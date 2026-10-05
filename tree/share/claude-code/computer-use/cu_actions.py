# -*- coding: utf-8 -*-
# platform: macOS-only -- uses the system Python 2.7 and PyObjC that Mac OS X 10.9 ships
"""Mavericks-compatible computer-use primitives. Uses PyObjC's Quartz + AppKit.

Targets system /usr/bin/python2.7 (Mavericks ships PyObjC bundled).
"""
from __future__ import print_function, division

import base64
import hashlib
import os
import time

import Quartz
import AppKit
from Foundation import NSRunLoop, NSDate
from Quartz import (
    CGDisplayCreateImage,
    CGMainDisplayID,
    CGGetActiveDisplayList,
    CGDisplayBounds,
    CGDisplayPixelsWide,
    CGDisplayPixelsHigh,
    CGEventCreate,
    CGEventGetLocation,
    CGEventPost,
    CGEventCreateMouseEvent,
    CGEventCreateKeyboardEvent,
    CGEventKeyboardSetUnicodeString,
    CGEventCreateScrollWheelEvent,
    kCGHIDEventTap,
    kCGEventMouseMoved,
    kCGEventLeftMouseDown,
    kCGEventLeftMouseUp,
    kCGEventRightMouseDown,
    kCGEventRightMouseUp,
    kCGEventOtherMouseDown,
    kCGEventOtherMouseUp,
    kCGEventLeftMouseDragged,
    kCGMouseButtonLeft,
    kCGMouseButtonRight,
    kCGMouseButtonCenter,
    kCGScrollEventUnitPixel,
    kCGEventFlagMaskShift,
    kCGEventFlagMaskControl,
    kCGEventFlagMaskAlternate,
    kCGEventFlagMaskCommand,
    kCGEventFlagMaskSecondaryFn,
    CGEventSetFlags,
    CGEventSetIntegerValueField,
    kCGMouseEventClickState,
)

# Stay invisible: no Dock icon, no menu bar. Must run before any AppKit code
# touches NSApp -- Quartz's CGEvent* functions don't trigger app registration,
# but NSWorkspace launching apps does, which is enough to make the host
# Python process show up in the Dock.
_NSApp = AppKit.NSApplication.sharedApplication()
_NSApp.setActivationPolicy_(AppKit.NSApplicationActivationPolicyProhibited)


# NSWorkspace's frontmostApplication / runningApplications are KVO properties
# that AppKit refreshes ONLY when this process's run loop spins. The MCP server
# blocks in stdin.readline() and never runs a run loop, so without an explicit
# pump those properties are frozen at whatever was true the last time the loop
# ran (typically server startup). Pump briefly before any NSWorkspace read that
# must reflect the current state of the world.
def _pump(seconds=0.05):
    NSRunLoop.currentRunLoop().runUntilDate_(
        NSDate.dateWithTimeIntervalSinceNow_(float(seconds)))

# --- Host (controlling terminal) detection -----------------------------------
_TERM_BUNDLE_BY_PROGRAM = {
    "Apple_Terminal":  "com.apple.Terminal",
    "iTerm.app":       "com.googlecode.iterm2",
    "ghostty":         "com.mitchellh.ghostty",
    "kitty":           "net.kovidgoyal.kitty",
    "WarpTerminal":    "dev.warp.Warp-Stable",
    "vscode":          "com.microsoft.VSCode",
}

def detect_host_bundle():
    bid = os.environ.get("__CFBundleIdentifier")
    if bid:
        return bid
    return _TERM_BUNDLE_BY_PROGRAM.get(os.environ.get("TERM_PROGRAM", ""))

HOST_BUNDLE = detect_host_bundle()


# str() in Python 2 ASCII-encodes when the NSString carries non-ASCII (e.g. em
# dashes in window titles). Always go through unicode and let JSON encode UTF-8.
try:
    _text = unicode  # Py2
except NameError:
    _text = str      # Py3


def _txt(x):
    if x is None:
        return u""
    if isinstance(x, bytes):
        return x.decode("utf-8", "replace")
    return _text(x)


