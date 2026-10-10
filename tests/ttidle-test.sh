#!/bin/sh
# platform: macOS-only -- the spin canary's harness runs under Mac OS X 10.9's Python 2.7, and CI's macOS Python 3
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
T="$H_REPO/tests/e2e/ttidle.py"
h_assert_eq "# platform: macOS-only -- times Claude Code going idle in a pseudo-terminal, with no pyte, under Mac OS X 10.9's Python 2.7 or a modern Python 3" "$(sed -n 2p "$T")" "ttidle.py declares its platform"

pythons=""
for p in /usr/bin/python2.7 /usr/bin/python3 /opt/pkg/bin/python3; do [ ! -x "$p" ] || pythons="$pythons $p"; done
[ -n "$pythons" ] || { echo "ttidle-test: no python to run the harness with" >&2; exit 77; }

for py in $pythons; do
  rm -f "$H/answer" "$H/bg.pid"
  out="$("$py" "$T" 30 sh -c 'stty raw -echo; printf "\033[6n"; dd bs=1 count=6 2>/dev/null | od -An -c | tr -d " \n" > "$1"; exec sleep 60' sh "$H/answer" 2>&1)"
  case "$out" in TTIDLE=[0-9]*) idle=yes ;; *) idle=no ;; esac
  h_assert_eq "yes" "$idle" "[$py] a command that sits idle reports TTIDLE=<seconds>: $out"
  h_assert_eq '033[1;1R' "$(cat "$H/answer" 2>/dev/null)" "[$py] a cursor-position query gets an answer, as a terminal would give"
  rm -f "$H/screen.log"
  TTIDLE_LOG="$H/screen.log" "$py" "$T" 12 sh -c 'printf "hello screen"; exec sleep 60' >/dev/null 2>&1
  h_assert_contains "$(cat "$H/screen.log" 2>/dev/null)" "hello screen" "[$py] TTIDLE_LOG keeps what the command wrote to its terminal"

  out="$("$py" "$T" 9 sh -c 'while :; do :; done' 2>&1)"
  case "$out" in TTIDLE=none*) spin=yes ;; *) spin=no ;; esac
  h_assert_eq "yes" "$spin" "[$py] a command that spins reports TTIDLE=none: $out"

  "$py" "$T" 12 sh -c 'trap "" HUP; sleep 60 & echo $! > "$1"; exec sleep 60' sh "$H/bg.pid" >/dev/null 2>&1
  bg="$(cat "$H/bg.pid" 2>/dev/null || :)"
  h_assert_ok test -n "$bg"
  alive=no
  if [ -n "$bg" ] && kill -0 "$bg" 2>/dev/null; then alive=yes; kill "$bg" 2>/dev/null || :; fi
  h_assert_eq "no" "$alive" "[$py] the harness kills the command's whole session, not just the command"
done
