#!/bin/sh
# platform: macOS-only -- the launcher targets Mac OS X 10.9's sh and tools
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
TREE="$H/root/usr/local/mavergreen/claude-code"
P="$TREE/libexec/claude-code/prepare"
CC_LIBEXEC="$TREE/libexec/claude-code"
. "$CC_LIBEXEC/lib.sh"
. "$CC_LIBEXEC/fetch.sh"
. "$CC_LIBEXEC/select.sh"
. "$CC_LIBEXEC/patch.sh"
cc_init "$TREE/bin/claude"
h_fake_drydock
: > "$H/drydock.log"
PERL=/usr/bin/perl
now() { "$PERL" -MTime::HiRes=time -e 'printf "%.2f\n", time'; }

count() { wc -l < "$H/drydock.log" | tr -d ' '; }
built() { if [ -f "$(cc_entry "$1")" ]; then echo yes; else echo no; fi; }

h_assert_ok test -x "$P"
h_assert_eq "# platform: macOS-only -- patches Claude Code for Mac OS X 10.9 after its updater downloads a new version, so the next launch need not" "$(sed -n 2p "$P")" "prepare declares its platform"

rc=0; out="$("$P" --now 2>&1)" || rc=$?
h_assert_eq "0" "$rc" "prepare with no versions installed succeeds"
h_assert_eq "" "$out" "prepare with no versions installed says nothing"
h_assert_eq "0" "$(count)" "prepare with no versions installed patches nothing"

h_cdn_publish 2.1.289
h_cdn_publish 2.1.290
cc_fetch 2.1.289 2>/dev/null
cc_fetch 2.1.290 2>/dev/null

rc=0; DISABLE_AUTOUPDATER=1 "$P" --now || rc=$?
h_assert_eq "0" "$rc" "prepare while updates are held succeeds"
h_assert_eq "0" "$(count)" "prepare while updates are held patches nothing"

rc=0; "$P" --now || rc=$?
h_assert_eq "0" "$rc" "prepare succeeds"
h_assert_eq "yes" "$(built 2.1.290)" "prepare patches the newest installed version"
h_assert_eq "no" "$(built 2.1.289)" "prepare patches only the version the next launch would pick"
h_assert_eq "1" "$(count)" "drydock ran once"
"$P" --now
h_assert_eq "1" "$(count)" "prepare does not patch a version again"
h_assert_fails test -e "$CC_STATE/current"

CFG="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
printf '{"autoUpdatesChannel": "stable"}' > "$CFG"
touch -t 202601010000 "$CC_VERSIONS/2.1.290"
touch -t 202602010000 "$CC_VERSIONS/2.1.289"
"$P" --now
h_assert_eq "yes" "$(built 2.1.289)" "on the stable channel prepare patches the last version downloaded"
rm -f "$CFG"

printf '2.1.290\n' > "$H/drydock-refuses"
rm -rf "$CC_CACHE"
rc=0; "$P" --now 2>/dev/null || rc=$?
h_assert_eq "3" "$rc" "prepare fails when drydock refuses"
h_assert_contains "$(cat "$CC_STATE/last-patch-error")" "fake drydock: detail on stderr" "prepare leaves drydock's complaint where the launcher does"
rm -f "$H/drydock-refuses"

rm -rf "$CC_CACHE"
: > "$H/drydock.log"
printf '3\n' > "$H/drydock-slow"
t0=$(now)
out="$("$P"; echo "rc=$?")"
t1=$(now)
h_assert_eq "rc=0" "$out" "prepare returns 0 and prints nothing when it detaches"
h_assert_eq "0" "$("$PERL" -e "print(($t1 - $t0) > 2 ? 1 : 0)")" "prepare returns before the patch finishes, holding none of its caller's output open"
h_assert_eq "no" "$(built 2.1.290)" "the patch is still running"
i=0
while [ "$(built 2.1.290)" = no ] && [ "$i" -lt 15 ]; do /bin/sleep 1; i=$((i+1)); done
h_assert_eq "yes" "$(built 2.1.290)" "the detached prepare finishes the patch"
rm -f "$H/drydock-slow"

rm -rf "$CC_CACHE"
printf '3\n' > "$H/drydock-slow"
rm -f "$H/hook.pgid"
"$PERL" -e 'setpgrp(0, 0); exec @ARGV' sh -c 'echo $$ > "$1"; "$2"; exec sleep 30' sh "$H/hook.pgid" "$P" &
i=0
while [ ! -s "$H/hook.pgid" ] && [ "$i" -lt 10 ]; do /bin/sleep 1; i=$((i+1)); done
/bin/sleep 1
kill -TERM -- "-$(cat "$H/hook.pgid")" 2>/dev/null || :
wait 2>/dev/null || :
i=0
while [ "$(built 2.1.290)" = no ] && [ "$i" -lt 15 ]; do /bin/sleep 1; i=$((i+1)); done
h_assert_eq "yes" "$(built 2.1.290)" "the detached prepare outlives a kill of the hook's whole process group"
rm -f "$H/drydock-slow"

S="$TREE/share/claude-code/settings.json"
PY=""
for p in /usr/bin/python2.7 /usr/bin/python python3; do
  if command -v "$p" >/dev/null 2>&1; then PY="$p"; break; fi
done
if [ -n "$PY" ]; then
  hooks="$("$PY" -c 'import json,sys
d=json.load(open(sys.argv[1]))
for g in d["hooks"]["SessionEnd"]:
    for h in g["hooks"]:
        print("%s %s" % (h["type"], h["command"]))
print(d["permissions"]["allow"][0])' "$S")"
  h_assert_eq "command /usr/local/mavergreen/claude-code/libexec/claude-code/prepare
mcp__computer-use-mavericks" "$hooks" "settings.json runs prepare, by its installed path, when a session ends, and still allows computer use"
fi