# ---------- Displays ----------
def list_displays():
    err, ids, count = CGGetActiveDisplayList(16, None, None)
    out = []
    main = CGMainDisplayID()
    for did in ids[:count]:
        b = CGDisplayBounds(did)
        out.append({
            "displayId": int(did),
            "isMain": bool(did == main),
            "originX": int(b.origin.x),
            "originY": int(b.origin.y),
            "width": int(b.size.width),
            "height": int(b.size.height),
            "pixelsWide": int(CGDisplayPixelsWide(did)),
            "pixelsHigh": int(CGDisplayPixelsHigh(did)),
        })
    return out


# ---------- Screenshot ----------
def screenshot(display_id=None, jpeg_quality=0.65, max_dim=1600):
    """Return dict with base64, width, height, displayId, originX, originY, displayWidth, displayHeight."""
    did = display_id if display_id is not None else int(CGMainDisplayID())
    img = CGDisplayCreateImage(did)
    if img is None:
        raise RuntimeError("CGDisplayCreateImage failed for display {0}".format(did))

    rep = AppKit.NSBitmapImageRep.alloc().initWithCGImage_(img)
    w = int(CGDisplayPixelsWide(did))
    h = int(CGDisplayPixelsHigh(did))
    out_w, out_h = w, h
    if max_dim and max(w, h) > max_dim:
        scale = max_dim / float(max(w, h))
        out_w = int(w * scale)
        out_h = int(h * scale)
        ns_image = AppKit.NSImage.alloc().initWithSize_(AppKit.NSMakeSize(out_w, out_h))
        ns_image.lockFocus()
        src_rect = AppKit.NSMakeRect(0, 0, w, h)
        dst_rect = AppKit.NSMakeRect(0, 0, out_w, out_h)
        rep.drawInRect_fromRect_operation_fraction_respectFlipped_hints_(
            dst_rect, src_rect, AppKit.NSCompositeCopy, 1.0, True, None,
        )
        ns_image.unlockFocus()
        tiff = ns_image.TIFFRepresentation()
        rep = AppKit.NSBitmapImageRep.imageRepWithData_(tiff)

    props = {AppKit.NSImageCompressionFactor: float(jpeg_quality)}
    data = rep.representationUsingType_properties_(AppKit.NSJPEGFileType, props)
    raw = bytes(data)
    b64 = base64.b64encode(raw).decode("ascii")

    bounds = CGDisplayBounds(did)
    return {
        "base64": b64,
        "width": out_w,
        "height": out_h,
        "displayId": int(did),
        "originX": int(bounds.origin.x),
        "originY": int(bounds.origin.y),
        "displayWidth": w,
        "displayHeight": h,
    }


def zoom_region(display_id, region_screen, jpeg_quality=0.85):
    """Capture (x, y, w, h) in *display* (screen) pixel coords at full
    resolution. Caller is responsible for translating screenshot-space
    coordinates into screen-space before invoking. Returns dict like
    screenshot() but with no max_dim downscale."""
    rx, ry, rw, rh = region_screen
    img = CGDisplayCreateImage(display_id)
    if img is None:
        raise RuntimeError("CGDisplayCreateImage failed for display {0}".format(display_id))
    rep = AppKit.NSBitmapImageRep.alloc().initWithCGImage_(img)
    full_w = int(CGDisplayPixelsWide(display_id))
    full_h = int(CGDisplayPixelsHigh(display_id))
    rx = max(0, min(int(rx), full_w - 1))
    ry = max(0, min(int(ry), full_h - 1))
    rw = max(1, min(int(rw), full_w - rx))
    rh = max(1, min(int(rh), full_h - ry))
    cropped = AppKit.NSImage.alloc().initWithSize_(AppKit.NSMakeSize(rw, rh))
    cropped.lockFocus()
    rep.drawInRect_fromRect_operation_fraction_respectFlipped_hints_(
        AppKit.NSMakeRect(0, 0, rw, rh),
        AppKit.NSMakeRect(rx, full_h - ry - rh, rw, rh),
        AppKit.NSCompositeCopy, 1.0, True, None,
    )
    cropped.unlockFocus()
    out_rep = AppKit.NSBitmapImageRep.imageRepWithData_(cropped.TIFFRepresentation())
    data = out_rep.representationUsingType_properties_(
        AppKit.NSJPEGFileType, {AppKit.NSImageCompressionFactor: float(jpeg_quality)})
    return {
        "base64": base64.b64encode(bytes(data)).decode("ascii"),
        "width": rw, "height": rh,
        "displayId": int(display_id),
        "regionScreen": [rx, ry, rw, rh],
    }


