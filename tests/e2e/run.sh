#!/bin/sh
# platform: macOS-only -- drives an installed claude-code on Mac OS X 10.9
#   usage: sh tests/e2e/run.sh   (exit 77 unless 10.9 with the product installed; checks 5-6 also need CC_E2E_REAL_ACCOUNT=1;
#          CC_E2E_CHECKS="1 7" runs only those checks)

MG=/usr/local/mavergreen
CLAUDE="$MG/claude-code/bin/claude"
LIBX="$MG/claude-code/libexec/claude-code"
TTIDLE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/ttidle.py"
FAILS=0
HOMES=""
OLDER="${CC_E2E_OLDER_VERSION:-2.1.285}"

case "$(sw_vers -productVersion 2>/dev/null)" in
  10.9|10.9.*) ;;
  *) echo "SKIP: not Mac OS X 10.9"; exit 77 ;;
esac
[ -f "$MG/claude-code/mavergreen.plist" ] || { echo "SKIP: claude-code is not installed"; exit 77; }

REAL_HOME="$HOME"
[ "${CC_E2E_REAL_ACCOUNT-}" = 1 ] && echo "WARNING: CC_E2E_REAL_ACCOUNT=1 takes over the real account's Claude Code from Mavericks Forever"

cleanup() {
  for _h in $HOMES; do
    case "$_h" in
      */cc-e2e.?*) rm -rf "$_h" ;;
    esac
  done
}
trap cleanup EXIT
trap 'exit 1' INT TERM

new_home() {
  NEWHOME="$(mktemp -d "${TMPDIR:-/tmp}/cc-e2e.XXXXXX")" || return 1
  HOMES="$HOMES $NEWHOME"
}

ccrun() {
  _crh="$1"; _crs="$2"; shift 2
  for _crv in http_proxy https_proxy ALL_PROXY no_proxy SSL_CERT_FILE; do
    eval "_crset=\${$_crv+x}"
    if [ -n "$_crset" ]; then
      eval "_crval=\$$_crv"
      set -- "$_crv=$_crval" "$@"
    fi
  done
  env -i HOME="$_crh" PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR="${TMPDIR:-/tmp}" \
    perl -e 'alarm shift; exec @ARGV' "$_crs" env "$@"
}

to() {
  _secs="$1"; shift
  perl -e 'alarm shift; exec @ARGV' "$_secs" "$@"
}

pass() { echo "PASS $1 $2"; }
fail() { echo "FAIL $1 $2: $3"; FAILS=$((FAILS+1)); }
skip() { echo "SKIP $1 $2: $3"; }

has_version() {
  _hv=" $(printf '%s' "$1" | tr -s '[:space:]' ' ') "
  case "$_hv" in
    *" $2 "*|*" v$2 "*|*"($2 "*|*"($2)"*|*" $2)"*) return 0 ;;
  esac
  return 1
}

cdn_latest() {
  curl -fsSL "https://downloads.claude.ai/claude-code-releases/latest" 2>/dev/null | tr -d '[:space:]'
}

cache_listing() {
  find "$1/Library/Caches/dev.mavergreen.claude-code" -exec stat -f '%N %m' {} + 2>/dev/null
}

check1() {
  _n=1; _name="fresh bootstrap"
  new_home || { fail $_n "$_name" "no throwaway HOME"; return; }
  _h="$NEWHOME"
  _want="$(cdn_latest)"
  [ -n "$_want" ] || { fail $_n "$_name" "could not read the CDN's latest"; return; }
  _out="$(ccrun "$_h" 600 "$CLAUDE" --version 2>&1)"
  has_version "$_out" "$_want" || { fail $_n "$_name" "--version printed '$_out', wanted $_want"; return; }
  _t="$(readlink "$_h/.local/bin/claude" 2>/dev/null)"
  [ "$_t" = "$MG/bin/claude" ] || { fail $_n "$_name" "~/.local/bin/claude -> '$_t', wanted $MG/bin/claude"; return; }
  pass $_n "$_name"
}

