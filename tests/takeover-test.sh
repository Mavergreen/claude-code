#!/bin/sh
# platform: macOS-only -- the launcher targets Mac OS X 10.9's sh and tools
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
CC_LIBEXEC="$H/root/usr/local/mavergreen/claude-code/libexec/claude-code"
. "$CC_LIBEXEC/lib.sh"
. "$CC_LIBEXEC/takeover.sh"
mkdir -p "$H/root/usr/local/mavergreen/claude-code/bin" "$H/root/usr/local/mavergreen/bin"
printf '#!/bin/sh\n' > "$H/root/usr/local/mavergreen/claude-code/bin/claude"
chmod +x "$H/root/usr/local/mavergreen/claude-code/bin/claude"
ln -s "$H/root/usr/local/mavergreen/claude-code/bin/claude" "$H/root/usr/local/mavergreen/bin/claude"
cc_init "$H/root/usr/local/mavergreen/claude-code/bin/claude"

D="$HOME/.local/share/claude"
mkdir -p "$HOME/.local/share/claude-mavericks/lib" "$HOME/.cache/claude-mavericks" "$D/versions" "$HOME/.local/share/claude-mavericks-local"
ln -s /nowhere/S.dylib "$D/S.dylib"
ln -s /nowhere/I.dylib "$D/versions/I.dylib"
ln -s /nowhere/c++.1.dylib "$D/versions/c++.1.dylib"
: > "$D/versions/2.1.289.mf-tmp.42"
: > "$D/versions/2.1.289"
mkdir -p "$CC_MG/var/claude-code"
printf 'Removed /usr/local/lib/mf-shim.dylib\n' > "$CC_MG/var/claude-code/removed-mavericks-forever"

out="$(cc_takeover 2>&1)"
h_assert_contains "$out" "~/.local/share/claude-mavericks" "names the data dir"
h_assert_contains "$out" "~/.cache/claude-mavericks" "names the cache dir"
h_assert_contains "$out" "~/.local/share/claude/S.dylib" "names the S alias"
h_assert_contains "$out" "~/.local/share/claude/versions/I.dylib" "names the I alias"
h_assert_contains "$out" "~/.local/share/claude/versions/c++.1.dylib" "names the c++ alias"
h_assert_contains "$out" "~/.local/share/claude/versions/2.1.289.mf-tmp.42" "names the temp file"
h_assert_contains "$out" "Removed /usr/local/lib/mf-shim.dylib" "includes the system list"
GOBACK="To go back to Mavericks Forever, uninstall Claude Code for Mavericks first (sudo mavergreen uninstall claude-code), then rerun https://mavericksforever.com/claude/install.sh"
case "$out" in *"$GOBACK") ;; *) h_assert_eq "ends with: $GOBACK" "$out" "notice ending" ;; esac
h_assert_fails test -e "$HOME/.local/share/claude-mavericks"
h_assert_fails test -e "$HOME/.cache/claude-mavericks"
h_assert_fails test -L "$D/S.dylib"
h_assert_fails test -L "$D/versions/I.dylib"
h_assert_fails test -L "$D/versions/c++.1.dylib"
h_assert_fails test -e "$D/versions/2.1.289.mf-tmp.42"
h_assert_ok test -f "$D/versions/2.1.289"
h_assert_ok test -d "$HOME/.local/share/claude-mavericks-local"
h_assert_ok test -f "$CC_STATE/took-over"

h_assert_eq "$(cc_sha256 "$CC_MG/var/claude-code/removed-mavericks-forever")" "$(cat "$CC_STATE/took-over")" "the marker records the system list's digest"