def write_jpeg_to_disk(b64):
    """Decode a base64 JPEG and drop it in /tmp with a unique name. Returns
    the full path. Used by screenshot/zoom save_to_disk."""
    import tempfile
    fd, path = tempfile.mkstemp(prefix="cu-mavericks-", suffix=".jpg", dir="/tmp")
    try:
        os.write(fd, base64.b64decode(b64))
    finally:
        os.close(fd)
    return path


# ---------- Mouse ----------
def cursor_position():
    e = CGEventCreate(None)
    p = CGEventGetLocation(e)
    return {"x": int(p.x), "y": int(p.y)}


def _post_mouse(kind, x, y, button, click_count=1, flags=0):
    ev = CGEventCreateMouseEvent(None, kind, (x, y), button)
    # WebKit and many AppKit controls treat clickState=0 as "not really a click"
    # and won't move focus to a text input on a click whose state is 0. Always
    # set it to >=1 for mouse-down/up; pure mouse moves don't carry the field.
    if kind != kCGEventMouseMoved:
        CGEventSetIntegerValueField(ev, kCGMouseEventClickState, max(1, int(click_count)))
    if flags:
        CGEventSetFlags(ev, flags)
    CGEventPost(kCGHIDEventTap, ev)


def mouse_move(x, y):
    _post_mouse(kCGEventMouseMoved, float(x), float(y), kCGMouseButtonLeft)


def _click(button, x, y, click_count=1, flags=0):
    x = float(x); y = float(y)
    if button == "left":
        down, up, btn = kCGEventLeftMouseDown, kCGEventLeftMouseUp, kCGMouseButtonLeft
    elif button == "right":
        down, up, btn = kCGEventRightMouseDown, kCGEventRightMouseUp, kCGMouseButtonRight
    elif button == "middle":
        down, up, btn = kCGEventOtherMouseDown, kCGEventOtherMouseUp, kCGMouseButtonCenter
    else:
        raise ValueError("unknown button: {0}".format(button))
    for i in range(1, click_count + 1):
        _post_mouse(down, x, y, btn, i, flags)
        _post_mouse(up, x, y, btn, i, flags)


def left_click(x, y, flags=0):       _click("left", x, y, 1, flags)
def right_click(x, y, flags=0):      _click("right", x, y, 1, flags)
def middle_click(x, y, flags=0):     _click("middle", x, y, 1, flags)
def double_click(x, y, flags=0):     _click("left", x, y, 2, flags)
def triple_click(x, y, flags=0):     _click("left", x, y, 3, flags)


def left_mouse_down(x=None, y=None):
    if x is None or y is None:
        p = cursor_position(); x, y = p["x"], p["y"]
    _post_mouse(kCGEventLeftMouseDown, float(x), float(y), kCGMouseButtonLeft)


def left_mouse_up(x=None, y=None):
    if x is None or y is None:
        p = cursor_position(); x, y = p["x"], p["y"]
    _post_mouse(kCGEventLeftMouseUp, float(x), float(y), kCGMouseButtonLeft)