check2() {
  _n=2; _name="second run patches nothing new"
  new_home || { fail $_n "$_name" "no throwaway HOME"; return; }
  _h="$NEWHOME"
  ccrun "$_h" 600 "$CLAUDE" --version >/dev/null 2>&1
  _l1="$(cache_listing "$_h")"
  [ -n "$_l1" ] || { fail $_n "$_name" "no cache after the first run"; return; }
  sleep 2
  ccrun "$_h" 600 "$CLAUDE" --version >/dev/null 2>&1
  _l2="$(cache_listing "$_h")"
  [ "$_l1" = "$_l2" ] || { fail $_n "$_name" "the cache changed on the second run"; return; }
  pass $_n "$_name"
}

update_ok() {
  _uo="$(ccrun "$1" 900 env PATH="$2" "$CLAUDE" update 2>&1)"
  _urc=$?
  UPDATE_OUT="$_uo"
  [ "$_urc" -eq 0 ] || { UPDATE_WHY="exit $_urc: $_uo"; return 1; }
  case "$_uo" in
    *"is not in your PATH"*) UPDATE_WHY="warned: $_uo"; return 1 ;;
  esac
  case "$(printf '%s' "$_uo" | tr 'A-Z' 'a-z')" in
    *"up to date"*|*"up-to-date"*|*updated*) return 0 ;;
  esac
  UPDATE_WHY="no up-to-date or updated message: '$_uo'"
  return 1
}

check3() {
  _n=3; _name="update prints no PATH warning"
  new_home || { fail $_n "$_name" "no throwaway HOME"; return; }
  _h="$NEWHOME"
  update_ok "$_h" "/usr/bin:/bin:/usr/sbin:/sbin" || { fail $_n "$_name" "without ~/.local/bin in PATH, $UPDATE_WHY"; return; }
  update_ok "$_h" "$_h/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin" || { fail $_n "$_name" "with ~/.local/bin in PATH, $UPDATE_WHY"; return; }
  pass $_n "$_name"
}

check4() {
  _n=4; _name="DISABLE_AUTOUPDATER runs current"
  new_home || { fail $_n "$_name" "no throwaway HOME"; return; }
  _h="$NEWHOME"
  _latest="$(ccrun "$_h" 600 "$CLAUDE" --version 2>&1)"
  has_version "$_latest" "$OLDER" && { fail $_n "$_name" "latest is $OLDER; set CC_E2E_OLDER_VERSION to an older release"; return; }
  ccrun "$_h" 600 sh -c '. "$1/lib.sh"; . "$1/fetch.sh"; cc_init "$2"; cc_fetch "$3"' \
    sh "$LIBX" "$CLAUDE" "$OLDER" >/dev/null 2>&1
  [ -x "$_h/.local/share/claude/versions/$OLDER" ] || { fail $_n "$_name" "could not install $OLDER into the throwaway HOME"; return; }
  printf '%s\n' "$OLDER" > "$_h/Library/Application Support/dev.mavergreen.claude-code/current"
  _out="$(ccrun "$_h" 600 env DISABLE_AUTOUPDATER=1 "$CLAUDE" --version 2>&1)"
  has_version "$_out" "$OLDER" && pass $_n "$_name" || fail $_n "$_name" "--version printed '$_out', wanted $OLDER (current)"
}

real_account() {
  [ "${CC_E2E_REAL_ACCOUNT-}" = 1 ] || { skip $1 "$2" "set CC_E2E_REAL_ACCOUNT=1 to run against the current user's real account"; return 1; }
  return 0
}

check5() {
  _n=5; _name="claude -p returns OK"
  real_account $_n "$_name" || return
  [ -n "${ANTHROPIC_API_KEY-}" ] || { skip $_n "$_name" "ANTHROPIC_API_KEY is not set"; return; }
  _out="$(to 300 env HOME="$REAL_HOME" "$CLAUDE" -p 'reply with OK' 2>&1)"
  [ "$(printf '%s' "$_out" | tr -d '[:space:]')" = OK ] && pass $_n "$_name" || fail $_n "$_name" "printed '$_out'"
}