h_assert_eq "" "$(cc_takeover 2>&1)" "second run prints nothing"
mkdir -p "$HOME/.local/share/claude-mavericks"
h_assert_eq "" "$(cc_takeover 2>&1)" "an unchanged system list does not run again"
h_assert_ok test -d "$HOME/.local/share/claude-mavericks"
printf '# 2026-10-06T00:00:00Z 4242\n/usr/local/bin/claude\n' > "$CC_MG/var/claude-code/removed-mavericks-forever"
out="$(cc_takeover 2>&1)"
h_assert_contains "$out" "~/.local/share/claude-mavericks" "a changed system list runs the takeover again"
h_assert_contains "$out" "  /usr/local/bin/claude" "and prints the new list"
h_assert_contains "$out" "$GOBACK" "with the go-back line"
case "$out" in *"4242"*) h_assert_eq "no stamp" "$out" "the list's stamp line is not printed" ;; esac
h_assert_fails test -e "$HOME/.local/share/claude-mavericks"
h_assert_eq "$(cc_sha256 "$CC_MG/var/claude-code/removed-mavericks-forever")" "$(cat "$CC_STATE/took-over")" "the marker follows the new digest"
h_assert_eq "" "$(cc_takeover 2>&1)" "and then it is silent again"
printf 'Removed /usr/local/lib/mf-shim.dylib\n' > "$CC_MG/var/claude-code/removed-mavericks-forever"
cc_takeover >/dev/null 2>&1

rm -rf "$CC_STATE"
: > "$D/S.dylib"
: > "$D/versions/I.dylib"
: > "$CC_MG/var/claude-code/removed-mavericks-forever"
h_assert_eq "" "$(cc_takeover 2>&1)" "nothing removed and empty system list prints nothing"
h_assert_ok test -f "$D/S.dylib"
h_assert_ok test -f "$D/versions/I.dylib"
h_assert_ok test -f "$CC_STATE/took-over"

rm -rf "$CC_STATE"
rm -f "$CC_MG/var/claude-code/removed-mavericks-forever"
h_assert_eq "" "$(cc_takeover 2>&1)" "absent system list prints nothing"

rm -rf "$CC_STATE"
printf 'only system\n' > "$CC_MG/var/claude-code/removed-mavericks-forever"
out="$(cc_takeover 2>&1)"
h_assert_contains "$out" "only system" "system list alone prints a notice"

OURS="$CC_MG/bin/claude"
h_assert_fails test -e "$CC_LINK"
cc_claim_link
h_assert_eq "$OURS" "$(readlink "$CC_LINK")" "missing link is created"

before="$(ls -il "$CC_LINK")"
h_assert_eq "" "$(cc_claim_link 2>&1)" "ours prints nothing"
h_assert_eq "$before" "$(ls -il "$CC_LINK")" "ours untouched (same inode)"

mkdir -p "$D/versions" "$H/alt"
ln -s "$H/alt" "$H/altlink"
ln -s "$CC_TREE/bin/claude" "$H/alt/hop"
rm -f "$CC_LINK"
ln -s "$H/altlink/hop" "$CC_LINK"
h_assert_eq "" "$(cc_claim_link 2>&1)" "indirect link to ours prints nothing"
h_assert_eq "$H/altlink/hop" "$(readlink "$CC_LINK")" "indirect link to ours untouched"

rm -f "$CC_LINK"
ln -s "$D/versions/2.1.289" "$CC_LINK"
h_assert_eq "" "$(cc_claim_link 2>&1)" "replacing Anthropic's link prints nothing"
h_assert_eq "$OURS" "$(readlink "$CC_LINK")" "Anthropic link replaced"
h_assert_eq "" "$(ls -A "$HOME/.local/bin" | grep '^\.claude-link\.' || true)" "no temp links left"

rm -f "$CC_LINK"
printf '#!/bin/sh\necho mine\n' > "$CC_LINK"
out="$(cc_claim_link 2>&1)"
h_assert_contains "$out" "$CC_LINK" "foreign link note names the path"
h_assert_eq "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "one note line"
h_assert_eq "" "$(cc_claim_link 2>&1)" "no second note"
h_assert_contains "$(cat "$CC_LINK")" "echo mine" "user's script kept"
h_assert_ok test -f "$CC_STATE/foreign-link"

rm -rf "$HOME/.local/bin"
cc_claim_link
h_assert_eq "$OURS" "$(readlink "$CC_LINK")" "bin dir created"

rm -f "$CC_LINK"
mkdir -p "$D/versions/2.1.289.d"
ln -s "$D/versions/2.1.289.d/" "$CC_LINK"
cc_claim_link
h_assert_eq "$OURS" "$(readlink "$CC_LINK")" "link to a versions directory replaced"
h_assert_eq "0" "$(ls -A "$D/versions/2.1.289.d" | wc -l | tr -d ' ')" "nothing created inside that directory"