def left_click_drag(end_x, end_y, start_x=None, start_y=None, steps=20, dwell=0.01):
    if start_x is None or start_y is None:
        p = cursor_position(); start_x, start_y = p["x"], p["y"]
    sx, sy, ex, ey = map(float, (start_x, start_y, end_x, end_y))
    _post_mouse(kCGEventLeftMouseDown, sx, sy, kCGMouseButtonLeft)
    for i in range(1, steps + 1):
        t = i / steps
        x = sx + (ex - sx) * t
        y = sy + (ey - sy) * t
        _post_mouse(kCGEventLeftMouseDragged, x, y, kCGMouseButtonLeft)
        time.sleep(dwell)
    _post_mouse(kCGEventLeftMouseUp, ex, ey, kCGMouseButtonLeft)


# kCGScrollEventUnitLine = 1; conventional "ticks" map to lines, not pixels.
_kCGScrollEventUnitLine = 1


def scroll_directional(x, y, direction, amount):
    """Scroll N ticks in the given direction at (x, y). Matches the official
    server's scroll_direction + scroll_amount semantics."""
    mouse_move(x, y)
    a = int(amount)
    if direction == "up":      dy, dx = a, 0
    elif direction == "down":  dy, dx = -a, 0
    elif direction == "left":  dy, dx = 0, a
    elif direction == "right": dy, dx = 0, -a
    else:
        raise ValueError("scroll direction must be up/down/left/right, got {0!r}".format(direction))
    ev = CGEventCreateScrollWheelEvent(None, _kCGScrollEventUnitLine, 2, dy, dx)
    CGEventPost(kCGHIDEventTap, ev)


# ---------- Keyboard ----------
# Virtual keycodes -- standard US layout (Carbon/HIToolbox).
_KEYCODES = {
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
    "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
    "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45,
    "m": 46, ".": 47, "`": 50,
    "space": 49, "return": 36, "enter": 36, "tab": 48, "escape": 53, "esc": 53,
    "delete": 51, "backspace": 51, "forwarddelete": 117,
    "up": 126, "down": 125, "left": 123, "right": 124,
    "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
    "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    "shift": 56, "control": 59, "ctrl": 59, "option": 58, "alt": 58,
    "command": 55, "cmd": 55, "meta": 55, "fn": 63,
}

_MODIFIER_FLAGS = {
    "shift":   kCGEventFlagMaskShift,
    "control": kCGEventFlagMaskControl,
    "ctrl":    kCGEventFlagMaskControl,
    "option":  kCGEventFlagMaskAlternate,
    "alt":     kCGEventFlagMaskAlternate,
    "command": kCGEventFlagMaskCommand,
    "cmd":     kCGEventFlagMaskCommand,
    "meta":    kCGEventFlagMaskCommand,
    "fn":      kCGEventFlagMaskSecondaryFn,
}


# Char -> (virtual keycode, modifier flags). Used by type_text so that
# synthesized events have a keycode matching the character — a Mavericks
# NSOpenPanel sheet path-completion handler reads the physical keycode and
# bails (cancelling the panel + parent) when keycode 0 ('a') is paired with
# any other character via CGEventKeyboardSetUnicodeString. Built from the US
# QWERTY layout; non-Latin chars fall back to keycode 0 + unicode override.
_SHIFT = kCGEventFlagMaskShift
_CHAR_TO_KEY = {}
for ch, kc in {
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
    "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
    "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45,
    "m": 46, ".": 47, "`": 50,
    " ": 49, "\t": 48, "\n": 36, "\r": 36,
}.items():
    _CHAR_TO_KEY[ch] = (kc, 0)
for ch, sh in {
    "A": "a", "B": "b", "C": "c", "D": "d", "E": "e", "F": "f", "G": "g", "H": "h",
    "I": "i", "J": "j", "K": "k", "L": "l", "M": "m", "N": "n", "O": "o", "P": "p",
    "Q": "q", "R": "r", "S": "s", "T": "t", "U": "u", "V": "v", "W": "w", "X": "x",
    "Y": "y", "Z": "z",
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8",
    "(": "9", ")": "0",
    "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", '"': "'",
    "<": ",", ">": ".", "?": "/", "~": "`",
}.items():
    _CHAR_TO_KEY[ch] = (_CHAR_TO_KEY[sh][0], _SHIFT)


