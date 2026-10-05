#!/usr/bin/python2.7
# -*- coding: utf-8 -*-
# platform: macOS-only -- uses the system Python 2.7 and PyObjC that Mac OS X 10.9 ships
"""computer-use-mavericks: Mavericks-compatible replacement for the built-in
computer-use MCP. Speaks stdio JSON-RPC 2.0; tool surface mirrors the official
server shipped inside Claude Code (request_access, screenshot, zoom, click
variants with `coordinate`+`text` modifiers, scroll with direction/amount,
type, key, hold_key, wait, cursor_position, open_application, switch_display,
list_granted_applications, read_clipboard, write_clipboard, left_mouse_down/up,
left_click_drag, mouse_move, computer_batch). Mavericks deviations:

  - request_access / list_granted_applications are no-op stubs (no per-app
    sandbox enforcement on 10.9 — every app is granted).
  - screenshot has no compositor-level filtering; all open windows are visible.
  - The controlling terminal is auto-hidden before every screenshot, zoom, and
    input action (mirroring the official server's hide-before-action), so the
    screen the model acts on matches the screenshot it saw, and input cannot
    land in the Claude session. It is unhidden again after ~30s with no MCP
    activity (CU_MAVERICKS_UNHIDE_IDLE overrides) and at server shutdown.
    As a safety net for detection failures, every keyboard tool still checks
    the frontmost app and every pointer tool checks the live window z-order at
    the target point, refusing rather than delivering input into the terminal
    (the one "app" the official server's allowlist would never grant). The
    frontmost check runs BEFORE hiding, so an actively-used terminal is
    refused, not yanked away from the user.

Targets system /usr/bin/python2.7 (PyObjC bundled with the OS)."""
from __future__ import print_function, division

import errno
import json
import os
import select
import signal
import sys
import time
import traceback

# When the parent (claude) closes our stdio -- e.g. --print mode finishes
# before our async initialize response lands -- don't fill the log with
# broken-pipe tracebacks. Restoring SIGPIPE's default disposition means
# writes after the parent closes just kill us cleanly with no output.
try:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
except (AttributeError, ValueError):
    pass

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cu_actions as cu  # noqa: E402

_DEFAULT_LOG = os.path.join(
    os.path.expanduser("~"), ".cache", "claude-mavericks", "cu.log")
try:
    os.makedirs(os.path.dirname(_DEFAULT_LOG))
except OSError:
    pass  # exists or unwritable; open() below will surface real errors
LOG_PATH = os.environ.get("CU_MAVERICKS_LOG", _DEFAULT_LOG)
_LOG = open(LOG_PATH, "a", 1)


def log(*a):
    _LOG.write(time.strftime("%Y-%m-%d %H:%M:%S ") + " ".join(str(x) for x in a) + "\n")


def send(obj):
    s = json.dumps(obj, separators=(",", ":"), ensure_ascii=False)
    if isinstance(s, unicode):  # py2: dumps may return unicode
        s = s.encode("utf-8")
    try:
        sys.stdout.write(s + "\n")
        sys.stdout.flush()
    except IOError as e:
        if e.errno in (errno.EPIPE, errno.EBADF):
            _unhide_on_exit()  # parent died; don't leave the terminal hidden
            os._exit(0)
        raise
    log("->", s[:400])


def text_result(text, is_error=False):
    return {"content": [{"type": "text", "text": text}], "isError": is_error}


def _flat(x):
    return int(round(float(x)))


# Coordinate-space bridging. The model points at things in the *screenshot it
# last saw*; when we downscale for token cost, raw click coordinates would
# land at the wrong screen pixel. Cache the last screenshot's metadata and
# convert (x, y) on every tool that takes a coordinate.
_last_shot = None  # {width, height, displayId, originX, originY, displayWidth, displayHeight}
# Preferred display for the next screenshot. None = main display. Set by switch_display.
_preferred_display = None
# Whether left_mouse_down left the synthetic button held. Official semantics:
# left_mouse_down errors if already held; clicks/drags auto-release first.
_mouse_held = False


def _to_screen(x, y):
    if _last_shot is None:
        return _flat(x), _flat(y)
    sw = _last_shot["width"];        sh = _last_shot["height"]
    dw = _last_shot["displayWidth"]; dh = _last_shot["displayHeight"]
    ox = _last_shot["originX"];      oy = _last_shot["originY"]
    if sw <= 0 or sh <= 0 or (sw == dw and sh == dh):
        return _flat(x) + ox, _flat(y) + oy
    return _flat(x * dw / sw) + ox, _flat(y * dh / sh) + oy


def _from_screen(x, y):
    if _last_shot is None:
        return _flat(x), _flat(y)
    sw = _last_shot["width"];        sh = _last_shot["height"]
    dw = _last_shot["displayWidth"]; dh = _last_shot["displayHeight"]
    ox = _last_shot["originX"];      oy = _last_shot["originY"]
    if sw <= 0 or sh <= 0 or (sw == dw and sh == dh):
        return _flat(x) - ox, _flat(y) - oy
    return _flat((x - ox) * sw / dw), _flat((y - oy) * sh / dh)


# Schema fragments and shared description text, copied verbatim from the
# official server (models are tuned against its exact wording) except where a
# genuine Mavericks deviation forces a change.
_X_DESC = ("Horizontal pixel position read directly from the most recent screenshot image, "
           "measured from the left edge. The server handles all scaling.")