rm -rf "$CC_STATE" "$HOME/.cache/claude-mavericks" "$HOME/.local/share/claude-mavericks"
: > "$CC_MG/var/claude-code/removed-mavericks-forever"
mkdir -p "$HOME/.cache/claude-mavericks/locked"
: > "$HOME/.cache/claude-mavericks/locked/f"
chmod 555 "$HOME/.cache/claude-mavericks/locked"
rc=0
out="$(cc_takeover 2>&1)" || rc=$?
h_assert_eq "0" "$rc" "a failed removal does not fail the launch"
h_assert_fails test -f "$CC_STATE/took-over"
case "$out" in *"~/.cache/claude-mavericks"*) h_assert_eq "not listed" "listed" "failed path is not listed" ;; esac
chmod 755 "$HOME/.cache/claude-mavericks/locked"
out="$(cc_takeover 2>&1)"
h_assert_contains "$out" "~/.cache/claude-mavericks" "retry removes and lists it"
h_assert_ok test -f "$CC_STATE/took-over"

rm -rf "$CC_STATE"
printf 'no newline' > "$CC_MG/var/claude-code/removed-mavericks-forever"
out="$(cc_takeover 2>&1)"
h_assert_contains "$out" "no newline" "last system line without trailing newline kept"

rm -rf "$CC_STATE" "$H/target"
mkdir -p "$H/target"
: > "$H/target/keep"
ln -s "$H/target" "$HOME/.local/share/claude-mavericks"
: > "$D/c++.1.dylib"
: > "$CC_MG/var/claude-code/removed-mavericks-forever"
cc_takeover 2>/dev/null
h_assert_fails test -L "$HOME/.local/share/claude-mavericks"
h_assert_ok test -f "$H/target/keep"
h_assert_ok test -f "$D/c++.1.dylib"

rm -rf "$CC_STATE"
X="$H/xdg"
mkdir -p "$X/claude/versions" "$HOME/.local/share/claude-mavericks"
ln -s /nowhere "$X/claude/S.dylib"
ln -s /nowhere "$X/claude/versions/I.dylib"
out="$(XDG_DATA_HOME="$X" cc_takeover 2>&1)"
h_assert_contains "$out" "$X/claude/S.dylib" "alias under XDG_DATA_HOME removed"
h_assert_fails test -L "$X/claude/versions/I.dylib"
h_assert_fails test -e "$HOME/.local/share/claude-mavericks"

rm -rf "$CC_STATE"
ln -s /nowhere "$D/S.dylib" 2>/dev/null || { rm -f "$D/S.dylib"; ln -s /nowhere "$D/S.dylib"; }
out="$(XDG_DATA_HOME="relative/xdg" cc_takeover 2>&1)"
h_assert_contains "$out" "~/.local/share/claude/S.dylib" "relative XDG_DATA_HOME ignored"
h_assert_eq "$HOME/.local/share/claude/versions" "$(XDG_DATA_HOME=rel; cc_init "$CC_TREE/bin/claude"; echo "$CC_VERSIONS")" "cc_init ignores relative XDG_DATA_HOME"

out="$(HOME="" cc_init "$CC_TREE/bin/claude" 2>&1)" && h_assert_eq "failure" "success" "empty HOME refused"
h_assert_contains "$out" "HOME must be an absolute path other than /" "empty HOME message"
out="$(HOME="rel/home" cc_init "$CC_TREE/bin/claude" 2>&1)" && h_assert_eq "failure" "success" "relative HOME refused"
h_assert_contains "$out" "HOME must be an absolute path other than / (it is 'rel/home')" "relative HOME message"
out="$(HOME="/" cc_init "$CC_TREE/bin/claude" 2>&1)" && h_assert_eq "failure" "success" "root HOME refused"
for h in // /. /./ /.. /../. ///; do
  rc=0; out="$(HOME="$h" cc_init "$CC_TREE/bin/claude" 2>&1)" || rc=$?
  h_assert_eq "1" "$rc" "HOME=$h, which is / spelled another way, is refused"
  h_assert_contains "$out" "HOME must be an absolute path other than / (it is '$h')" "and the refusal names it"