def _parse_combo(combo):
    # Convention: the LAST '+'-separated token is the held key; everything
    # before it is a modifier. So "cmd+shift+a" = mods cmd|shift + key 'a',
    # but "shift" alone = mods 0 + key 'shift' (so hold_key("shift") works).
    parts = [p.strip().lower() for p in combo.split("+") if p.strip()]
    if not parts:
        raise ValueError("empty combo")
    mod_parts, key_name = parts[:-1], parts[-1]
    mods = 0
    for p in mod_parts:
        if p not in _MODIFIER_FLAGS:
            raise ValueError("expected modifier in {0!r}, got {1!r}".format(combo, p))
        mods |= _MODIFIER_FLAGS[p]
    if key_name in _KEYCODES:
        return mods, _KEYCODES[key_name], None
    if len(key_name) == 1:
        return mods, _KEYCODES.get(key_name, None), key_name
    raise ValueError("unknown key: {0!r}".format(key_name))


def key(combo, repeat=1):
    mods, code, unicode_fallback = _parse_combo(combo)
    if code is None and unicode_fallback:
        for _ in range(max(1, int(repeat))):
            type_text(unicode_fallback)
        return
    for _ in range(max(1, int(repeat))):
        down = CGEventCreateKeyboardEvent(None, code, True)
        up = CGEventCreateKeyboardEvent(None, code, False)
        # Always set flags explicitly (even 0). CGEventCreateKeyboardEvent
        # with NULL source inherits the system's current modifier state, so
        # a previous cmd+X event can leave the Cmd bit "captured" and our
        # next no-modifier event silently gains a Cmd flag.
        CGEventSetFlags(down, mods)
        CGEventSetFlags(up, mods)
        CGEventPost(kCGHIDEventTap, down)
        CGEventPost(kCGHIDEventTap, up)


def hold_key(combo, duration=1.0):
    mods, code, _unicode = _parse_combo(combo)
    if code is None:
        raise ValueError("cannot hold: unsupported key {0!r}".format(combo))
    down = CGEventCreateKeyboardEvent(None, code, True)
    CGEventSetFlags(down, mods)
    CGEventPost(kCGHIDEventTap, down)
    time.sleep(max(0.0, float(duration)))
    up = CGEventCreateKeyboardEvent(None, code, False)
    CGEventSetFlags(up, mods)
    CGEventPost(kCGHIDEventTap, up)


def type_text(text, per_char_delay=0.0):
    # One synthetic event per character (or per surrogate pair). Three
    # Mavericks-specific constraints drive the design:
    #  1. PyObjC 2.3.2 (system) won't depythonify a unicode string into
    #     UniChar* (unsigned short) — pass a tuple of ints instead.
    #  2. The kCGEventUnicodeStringField buffer caps at ~20 UniChars per
    #     event, so we can't pack the whole string into one event.
    #  3. NSOpenPanel sheets on 10.9 reject events whose physical keycode
    #     contradicts the unicode-override character (the panel's path-
    #     completion handler bails and dismisses both sheet AND parent).
    #     Use the matching keycode for ASCII; fall back to keycode 0 for
    #     non-Latin chars where no US-layout keycode applies.
    # WindowServer also drops events posted back-to-back without a yield,
    # so default to a 5ms inter-event sleep when the caller didn't set one.
    if isinstance(text, bytes):
        text = text.decode("utf-8")
    if not text:
        return
    inter_delay = per_char_delay if per_char_delay > 0 else 0.005
    i = 0
    while i < len(text):
        cu = ord(text[i])
        if 0xD800 <= cu <= 0xDBFF and i + 1 < len(text):
            units = (cu, ord(text[i + 1]))
            keycode, mods = 0, 0
            i += 2
        else:
            units = (cu,)
            keycode, mods = _CHAR_TO_KEY.get(text[i], (0, 0))
            i += 1
        ev_d = CGEventCreateKeyboardEvent(None, keycode, True)
        ev_u = CGEventCreateKeyboardEvent(None, keycode, False)
        # Always set flags explicitly (even 0). CGEventCreateKeyboardEvent
        # with NULL source inherits system modifier state, so a previous
        # cmd+X event can leak the Cmd bit into this one.
        CGEventSetFlags(ev_d, mods)
        CGEventSetFlags(ev_u, mods)
        CGEventKeyboardSetUnicodeString(ev_d, len(units), units)
        CGEventKeyboardSetUnicodeString(ev_u, len(units), units)
        CGEventPost(kCGHIDEventTap, ev_d)
        CGEventPost(kCGHIDEventTap, ev_u)
        time.sleep(inter_delay)