_COORD_SCHEMA = {
    "type": "array", "items": {"type": "number"}, "minItems": 2, "maxItems": 2,
    "description": "(x, y): " + _X_DESC,
}
_MODIFIER_TEXT_SCHEMA = {
    "type": "string",
    "description": 'Modifier keys to hold during the click (e.g. "shift", "ctrl+shift"). Supports the same syntax as the key tool.',
}
# Official allowlist sentence, appended to every input tool's description. True
# here too: the Mavericks session allowlist is "every app except the terminal
# hosting this Claude session".
_ALLOWLIST_SENTENCE = ("The frontmost application must be in the session allowlist at the time "
                       "of this call, or this tool returns an error and does nothing.")
_SAVE_TO_DISK_SCHEMA = {
    "type": "boolean",
    "description": (u"Save the image to disk so it can be attached to a message for the user. "
                    u"Returns the saved path in the tool result. Only set this when you intend "
                    u"to share the image — screenshots you're just looking at don't need "
                    u"saving."),
}


def _installed_apps():
    """Names of .app bundles in the standard locations. The official server
    lists installed apps inside the request_access schema; mirror that."""
    seen = []
    for d in ("/Applications", "/Applications/Utilities",
              os.path.expanduser("~/Applications")):
        try:
            entries = sorted(os.listdir(d))
        except OSError:
            continue
        for e in entries:
            if e.endswith(".app") and e[:-4] not in seen:
                seen.append(e[:-4])
    return seen[:80]

_APPS_AVAILABLE = _installed_apps()
_APPS_SUFFIX = (" Available applications on this machine: {0}.".format(", ".join(_APPS_AVAILABLE))
                if _APPS_AVAILABLE else "")


