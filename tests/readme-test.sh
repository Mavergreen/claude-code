#!/bin/sh
# platform: macOS-only -- the harness targets Mac OS X 10.9's sh and tools
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
R="$H_REPO/README.md"

section() { sed -n "/^## $1\$/,/^## /p" "$R"; }
first_line() { printf '%s\n' "$1" | grep -n -F -- "$2" | head -n 1 | cut -d: -f1; }
in_order() {
  _txt="$1"; shift
  _prev=0
  for _w in "$@"; do
    _n="$(first_line "$_txt" "$_w")"
    [ -n "$_n" ] && [ "$_n" -gt "$_prev" ] || return 1
    _prev="$_n"
  done
}

ALL="$(cat "$R")"
h_assert_contains "$ALL" "Wowfunhappy" "README credits Wowfunhappy"

USE="$(section "How to use")"
CURL='curl -fsSL https://github.com/Mavergreen/claude-code/releases/latest/download/install.sh | sh'
h_assert_contains "$USE" "$CURL" "How to use gives the one-command install"
h_assert_contains "$USE" "AVX" "How to use names the CPU requirement"

BACK="$(section "Go back to Mavericks Forever")"
h_assert_ok in_order "$BACK" "sudo mavergreen uninstall claude-code" "mavericksforever.com/claude/install.sh"
h_assert_contains "$BACK" '[ "$(readlink ~/.local/bin/claude)" = /usr/local/mavergreen/bin/claude ] && rm -f ~/.local/bin/claude' "Going back removes the link only when it is the launcher's"