# ---------- Apps / clipboard ----------
def open_application(app, wait_seconds=3.0):
    """Launch (or activate, if already running) an app by bundle id or display
    name. Matches the official tool: single `app` arg, smart-detects which.

    After a successful launch, polls until the app is confirmed frontmost (or
    the timeout lapses). Activation is asynchronous; without the wait, a
    type/key issued right after open_application can land in whatever app was
    focused before -- including the controlling terminal."""
    ws = AppKit.NSWorkspace.sharedWorkspace()
    # Reverse-DNS bundle ids contain dots and never spaces; display names
    # ("Slack", "VLC media player") may have spaces and rarely have dots.
    looks_like_bundle = "." in app and " " not in app
    ok = False
    if looks_like_bundle:
        ok, _ident = ws.launchAppWithBundleIdentifier_options_additionalEventParamDescriptor_launchIdentifier_(
            app, AppKit.NSWorkspaceLaunchDefault, None, None,
        )
    if not ok:
        # Also the fallback when a dotted string doesn't resolve as a bundle
        # id (e.g. user typed "com.something" loosely).
        ok = bool(ws.launchApplication_(app))
    result = {"launched": bool(ok), "app": app}
    if not ok:
        return result
    target = _txt(app).lower()
    deadline = time.time() + max(0.0, float(wait_seconds))
    activated = False
    while time.time() < deadline:
        _pump(0.1)
        d = ws.activeApplication() or {}
        bid = _txt(d.get("NSApplicationBundleIdentifier") or u"").lower()
        name = _txt(d.get("NSApplicationName") or u"").lower()
        if target in (bid, name):
            activated = True
            break
    result["activated"] = activated
    if not activated:
        result["note"] = ("launched, but not confirmed frontmost within {0}s; "
                          "verify focus with a screenshot before typing".format(wait_seconds))
    return result


def parse_modifiers(text):
    """Parse a '+'-separated modifier-only combo (e.g. 'shift', 'ctrl+shift')
    and return the CGEventFlags mask. Empty / None -> 0."""
    if not text:
        return 0
    flags = 0
    for p in text.split("+"):
        p = p.strip().lower()
        if not p:
            continue
        if p in _MODIFIER_FLAGS:
            flags |= _MODIFIER_FLAGS[p]
        else:
            raise ValueError("not a modifier key: {0!r}".format(p))
    return flags


# --- Hide/unhide controlling terminal ----------------------------------------
def _running_with_bundle(bundle_id):
    _pump(0.05)  # runningApplications is run-loop-cached; refresh first
    apps = AppKit.NSWorkspace.sharedWorkspace().runningApplications()
    for a in apps:
        if _txt(a.bundleIdentifier() or u"") == bundle_id:
            return a
    return None


def hide_host(bundle_id=None):
    bid = bundle_id or HOST_BUNDLE
    if not bid:
        return {"hidden": False, "reason": "no host bundle detected"}
    a = _running_with_bundle(bid)
    if not a:
        return {"hidden": False, "reason": "{0} not running".format(bid)}
    a.hide()
    return {"hidden": True, "bundleId": bid}


def unhide_host(bundle_id=None):
    bid = bundle_id or HOST_BUNDLE
    if not bid:
        return {"unhidden": False, "reason": "no host bundle detected"}
    a = _running_with_bundle(bid)
    if not a:
        return {"unhidden": False, "reason": "{0} not running".format(bid)}
    a.unhide()
    return {"unhidden": True, "bundleId": bid}


