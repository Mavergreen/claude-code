#!/bin/sh
# platform: macOS-only -- the harness targets Mac OS X 10.9's sh and tools
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
R="$H_REPO/README.md"

line_of() { grep -n -F -- "$1" "$R" | head -n 1 | cut -d: -f1; }
before() {
  _a="$(line_of "$1")"; _b="$(line_of "$2")"
  [ -n "$_a" ] && [ -n "$_b" ] && [ "$_a" -lt "$_b" ]
}
section() { sed -n "/^## $1\$/,/^## /p" "$R"; }

if grep -n -i -E 'installs[^.]*(AVX2 emulator|avxemu)' "$R"; then
  echo "FAIL: README says this package installs the AVX2 emulator" >&2; H_FAILS=$((H_FAILS+1))
fi
h_assert_contains "$(cat "$R")" "separate" "the required products are separate packages"

INS="$(section Installing)"
h_assert_contains "$INS" "avxemu" "Installing names avxemu"
h_assert_contains "$INS" "recaulk" "Installing names recaulk"
h_assert_contains "$INS" "libcxx22" "Installing names libcxx22"
h_assert_contains "$INS" "icu" "Installing names icu"
h_assert_contains "$INS" "new Terminal window" "Installing says to open a new Terminal window"
h_assert_contains "$INS" "/usr/local/mavergreen/bin/claude" "Installing names the command's new path"
h_assert_contains "$INS" "/usr/local/bin/claude" "in place of the old one"
h_assert_ok before "## Installing" "## Pinning a version"
CURL='curl -fsSL https://github.com/Mavergreen/claude-code/releases/latest/download/install.sh | sh'
h_assert_contains "$INS" "$CURL" "Installing gives the one-command install"
_iq="$(printf '%s\n' "$INS" | grep -n -F -- "$CURL" | head -n 1 | cut -d: -f1)"
_i1="$(printf '%s\n' "$INS" | grep -n '^1\. ' | head -n 1 | cut -d: -f1)"
h_assert_ok test "${_iq:-99}" -lt "${_i1:-0}"
MAN="$(printf '%s\n' "$INS" | sed -n '/^1\. /,$p')"
_ia="$(printf '%s\n' "$MAN" | grep -n -i 'avxemu' | head -n 1 | cut -d: -f1)"
_ir="$(printf '%s\n' "$MAN" | grep -n -i 'recaulk' | head -n 1 | cut -d: -f1)"
_il="$(printf '%s\n' "$MAN" | grep -n -i 'libcxx22' | head -n 1 | cut -d: -f1)"
_ii="$(printf '%s\n' "$MAN" | grep -n -i 'icu' | head -n 1 | cut -d: -f1)"
_ic="$(printf '%s\n' "$MAN" | grep -n 'Claude Code for Mavericks' | head -n 1 | cut -d: -f1)"
h_assert_ok test "${_ia:-99}" -lt "${_ir:-0}"
h_assert_ok test "${_ir:-99}" -lt "${_il:-0}"
h_assert_ok test "${_il:-99}" -lt "${_ii:-0}"
h_assert_ok test "${_ii:-99}" -lt "${_ic:-0}"

PIN="$(section "Pinning a version")"
h_assert_contains "$PIN" "DISABLE_AUTOUPDATER=1" "Pinning names the variable"
h_assert_contains "$PIN" "~/.claude/settings.json" "Pinning names the settings file"
h_assert_contains "$PIN" '"env"' "under env"
h_assert_contains "$PIN" "claude install" "Pinning names claude install"
h_assert_contains "$PIN" "next launch" "which applies at the next launch"

BACK="$(section "Going back to Mavericks Forever")"
h_assert_contains "$BACK" "sudo mavergreen uninstall claude-code" "Going back says to uninstall"
h_assert_contains "$BACK" "https://mavericksforever.com/claude/install.sh" "Going back names the installer"
case "$BACK" in
  *"sudo mavergreen uninstall claude-code"*"https://mavericksforever.com/claude/install.sh"*) ;;
  *) h_assert_eq "uninstall, then rerun the installer" "$BACK" "Going back: uninstall first, then rerun" ;;
esac
h_assert_contains "$BACK" '[ "$(readlink ~/.local/bin/claude)" = /usr/local/mavergreen/bin/claude ] && rm -f ~/.local/bin/claude' "Going back removes the link only when it is the launcher's"