check6() {
  _n=6; _name="mcp list shows computer-use-mavericks connected"
  real_account $_n "$_name" || return
  _out="$(to 300 env HOME="$REAL_HOME" "$CLAUDE" mcp list 2>&1)"
  case "$(printf '%s\n' "$_out" | grep 'computer-use-mavericks')" in
    *Connected*) pass $_n "$_name" ;;
    *) fail $_n "$_name" "mcp list printed '$_out'" ;;
  esac
}

check7() {
  _n=7; _name="spin canary: idles with wide characters on screen"
  new_home || { fail $_n "$_name" "no throwaway HOME"; return; }
  _h="$(cd "$NEWHOME" && pwd -P)" || { fail $_n "$_name" "could not resolve the throwaway HOME"; return; }
  _py=/usr/bin/python; [ -x "$_py" ] || _py=python3
  ccrun "$_h" 900 "$CLAUDE" --version >/dev/null 2>&1 || { fail $_n "$_name" "claude --version failed, so there is nothing to watch"; return; }
  _p="$_h/wide project"
  mkdir -p "$_p/.claude/skills/wide" || { fail $_n "$_name" "could not make the project"; return; }
  _wide='Wide characters — em dashes – en dashes … 日本語のテキスト 한국어 中文 🙂🚀 e\xcc\x81 «»'
  printf "# Canary\n\n$_wide\n\n- $_wide\n- $_wide\n" > "$_p/CLAUDE.md"
  printf -- "---\nname: wide\ndescription: $_wide — a skill whose text is wide\n---\n\n$_wide\n" > "$_p/.claude/skills/wide/SKILL.md"
  "$_py" -c '
import json, sys
home, project, key = sys.argv[1], sys.argv[2], sys.argv[3]
c = {"hasCompletedOnboarding": True, "theme": "dark",
     "projects": {project: {"hasTrustDialogAccepted": True, "projectOnboardingSeenCount": 9}}}
if key:
    c["customApiKeyResponses"] = {"approved": [key[-20:]], "rejected": []}
open(home + "/.claude.json", "w").write(json.dumps(c))
' "$_h" "$_p" "${ANTHROPIC_API_KEY-}" || { fail $_n "$_name" "could not seed .claude.json"; return; }
  set --
  [ -z "${ANTHROPIC_API_KEY-}" ] || set -- "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY"
  _r="$(cd "$_p" && ccrun "$_h" 300 "$@" DISABLE_AUTOUPDATER=1 TTIDLE_LOG="$_h/screen.log" "$_py" "$TTIDLE" 180 "$CLAUDE" 2>&1 | tail -n 1)"
  case "$_r" in
    TTIDLE=none*) fail $_n "$_name" "it never went idle -- the spin is back? ($_r)"; return ;;
    TTIDLE=[0-9]*) ;;
    *) fail $_n "$_name" "inconclusive: $_r"; return ;;
  esac
  LC_ALL=C perl -0ne 'exit(m{~/wide(?:\e\[\d*[CG]| )+project} ? 0 : 1)' "$_h/screen.log" 2>/dev/null \
    || { fail $_n "$_name" "it idled, but its screen never showed the REPL's header, ~/wide project, so it may have idled at a dialog before reading the wide text ($_r)"; return; }
  pass $_n "$_name ($_r)"
}

for _c in ${CC_E2E_CHECKS:-1 2 3 4 5 6 7}; do
  case "$_c" in
    [1-7]) "check$_c" ;;
    *) fail 0 "CC_E2E_CHECKS" "no check $_c" ;;
  esac
  [ "$HOME" = "$REAL_HOME" ] || { fail 0 environment "HOME leaked: $HOME"; HOME="$REAL_HOME"; }
done

[ "$FAILS" -eq 0 ] || exit 1
exit 0