def host_display_name():
    """Localized display name of the host terminal app (e.g. "Terminal"),
    falling back to its bundle id. Used in user-facing guard messages."""
    if not HOST_BUNDLE:
        return u""
    a = _running_with_bundle(HOST_BUNDLE)
    if a is not None:
        return _txt(a.localizedName() or u"") or HOST_BUNDLE
    return HOST_BUNDLE


def frontmost_bundle():
    """Bundle id of the app that currently owns keyboard focus, or u"" if
    none/unknown. Synthetic CGEvents posted to the HID tap are delivered to
    whatever this returns -- never to a specific window -- so input guards
    consult it before acting, notably to avoid typing into the controlling
    terminal (which would inject keystrokes into the Claude session itself).

    Uses the deprecated Carbon-backed activeApplication() because it queries
    LaunchServices fresh on every call; frontmostApplication is run-loop-cached
    (see _pump) and was returning stale values, which silently disabled the
    host-terminal input guard."""
    ws = AppKit.NSWorkspace.sharedWorkspace()
    d = ws.activeApplication()
    if d:
        bid = d.get("NSApplicationBundleIdentifier")
        if bid:
            return _txt(bid)
    _pump(0.05)
    a = ws.frontmostApplication()
    if a is None:
        return u""
    return _txt(a.bundleIdentifier() or u"")


def host_window_at_point(x, y):
    """True when the topmost normal-layer on-screen window containing the
    global screen point (x, y) belongs to the host terminal. Pointer events
    posted to the HID tap hit whatever window is really at that point --
    which, because screenshot() hides the host during capture, may be a host
    window the model cannot see. CGWindowListCopyWindowInfo queries the window
    server directly (front-to-back order, never stale), so this reflects the
    live z-order rather than the screenshot's."""
    if not HOST_BUNDLE:
        return False
    opts = (Quartz.kCGWindowListOptionOnScreenOnly
            | Quartz.kCGWindowListExcludeDesktopElements)
    raw = Quartz.CGWindowListCopyWindowInfo(opts, Quartz.kCGNullWindowID)
    for w in raw or []:
        # Layer 0 is the normal app-window layer; menus, the menu bar, and
        # other overlays live higher and legitimately intercept clicks, so
        # they are not the host terminal's problem to answer for.
        if int(w.get("kCGWindowLayer", 0)) != 0:
            continue
        if float(w.get("kCGWindowAlpha", 1.0)) <= 0.01:
            continue
        b = w.get("kCGWindowBounds") or {}
        bx = float(b.get("X", 0)); by = float(b.get("Y", 0))
        bw = float(b.get("Width", 0)); bh = float(b.get("Height", 0))
        if not (bx <= x < bx + bw and by <= y < by + bh):
            continue
        pid = int(w.get("kCGWindowOwnerPID", 0))
        a = AppKit.NSRunningApplication.runningApplicationWithProcessIdentifier_(pid)
        bid = _txt(a.bundleIdentifier() or u"") if a else u""
        return bid == HOST_BUNDLE
    return False