done
for h in /.h /a. /x/..y; do
  h_assert_eq "$h/.local/bin/claude" "$(HOME="$h" cc_init "$CC_TREE/bin/claude"; printf %s "$CC_LINK")" "HOME=$h, below / though it has dots, is accepted"
done

rm -rf "$CC_STATE" "$HOME/.local/share/claude-mavericks" "$HOME/.cache/claude-mavericks"
: > "$CC_MG/var/claude-code/removed-mavericks-forever"
rm -f "$D/S.dylib" "$D/versions/I.dylib"
ln -s /nowhere "$D/S.dylib"
: > "$D/versions/2.1.300.mf-tmp.7"
mkdir -p "$HOME/.local/share/claude-mavericks/lib"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$H/rm.log"\nexec /bin/rm "$@"\n' > "$H/bin/rm"; chmod +x "$H/bin/rm"; hash -r
cc_takeover 2>/dev/null
rm -f "$H/bin/rm"; hash -r
h_assert_eq "-f $D/S.dylib" "$(grep -F "$D/S.dylib" "$H/rm.log")" "a symlink is removed with rm -f, never a recursive rm"
h_assert_eq "-f $D/versions/2.1.300.mf-tmp.7" "$(grep -F "$D/versions/2.1.300.mf-tmp.7" "$H/rm.log")" "a file is removed with rm -f"
h_assert_eq "-rf $HOME/.local/share/claude-mavericks" "$(grep -F "$HOME/.local/share/claude-mavericks" "$H/rm.log")" "only a directory is removed recursively"
h_assert_absent "$D/S.dylib" "the symlink is gone"
h_assert_absent "$HOME/.local/share/claude-mavericks" "the directory is gone"

rm -rf "$CC_STATE"
rm -f "$CC_LINK"
mkdir -p "$HOME/.local/bin"
ln -s loop "$CC_LINK"
ln -s claude "$HOME/.local/bin/loop"
out="$(cc_claim_link 2>&1)"
h_assert_eq "claude: $CC_LINK is not this launcher's and is left alone" "$out" "a symlink loop at the link is foreign, said once, with no resolver error"
h_assert_eq "" "$(cc_claim_link 2>&1)" "and nothing is said about it at the next launch"
h_assert_eq "loop" "$(readlink "$CC_LINK")" "the looping link is left alone"

rm -rf "$CC_STATE" "$HOME/.local/share/claude-mavericks" "$HOME/.cache/claude-mavericks"
printf 'Removed /usr/local/bin/rg\n' > "$CC_MG/var/claude-code/removed-mavericks-forever"
mkdir -p "$HOME/.cache/claude-mavericks/locked"
: > "$HOME/.cache/claude-mavericks/locked/f"
chmod 555 "$HOME/.cache/claude-mavericks/locked"
out="$(cc_takeover 2>&1)"
h_assert_contains "$out" "Removed /usr/local/bin/rg" "a takeover stuck on a path it cannot remove still prints its notice"
h_assert_eq "" "$(cc_takeover 2>&1)" "but not again at every launch while it stays stuck the same way"
mkdir -p "$HOME/.local/share/claude-mavericks"
out="$(cc_takeover 2>&1)"
h_assert_contains "$out" "~/.local/share/claude-mavericks" "a stuck takeover that removes something new says so"
h_assert_eq "" "$(cc_takeover 2>&1)" "once"
printf 'Removed /usr/local/bin/claude\n' > "$CC_MG/var/claude-code/removed-mavericks-forever"
out="$(cc_takeover 2>&1)"
h_assert_contains "$out" "Removed /usr/local/bin/claude" "a changed system list is a new state, printed while still stuck"
chmod 755 "$HOME/.cache/claude-mavericks/locked"
out="$(cc_takeover 2>&1)"
h_assert_contains "$out" "~/.cache/claude-mavericks" "once unstuck, the takeover removes and lists the path"
h_assert_ok test -f "$CC_STATE/took-over"
h_assert_eq "" "$(cc_takeover 2>&1)" "and is silent after"
h_teardown