TOOLS = [
    {
        "name": "request_access",
        "description": (u"Request user permission to control a set of applications for this session. "
                        u"Must be called before any other tool in this server. Call this again "
                        u"mid-session to add more apps; previously granted apps remain granted. "
                        u"Returns the granted apps, denied apps, and screenshot filtering capability. "
                        u"(Mavericks port: there is no approval dialog — every requested app is "
                        u"granted immediately.)"),
        "inputSchema": {
            "type": "object",
            "properties": {
                "apps":            {"type": "array", "items": {"type": "string"},
                                    "description": ('Application display names (e.g. "Slack", "Calendar") or bundle '
                                                    'identifiers (e.g. "com.tinyspeck.slackmacgap"). Display names are '
                                                    'resolved case-insensitively against installed apps.' + _APPS_SUFFIX)},
                "reason":          {"type": "string",
                                    "description": "One-sentence explanation of why access is needed. Explain the task, not the mechanism."},
                "clipboardRead":   {"type": "boolean",
                                    "description": "Also request permission to read the user's clipboard."},
                "clipboardWrite":  {"type": "boolean",
                                    "description": "Also request permission to write the user's clipboard."},
                "systemKeyCombos": {"type": "boolean",
                                    "description": "Also request permission to send system-level key combos (quit app, switch app, lock screen)."},
            },
            "required": ["apps", "reason"],
        },
    },
    {
        "name": "screenshot",
        "description": (u"Take a screenshot of the primary display. On this platform, screenshots are "
                        u"NOT filtered — all open windows are visible, and input actions targeting "
                        u"apps not in the session allowlist (on this platform: only the terminal "
                        u"hosting this Claude session) are rejected. That terminal is hidden during "
                        u"capture and stays hidden while actions run, so the screen you act on "
                        u"matches this image; it reappears on its own when automation pauses. The "
                        u"returned image is what subsequent click coordinates are relative to."),
        "inputSchema": {
            "type": "object",
            "properties": {"save_to_disk": _SAVE_TO_DISK_SCHEMA},
            "required": [],
        },
    },
    {
        "name": "zoom",
        "description": ("Take a higher-resolution screenshot of a specific region of the last full-screen "
                        "screenshot. Use this liberally to inspect small text, button labels, or fine UI "
                        "details that are hard to read in the downsampled full-screen image. IMPORTANT: "
                        "Coordinates in subsequent click calls always refer to the full-screen "
                        "screenshot, never the zoomed image. This tool is read-only for inspecting detail."),
        "inputSchema": {
            "type": "object",
            "properties": {
                "region":       {"type": "array", "items": {"type": "integer"}, "minItems": 4, "maxItems": 4,
                                 "description": ("(x0, y0, x1, y1): Rectangle to zoom into, in the coordinate space of "
                                                 "the most recent full-screen screenshot. x0,y0 = top-left, "
                                                 "x1,y1 = bottom-right.")},
                "save_to_disk": _SAVE_TO_DISK_SCHEMA,
            },
            "required": ["region"],
        },
    },
    {"name": "left_click",   "description": "Left-click at the given coordinates. " + _ALLOWLIST_SENTENCE,
     "inputSchema": {"type": "object", "properties": {"coordinate": _COORD_SCHEMA, "text": _MODIFIER_TEXT_SCHEMA}, "required": ["coordinate"]}},
    {"name": "double_click", "description": "Double-click at the given coordinates. Selects a word in most text editors. " + _ALLOWLIST_SENTENCE,
     "inputSchema": {"type": "object", "properties": {"coordinate": _COORD_SCHEMA, "text": _MODIFIER_TEXT_SCHEMA}, "required": ["coordinate"]}},
    {"name": "triple_click", "description": "Triple-click at the given coordinates. Selects a line in most text editors. " + _ALLOWLIST_SENTENCE,
     "inputSchema": {"type": "object", "properties": {"coordinate": _COORD_SCHEMA, "text": _MODIFIER_TEXT_SCHEMA}, "required": ["coordinate"]}},
    {"name": "right_click",  "description": "Right-click at the given coordinates. Opens a context menu in most applications. " + _ALLOWLIST_SENTENCE,
     "inputSchema": {"type": "object", "properties": {"coordinate": _COORD_SCHEMA, "text": _MODIFIER_TEXT_SCHEMA}, "required": ["coordinate"]}},
    {"name": "middle_click", "description": "Middle-click (scroll-wheel click) at the given coordinates. " + _ALLOWLIST_SENTENCE,
     "inputSchema": {"type": "object", "properties": {"coordinate": _COORD_SCHEMA, "text": _MODIFIER_TEXT_SCHEMA}, "required": ["coordinate"]}},
    {
        "name": "type",
        "description": ("Type text into whatever currently has keyboard focus. " + _ALLOWLIST_SENTENCE +
                        " Newlines are supported. For keyboard shortcuts use `key` instead."),
        "inputSchema": {"type": "object", "properties": {"text": {"type": "string", "description": "Text to type."}}, "required": ["text"]},
    },
    {
        "name": "key",
        "description": ('Press a key or key combination (e.g. "return", "escape", "cmd+a", "ctrl+shift+tab"). ' + _ALLOWLIST_SENTENCE),
        "inputSchema": {
            "type": "object",
            "properties": {
                "text":   {"type": "string", "description": 'Modifiers joined with "+", e.g. "cmd+shift+a".'},
                "repeat": {"type": "integer", "minimum": 1, "maximum": 100, "description": "Number of times to repeat the key press. Default is 1."},
            },
            "required": ["text"],
        },
    },
    {
        "name": "scroll",
        "description": "Scroll at the given coordinates. " + _ALLOWLIST_SENTENCE,
        "inputSchema": {
            "type": "object",
            "properties": {
                "coordinate":       _COORD_SCHEMA,
                "scroll_direction": {"type": "string", "enum": ["up", "down", "left", "right"], "description": "Direction to scroll."},
                "scroll_amount":    {"type": "integer", "minimum": 0, "maximum": 100, "description": "Number of scroll ticks."},
            },
            "required": ["coordinate", "scroll_direction", "scroll_amount"],
        },
    },
    {
        "name": "left_click_drag",
        "description": "Press, move to target, and release. " + _ALLOWLIST_SENTENCE,
        "inputSchema": {
            "type": "object",
            "properties": {
                "coordinate":       dict(_COORD_SCHEMA, description="(x, y) end point: " + _X_DESC),
                "start_coordinate": dict(_COORD_SCHEMA, description="(x, y) start point. If omitted, drags from the current cursor position. " + _X_DESC),
            },
            "required": ["coordinate"],
        },
    },
    {"name": "mouse_move",
     "description": "Move the mouse cursor without clicking. Useful for triggering hover states. " + _ALLOWLIST_SENTENCE,
     "inputSchema": {"type": "object", "properties": {"coordinate": _COORD_SCHEMA}, "required": ["coordinate"]}},
    {
        "name": "open_application",
        "description": (u"Bring an application to the front, launching it if necessary. The target "
                        u"application must already be in the session allowlist — call request_access "
                        u"first. (Mavericks port: every app is granted.)"),
        "inputSchema": {
            "type": "object",
            "properties": {"app": {"type": "string", "description": 'Display name (e.g. "Slack") or bundle identifier (e.g. "com.tinyspeck.slackmacgap").'}},
            "required": ["app"],
        },
    },
    {
        "name": "switch_display",
        "description": (u"Switch which monitor subsequent screenshots capture. Use this when the "
                        u"application you need is on a different monitor than the one shown. The "
                        u"screenshot tool tells you which monitor it captured and lists other "
                        u"attached monitors by name — pass one of those names here. After "
                        u"switching, call screenshot to see the new monitor. Pass \"auto\" to "
                        u"return to automatic monitor selection."),
        "inputSchema": {
            "type": "object",
            "properties": {"display": {"type": "string",
                "description": 'Monitor name from the screenshot note (e.g. "display 69731906"), or "auto" to re-enable automatic selection.'}},
            "required": ["display"],
        },
    },
    {
        "name": "list_granted_applications",
        "description": ("List the applications currently in the session allowlist, plus the active "
                        "grant flags and coordinate mode. No side effects. (Mavericks port: every "
                        "running application is granted.)"),
        "inputSchema": {"type": "object", "properties": {}, "required": []},
    },
    {"name": "read_clipboard",  "description": "Read the current clipboard contents as text.",
     "inputSchema": {"type": "object", "properties": {}, "required": []}},
    {"name": "write_clipboard", "description": "Write text to the clipboard.",
     "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}},
    {
        "name": "wait",
        "description": "Wait for a specified duration.",
        "inputSchema": {
            "type": "object",
            "properties": {"duration": {"type": "number", "description": u"Duration in seconds (0–100)."}},
            "required": ["duration"],
        },
    },
    {"name": "cursor_position",
     "description": "Get the current mouse cursor position. Returns image-pixel coordinates relative to the most recent screenshot, or logical points if no screenshot has been taken.",
     "inputSchema": {"type": "object", "properties": {}, "required": []}},
    {
        "name": "hold_key",
        "description": ("Press and hold a key or key combination for the specified duration, then "
                        "release. " + _ALLOWLIST_SENTENCE),
        "inputSchema": {
            "type": "object",
            "properties": {
                "text":     {"type": "string", "description": 'Key or chord to hold, e.g. "space", "shift+down".'},
                "duration": {"type": "number", "description": u"Duration in seconds (0–100)."},
            },
            "required": ["text", "duration"],
        },
    },
    {"name": "left_mouse_down",
     "description": ("Press the left mouse button at the current cursor position and leave it held. " +
                     _ALLOWLIST_SENTENCE + " Use mouse_move first to position the cursor. Call "
                     "left_mouse_up to release. Errors if the button is already held."),
     "inputSchema": {"type": "object", "properties": {}, "required": []}},
    {"name": "left_mouse_up",
     "description": ("Release the left mouse button at the current cursor position. Pairs with "
                     "left_mouse_down. Safe to call even if the button is not currently held."),
     "inputSchema": {"type": "object", "properties": {}, "required": []}},
    {
        "name": "computer_batch",
        "description": (u"Execute a sequence of actions in ONE tool call. Each individual tool call "
                        u"requires a model→API round trip (seconds); batching a predictable sequence "
                        u"eliminates all but one. Use this whenever you can predict the outcome of "
                        u"several actions ahead — e.g. click a field, type into it, press Return. "
                        u"Actions execute sequentially and stop on the first error. " +
                        _ALLOWLIST_SENTENCE +
                        u" The frontmost check runs before EACH action inside the batch — if an "
                        u"action opens a non-allowed app, the next action's gate fires and the batch "
                        u"stops there. Mid-batch screenshot actions are allowed for inspection but "
                        u"coordinates in subsequent clicks always refer to the PRE-BATCH full-screen "
                        u"screenshot."),
        "inputSchema": {
            "type": "object",
            "properties": {"actions": {"type": "array", "minItems": 1, "items": {
                "type": "object",
                "properties": {
                    "action": {"type": "string",
                               "enum": ["key", "type", "mouse_move", "left_click", "left_click_drag",
                                        "right_click", "middle_click", "double_click", "triple_click",
                                        "scroll", "hold_key", "screenshot", "cursor_position",
                                        "left_mouse_down", "left_mouse_up", "wait"],
                               "description": "The action to perform."},
                    "coordinate":       {"type": "array", "items": {"type": "number"}, "minItems": 2, "maxItems": 2,
                                         "description": "(x, y) for click/mouse_move/scroll/left_click_drag end point."},
                    "start_coordinate": {"type": "array", "items": {"type": "number"}, "minItems": 2, "maxItems": 2,
                                         "description": u"(x, y) drag start — left_click_drag only. Omit to drag from current cursor."},
                    "text":             {"type": "string",
                                         "description": "For type: the text. For key/hold_key: the chord string. For click/scroll: modifier keys to hold."},
                    "scroll_direction": {"type": "string", "enum": ["up", "down", "left", "right"]},
                    "scroll_amount":    {"type": "integer", "minimum": 0, "maximum": 100},
                    "duration":         {"type": "number", "description": "For wait/hold_key: seconds."},
                },
                "required": ["action"],
            },
                "description": 'List of actions. Example: [{"action":"left_click","coordinate":[100,200]},{"action":"type","text":"hello"},{"action":"key","text":"Return"}]'}},
            "required": ["actions"],
        },
    },
]

# Actions the official server allows inside computer_batch (its `Jgo` set).
_BATCHABLE = frozenset([
    "key", "type", "mouse_move", "left_click", "left_click_drag", "right_click",
    "middle_click", "double_click", "triple_click", "scroll", "hold_key",
    "screenshot", "cursor_position", "left_mouse_down", "left_mouse_up", "wait",
])


# --- Helpers used by dispatch -------------------------------------------------

# Hide-before-action state (mirrors the official server's hideBeforeAction).
# The host terminal is hidden before every capture and input action and stays
# hidden while the model works; the idle loop in main() unhides it after
# _IDLE_UNHIDE seconds without MCP activity, and shutdown always unhides.
_IDLE_UNHIDE = float(os.environ.get("CU_MAVERICKS_UNHIDE_IDLE", "30"))
_we_hid = False          # we hid the host and haven't unhidden it yet
_last_activity = time.time()


def _touch_activity():
    global _last_activity
    _last_activity = time.time()


def _ensure_host_hidden():
    """Hide the controlling terminal if any of its windows are on screen.
    Returns True when this call actually transitioned it to hidden (drives the
    official-style 'got hidden' screenshot note). Idempotent: hide() on an
    already-hidden app is a cheap no-op, and the window-server query used to
    detect visibility is never stale, so manual unhides by the user are
    re-detected."""
    global _we_hid
    if not cu.HOST_BUNDLE:
        return False
    try:
        visible = any(w["layer"] == 0
                      for w in cu.list_window_locations([cu.HOST_BUNDLE]))
    except Exception:
        visible = True  # assume the worst; hiding twice is harmless
    r = cu.hide_host()
    if r.get("hidden"):
        _we_hid = True
    if visible:
        time.sleep(0.15)  # let WindowServer recomposite without the host
    return visible and bool(r.get("hidden"))


def _idle_tick():
    """Called by the stdin loop about once a second while no requests arrive.
    Restores the host terminal once the model has gone quiet."""
    global _we_hid
    if _we_hid and time.time() - _last_activity > _IDLE_UNHIDE:
        cu.unhide_host()
        _we_hid = False


def _unhide_on_exit():
    global _we_hid
    if _we_hid:
        try:
            cu.unhide_host()
        except Exception:
            pass
        _we_hid = False


def _do_screenshot():
    """Take a screenshot with the controlling terminal hidden (and left
    hidden). Updates the coordinate-space cache. Returns (shot, transitioned):
    the cu.screenshot() dict plus whether this capture actually hid the
    terminal (vs. it already being hidden from a previous action)."""
    global _last_shot
    transitioned = _ensure_host_hidden()
    shot = cu.screenshot(display_id=_preferred_display, max_dim=1600, jpeg_quality=0.65)
    _last_shot = {
        "width":         shot["width"],
        "height":        shot["height"],
        "displayId":     shot["displayId"],
        "displayWidth":  shot["displayWidth"],
        "displayHeight": shot["displayHeight"],
        "originX":       shot["originX"],
        "originY":       shot["originY"],
    }
    return shot, transitioned


# Input tools post synthetic HID events to whatever app currently holds
# keyboard focus -- there's no per-window addressing. If that's the controlling
# terminal, the keystrokes/clicks land in the Claude session itself. The
# official server guards every input tool by checking the frontmost app against
# its allowlist; this port has no real allowlist (every app is "granted"), so
# the one app we must never inject into is the host terminal. Mirror the
# official behavior: refuse and do nothing.
def _host_focus_block(action):
    """If the controlling terminal is frontmost, return an isError result to
    abort the input action; otherwise return None. No-op if we couldn't detect
    a host bundle (nothing to compare against)."""
    if not cu.HOST_BUNDLE:
        return None
    front = cu.frontmost_bundle()
    if front and front == cu.HOST_BUNDLE:
        # Wording follows the official server's app_not_granted error, with the
        # host-terminal context appended. Deliberately no anti-AppleScript
        # suffix: on this system AppleScript is a supported, often preferable
        # automation path for OTHER apps (just never for this terminal).
        return text_result(
            u'"{0}" is not in the allowed applications and is currently in front. '
            u'It is the terminal hosting this Claude session, so this input would '
            u'be delivered to the Claude session itself. Bring your target '
            u'application to the front first (e.g. with open_application), then '
            u'retry.'.format(cu.host_display_name() or cu.HOST_BUNDLE),
            is_error=True)
    return None


# Pointer events are routed by the window server to whatever window is really
# under the point -- and a click on a background window activates its app. The
# frontmost-app guard can't catch that: the controlling terminal isn't
# frontmost until the click MAKES it frontmost. Worse, screenshots hide the
# terminal, so the model may be aiming at an app it saw beneath a terminal
# window it cannot see. Check the live z-order at the target point.
def _host_point_block(action, sx, sy):
    """If the topmost window at screen point (sx, sy) belongs to the
    controlling terminal, return an isError result; otherwise None."""
    if not cu.HOST_BUNDLE:
        return None
    if cu.host_window_at_point(sx, sy):
        return text_result(
            u'{0} at these coordinates would land on "{1}", which is not in the '
            u'allowed applications — it is the terminal hosting this Claude '
            u'session, auto-hidden in screenshots but still on screen at that '
            u'location. To interact with what the screenshot shows there, bring '
            u'the target application forward with open_application, take a fresh '
            u'screenshot, and retry.'.format(
                action, cu.host_display_name() or cu.HOST_BUNDLE),
            is_error=True)
    return None


# --- Per-tool handlers --------------------------------------------------------

def _t_request_access(args):
    apps = args.get("apps") or []
    granted = [{"app": a, "tier": "full"} for a in apps]
    return text_result(json.dumps({
        "granted": granted, "denied": [],
        "screenshotFiltering": "none",
        "note": "Mavericks port: no per-app enforcement; all apps auto-granted.",
    }))


# Monitor naming: 10.9 has no supported API for human-readable display names,
# so use the official server's fallback naming scheme ("display <id>"). The
# screenshot note and switch_display speak the same names.
def _display_name(did):
    return u"display {0}".format(did)


_prev_shot_display = None  # displayId of the previous screenshot, for the monitor-change note


def _display_note(did):
    """Official-style monitor note: emitted only when >1 monitor is attached,
    and only on the first screenshot or when the captured monitor changed."""
    disps = cu.list_displays()
    if len(disps) < 2:
        return None
    others = [_display_name(d["displayId"]) for d in disps if d["displayId"] != did]
    tail = u""
    if others:
        tail = (u" Other attached monitors: {0}."
                u" Use switch_display to capture a different monitor.".format(
                    u", ".join(u'"{0}"'.format(o) for o in others)))
    if _prev_shot_display is None:
        return u'This screenshot was taken on monitor "{0}".'.format(_display_name(did)) + tail
    if _prev_shot_display != did:
        return (u'This screenshot was taken on monitor "{0}", which is different from your '
                u'previous screenshot (taken on "{1}").'.format(
                    _display_name(did), _display_name(_prev_shot_display)) + tail)
    return None


def _host_hidden_note(transitioned, had_prev_shot):
    """Official cadence: the hidden-apps note lists only apps hidden by THIS
    capture, and is suppressed on the first screenshot (there is no earlier
    action whose effect it could explain)."""
    if not (transitioned and had_prev_shot):
        return None
    return (u'"{0}" was open and got hidden before this screenshot (it hosts this Claude '
            u'session and is not in the session allowlist). It stays hidden while actions '
            u'run and reappears when automation pauses.'.format(
                cu.host_display_name() or cu.HOST_BUNDLE))


def _t_screenshot(args):
    global _prev_shot_display
    had_prev_shot = _last_shot is not None
    shot, transitioned = _do_screenshot()
    # Official result shape: optional text notes FIRST, then the image, and no
    # dimension caption -- the coordinate schema already tells the model "the
    # server handles all scaling".
    content = []
    note = _display_note(shot["displayId"])
    if note:
        content.append({"type": "text", "text": note})
    _prev_shot_display = shot["displayId"]
    hidden_note = _host_hidden_note(transitioned, had_prev_shot)
    if hidden_note:
        content.append({"type": "text", "text": hidden_note})
    if args.get("save_to_disk"):
        path = cu.write_jpeg_to_disk(shot["base64"])
        content.append({"type": "text", "text": u"Screenshot saved to {0}.".format(path)})
    content.append({"type": "image", "data": shot["base64"], "mimeType": "image/jpeg"})
    return {"content": content, "isError": False}


def _t_zoom(args):
    # Validation messages match the official server's.
    region = args.get("region")
    if not (isinstance(region, list) and len(region) == 4):
        return text_result("region must be an array of length 4: [x0, y0, x1, y1]", is_error=True)
    if not all(isinstance(v, (int, float)) and v >= 0 for v in region):
        return text_result("region values must be non-negative numbers", is_error=True)
    x0, y0, x1, y1 = region
    if x1 <= x0:
        return text_result("region x1 must be greater than x0", is_error=True)
    if y1 <= y0:
        return text_result("region y1 must be greater than y0", is_error=True)
    if _last_shot is None:
        return text_result("take a screenshot before zooming (region coords are relative to it)", is_error=True)
    if x1 > _last_shot["width"] or y1 > _last_shot["height"]:
        return text_result(u"region exceeds screenshot bounds ({0}×{1})".format(
            _last_shot["width"], _last_shot["height"]), is_error=True)
    sx0, sy0 = _to_screen(x0, y0)
    sx1, sy1 = _to_screen(x1, y1)
    # zoom recaptures the display live; keep the host terminal hidden like
    # screenshot does, or the zoomed image could show a terminal the full
    # capture omitted.
    _ensure_host_hidden()
    z = cu.zoom_region(_last_shot["displayId"], (sx0, sy0, sx1 - sx0, sy1 - sy0))
    content = []
    if args.get("save_to_disk"):
        path = cu.write_jpeg_to_disk(z["base64"])
        content.append({"type": "text", "text": u"Zoom image saved to {0}.".format(path)})
    content.append({"type": "image", "data": z["base64"], "mimeType": "image/jpeg"})
    return {"content": content, "isError": False}


def _release_if_held():
    """Official behavior: a click or drag issued while left_mouse_down left the
    button held releases it first instead of erroring."""
    global _mouse_held
    if _mouse_held:
        cu.left_mouse_up()
        _mouse_held = False


def _click_handler(tool_name):
    fn = getattr(cu, tool_name)
    def _h(args):
        blk = _host_focus_block(tool_name)
        if blk:
            return blk
        _ensure_host_hidden()
        cx, cy = args["coordinate"]
        sx, sy = _to_screen(cx, cy)
        blk = _host_point_block("Click", sx, sy)
        if blk:
            return blk
        _release_if_held()
        flags = cu.parse_modifiers(args.get("text", ""))
        fn(sx, sy, flags)
        return text_result("Clicked.")
    return _h


def _t_type(args):
    blk = _host_focus_block("type")
    if blk:
        return blk
    _ensure_host_hidden()
    cu.type_text(args["text"])
    return text_result("Typed {0} grapheme(s).".format(len(args["text"])))


def _t_key(args):
    blk = _host_focus_block("key")
    if blk:
        return blk
    _ensure_host_hidden()
    repeat = int(args.get("repeat", 1))
    cu.key(args["text"], repeat=repeat)
    return text_result("Key pressed.")


def _t_scroll(args):
    blk = _host_focus_block("scroll")
    if blk:
        return blk
    _ensure_host_hidden()
    cx, cy = args["coordinate"]
    sx, sy = _to_screen(cx, cy)
    # Scroll events go to the window under the cursor, not the focused app.
    blk = _host_point_block("Scroll", sx, sy)
    if blk:
        return blk
    cu.scroll_directional(sx, sy, args["scroll_direction"], int(args["scroll_amount"]))
    return text_result("Scrolled.")


def _t_left_click_drag(args):
    blk = _host_focus_block("left_click_drag")
    if blk:
        return blk
    _ensure_host_hidden()
    ex, ey = args["coordinate"]
    sex, sey = _to_screen(ex, ey)
    blk = _host_point_block("Drag ending", sex, sey)
    if blk:
        return blk
    if "start_coordinate" in args:
        sx, sy = args["start_coordinate"]
        ssx, ssy = _to_screen(sx, sy)
        blk = _host_point_block("Drag starting", ssx, ssy)
        if blk:
            return blk
        _release_if_held()
        cu.left_click_drag(sex, sey, ssx, ssy)
        return text_result("Dragged.")
    p = cu.cursor_position()
    blk = _host_point_block("Drag starting", p["x"], p["y"])
    if blk:
        return blk
    _release_if_held()
    cu.left_click_drag(sex, sey)
    return text_result("Dragged.")


def _t_mouse_move(args):
    blk = _host_focus_block("mouse_move")
    if blk:
        return blk
    _ensure_host_hidden()
    cx, cy = args["coordinate"]
    sx, sy = _to_screen(cx, cy)
    cu.mouse_move(sx, sy)
    return text_result("Moved.")


def _t_open_application(args):
    r = cu.open_application(args["app"])
    if not r.get("launched"):
        return text_result(u'Could not open "{0}". Check the name or bundle id — '
                           u'installed apps are listed in the request_access schema.'.format(args["app"]),
                           is_error=True)
    msg = u'Opened "{0}".'.format(args["app"])
    if not r.get("activated"):
        msg += u" " + r.get("note", u"Not yet confirmed frontmost; verify with a screenshot before typing.")
    return text_result(msg)


def _t_switch_display(args):
    global _preferred_display
    name = args["display"].strip()
    if name.lower() == "auto":
        _preferred_display = None
        return text_result("Returned to automatic monitor selection. Call screenshot to continue.")
    for d in cu.list_displays():
        # Accept the official-style monitor name from the screenshot note
        # ("display <id>") or a bare id string.
        if name.lower() in (_display_name(d["displayId"]).lower(), str(d["displayId"])):
            _preferred_display = d["displayId"]
            return text_result(u'Switched to monitor "{0}". Call screenshot to see it.'.format(
                _display_name(d["displayId"])))
    return text_result(u'No monitor named "{0}". Attached monitors: {1}.'.format(
        name, u", ".join(u'"{0}"'.format(_display_name(d["displayId"]))
                         for d in cu.list_displays())), is_error=True)


def _t_list_granted_applications(args):
    running = cu.list_running_applications()
    return text_result(json.dumps({
        "granted": [{"app": a["bundleId"], "tier": "full"} for a in running],
        "grantFlags": {"clipboardRead": True, "clipboardWrite": True, "systemKeyCombos": True},
        "screenshotFiltering": "none",
        "coordinateMode": "pixels",
        "note": "Mavericks port: every running app reported as granted.",
    }, indent=2))


def _t_read_clipboard(args):
    return text_result(cu.read_clipboard())


def _t_write_clipboard(args):
    cu.write_clipboard(args["text"])
    return text_result("Clipboard written.")


def _t_wait(args):
    dur = args["duration"]
    try:
        sec = float(dur)
    except (TypeError, ValueError):
        return text_result("duration must be a number", is_error=True)
    if sec < 0:
        return text_result("duration must be non-negative", is_error=True)
    if sec > 100:
        return text_result("duration is too long. Duration is in seconds.", is_error=True)
    cu.wait(int(sec * 1000))
    return text_result("Waited {0:g}s.".format(sec))


def _t_cursor_position(args):
    # Mirrors the official handler: image-pixel coordinates when the cursor is
    # on the last-screenshotted display, logical points (with a note) otherwise.
    p = cu.cursor_position()
    if _last_shot is not None:
        ox = p["x"] - _last_shot["originX"]
        oy = p["y"] - _last_shot["originY"]
        if ox < 0 or ox > _last_shot["displayWidth"] or oy < 0 or oy > _last_shot["displayHeight"]:
            return text_result(json.dumps({
                "x": p["x"], "y": p["y"], "coordinateSpace": "logical_points",
                "note": "cursor is on a different monitor than your last screenshot; take a fresh screenshot",
            }))
        sx = _flat(ox * _last_shot["width"] / _last_shot["displayWidth"])
        sy = _flat(oy * _last_shot["height"] / _last_shot["displayHeight"])
        return text_result(json.dumps({"x": sx, "y": sy, "coordinateSpace": "image_pixels"}))
    return text_result(json.dumps({"x": p["x"], "y": p["y"], "coordinateSpace": "logical_points"}))


def _t_hold_key(args):
    blk = _host_focus_block("hold_key")
    if blk:
        return blk
    _ensure_host_hidden()
    sec = min(100, max(0, float(args["duration"])))
    cu.hold_key(args["text"], duration=sec)
    return text_result("Key held.")


def _t_left_mouse_down(args):
    global _mouse_held
    blk = _host_focus_block("left_mouse_down")
    if blk:
        return blk
    if _mouse_held:
        return text_result("The left mouse button is already held. Call left_mouse_up to release it first.",
                           is_error=True)
    _ensure_host_hidden()
    p = cu.cursor_position()
    blk = _host_point_block("Pressing the mouse button", p["x"], p["y"])
    if blk:
        return blk
    cu.left_mouse_down()
    _mouse_held = True
    return text_result("Mouse button pressed.")


def _t_left_mouse_up(args):
    # Deliberately unguarded: refusing a release would leave the synthetic
    # button stuck down, which is worse than any input a lone mouse-up can
    # deliver to the terminal. Official: "Safe to call even if the button is
    # not currently held."
    global _mouse_held
    cu.left_mouse_up()
    _mouse_held = False
    return text_result("Mouse button released.")


def _t_computer_batch(args):
    global _last_shot
    actions = args["actions"]
    pre_shot = _last_shot
    lines = []       # one summary line per action
    images = []      # image blocks from mid-batch screenshots, passed through
    ok = True
    for idx, act in enumerate(actions):
        name = act.get("action")
        sub_args = {k: v for k, v in act.items() if k != "action"}
        if name not in _BATCHABLE:
            lines.append("action {0} ({1}): error - not a batchable action".format(idx, name))
            ok = False
            break
        try:
            r = HANDLERS[name](sub_args)
        except Exception as e:
            lines.append("action {0} ({1}): error - {2}: {3}".format(idx, name, type(e).__name__, e))
            ok = False
            break
        if name == "screenshot":
            # Official contract: coordinates in subsequent actions always refer
            # to the PRE-BATCH screenshot; a mid-batch capture is inspection-only.
            _last_shot = pre_shot
        texts = [c["text"] for c in r["content"] if c.get("type") == "text"]
        images.extend(c for c in r["content"] if c.get("type") == "image")
        lines.append("action {0} ({1}): {2}".format(idx, name, " ".join(texts) if texts else "ok"))
        if r.get("isError"):
            ok = False
            break
        # Focus changes (a click activating an app) are asynchronous. Between
        # MCP calls the model round-trip provides the settle time; inside a
        # batch we must pace explicitly, or a `type` 5ms after a click gets
        # delivered to the previously-focused app.
        if idx < len(actions) - 1:
            time.sleep(0.2)
    done = len(lines) if ok else len(lines) - 1
    lines.append("Batch {0}: {1} of {2} action(s) completed.".format(
        "finished" if ok else "stopped", done, len(actions)))
    content = [{"type": "text", "text": "\n".join(lines)}] + images
    return {"content": content, "isError": not ok}


HANDLERS = {
    "request_access":             _t_request_access,
    "screenshot":                 _t_screenshot,
    "zoom":                       _t_zoom,
    "left_click":                 _click_handler("left_click"),
    "right_click":                _click_handler("right_click"),
    "middle_click":               _click_handler("middle_click"),
    "double_click":               _click_handler("double_click"),
    "triple_click":               _click_handler("triple_click"),
    "type":                       _t_type,
    "key":                        _t_key,
    "scroll":                     _t_scroll,
    "left_click_drag":            _t_left_click_drag,
    "mouse_move":                 _t_mouse_move,
    "open_application":           _t_open_application,
    "switch_display":             _t_switch_display,
    "list_granted_applications":  _t_list_granted_applications,
    "read_clipboard":             _t_read_clipboard,
    "write_clipboard":            _t_write_clipboard,
    "wait":                       _t_wait,
    "cursor_position":            _t_cursor_position,
    "hold_key":                   _t_hold_key,
    "left_mouse_down":            _t_left_mouse_down,
    "left_mouse_up":              _t_left_mouse_up,
    "computer_batch":             _t_computer_batch,
}


def _call_tool(name, args):
    h = HANDLERS.get(name)
    if h is None:
        return text_result("unknown tool: {0}".format(name), is_error=True)
    return h(args or {})


def _stdin_lines():
    """Yield newline-delimited messages from fd 0, calling _idle_tick() about
    once a second while no data arrives. Reads via os.read + select rather
    than sys.stdin.readline: readline never returns control while the parent
    is quiet (so the idle unhide could never run), and Python 2's readahead
    could buffer past the line select() reported. Also avoids the historical
    `for line in sys.stdin` block-buffering hang (claude's 5s MCP handshake
    timeout vs. an initialize message stuck in an ~8KB readahead buffer)."""
    fd = sys.stdin.fileno()
    buf = b""
    while True:
        nl = buf.find(b"\n")
        if nl >= 0:
            line = buf[:nl]
            buf = buf[nl + 1:]
            yield line
            continue
        try:
            ready, _, _ = select.select([fd], [], [], 1.0)
        except select.error as e:
            if e.args and e.args[0] == errno.EINTR:
                continue
            raise
        if not ready:
            _idle_tick()
            continue
        chunk = os.read(fd, 65536)
        if not chunk:
            if buf:
                yield buf
            return
        buf += chunk


def _on_signal(sig, _frame):
    # claude stops MCP servers with SIGTERM, which would skip main()'s finally
    # and leave the user's terminal hidden.
    _unhide_on_exit()
    os._exit(0)


def main():
    log("started pid={0} argv={1}".format(os.getpid(), sys.argv))
    for _sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        try:
            signal.signal(_sig, _on_signal)
        except (ValueError, RuntimeError):
            pass
    try:
        for line in _stdin_lines():
            line = line.strip()
            if not line:
                continue
            log("<-", line[:400])
            try:
                msg = json.loads(line)
            except Exception as e:
                log("parse error:", e, "line:", line[:200])
                continue

            mid = msg.get("id")
            method = msg.get("method")

            if method == "initialize":
                p_in = msg.get("params") or {}
                pv = p_in.get("protocolVersion") or "2024-11-05"
                send({
                    "jsonrpc": "2.0", "id": mid,
                    "result": {
                        "protocolVersion": pv,
                        "capabilities": {"tools": {}},
                        "serverInfo": {"name": "computer-use-mavericks", "version": "0.5.0"},
                    },
                })
            elif method == "notifications/initialized":
                log("initialized")
            elif method == "tools/list":
                send({"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS}})
            elif method == "tools/call":
                p = msg.get("params", {})
                name = p.get("name") or ""
                args = p.get("arguments") or {}
                # Touch before AND after: a long-running call (wait, hold_key,
                # a big batch) must not count toward the idle-unhide timer.
                _touch_activity()
                try:
                    result = _call_tool(name, args)
                except Exception as e:
                    log("tool error:", name, e, traceback.format_exc())
                    result = text_result("{0}: {1}".format(type(e).__name__, e), is_error=True)
                _touch_activity()
                send({"jsonrpc": "2.0", "id": mid, "result": result})
            elif method == "ping":
                send({"jsonrpc": "2.0", "id": mid, "result": {}})
            elif mid is not None:
                send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "method not found: {0}".format(method)}})
    except KeyboardInterrupt:
        pass
    except Exception as e:
        log("fatal:", e, traceback.format_exc())
        raise
    finally:
        _unhide_on_exit()


if __name__ == "__main__":
    main()