# --- Window location enumeration ---------------------------------------------
def list_window_locations(bundle_ids=None):
    opts = (
        Quartz.kCGWindowListOptionOnScreenOnly
        | Quartz.kCGWindowListExcludeDesktopElements
    )
    raw = Quartz.CGWindowListCopyWindowInfo(opts, Quartz.kCGNullWindowID)
    if raw is None:
        return []
    displays = list_displays()
    by_bid = set(bundle_ids) if bundle_ids else None
    out = []
    # Resolve pids via NSRunningApplication (fresh per call) rather than the
    # run-loop-cached runningApplications list, which misses apps launched
    # after the last pump.
    pid_to_bundle = {}
    for w in raw:
        pid = int(w.get("kCGWindowOwnerPID", 0))
        if pid not in pid_to_bundle:
            a = AppKit.NSRunningApplication.runningApplicationWithProcessIdentifier_(pid)
            pid_to_bundle[pid] = _txt(a.bundleIdentifier() or u"") if a else None
        bid = pid_to_bundle.get(pid)
        if by_bid is not None and bid not in by_bid:
            continue
        bounds = w.get("kCGWindowBounds") or {}
        bx = int(bounds.get("X", 0)); by = int(bounds.get("Y", 0))
        bw = int(bounds.get("Width", 0)); bh = int(bounds.get("Height", 0))
        cx = bx + bw // 2; cy = by + bh // 2
        owning = None
        for d in displays:
            if d["originX"] <= cx < d["originX"] + d["width"] and d["originY"] <= cy < d["originY"] + d["height"]:
                owning = d["displayId"]; break
        if owning is None and displays:
            owning = displays[0]["displayId"]
        out.append({
            "bundleId":     bid,
            "ownerName":    _txt(w.get("kCGWindowOwnerName", u"")),
            "windowTitle":  _txt(w.get("kCGWindowName", u"") or u""),
            "displayId":    owning,
            "bounds":       {"x": bx, "y": by, "width": bw, "height": bh},
            "windowNumber": int(w.get("kCGWindowNumber", 0)),
            "layer":        int(w.get("kCGWindowLayer", 0)),
        })
    return out


# --- Pixel validation --------------------------------------------------------
def capture_region_jpeg(x, y, w, h, display_id=None, jpeg_quality=0.7):
    did = display_id if display_id is not None else int(Quartz.CGMainDisplayID())
    bounds = Quartz.CGDisplayBounds(did)
    rect = Quartz.CGRectMake(float(x) - bounds.origin.x, float(y) - bounds.origin.y, float(w), float(h))
    img = Quartz.CGDisplayCreateImageForRect(did, rect)
    if img is None:
        raise RuntimeError("CGDisplayCreateImageForRect failed")
    rep = AppKit.NSBitmapImageRep.alloc().initWithCGImage_(img)
    props = {AppKit.NSImageCompressionFactor: float(jpeg_quality)}
    data = rep.representationUsingType_properties_(AppKit.NSJPEGFileType, props)
    return bytes(data)


def jpeg_region_hash(jpeg_bytes):
    return hashlib.sha256(jpeg_bytes).hexdigest()


def list_running_applications():
    _pump(0.05)  # runningApplications is run-loop-cached; refresh first
    apps = AppKit.NSWorkspace.sharedWorkspace().runningApplications()
    out = []
    for a in apps:
        bid = a.bundleIdentifier()
        if bid is None:
            continue
        out.append({
            "bundleId":      _txt(bid),
            "localizedName": _txt(a.localizedName() or u""),
            "pid":           int(a.processIdentifier()),
            "isActive":      bool(a.isActive()),
        })
    return out


def focus_application(bundle_id):
    _pump(0.05)  # runningApplications is run-loop-cached; refresh first
    apps = AppKit.NSWorkspace.sharedWorkspace().runningApplications()
    for a in apps:
        if _txt(a.bundleIdentifier() or u"") == bundle_id:
            ok = bool(a.activateWithOptions_(AppKit.NSApplicationActivateIgnoringOtherApps))
            reason = None if ok else "activateWithOptions returned NO (app may be hidden or still launching)"
            return {"activated": ok, "bundleId": bundle_id, "reason": reason}
    return {"activated": False, "bundleId": bundle_id, "reason": "no running application has that bundle id"}


def read_clipboard():
    pb = AppKit.NSPasteboard.generalPasteboard()
    return _txt(pb.stringForType_(AppKit.NSPasteboardTypeString) or u"")


def write_clipboard(text):
    pb = AppKit.NSPasteboard.generalPasteboard()
    pb.clearContents()
    pb.setString_forType_(text, AppKit.NSPasteboardTypeString)
    return True


def wait(ms):
    time.sleep(max(0, int(ms)) / 1000.0)
