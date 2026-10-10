#!/bin/sh
# platform: macOS-only -- the launcher targets Mac OS X 10.9's sh and tools
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
CC_LIBEXEC="$H/root/usr/local/mavergreen/claude-code/libexec/claude-code"
. "$CC_LIBEXEC/lib.sh"
. "$CC_LIBEXEC/fetch.sh"
. "$CC_LIBEXEC/select.sh"
. "$CC_LIBEXEC/patch.sh"
mkdir -p "$H/root/usr/local/mavergreen/claude-code/bin"
cc_init "$H/root/usr/local/mavergreen/claude-code/bin/claude"
h_fake_drydock
: > "$H/drydock.log"

count() { wc -l < "$H/drydock.log" | tr -d ' '; }
leftovers() { find "$CC_CACHE" -type f ! -name claude | wc -l | tr -d ' '; }

h_cdn_publish 2.1.289
h_cdn_publish 2.1.290
cc_fetch 2.1.289
cc_fetch 2.1.290

ID="$(cut -c1-16 "$CC_TREE/share/claude-code/recipe-id")"
E289="$CC_CACHE/2.1.289-$ID/claude"
h_assert_eq "$E289" "$(cc_entry 2.1.289)" "entry path uses the first 16 hex of the recipe id"
h_assert_eq "2.1.289" "$(cc_entry_version "$E289")" "an entry path names its version"

h_assert_eq "$E289" "$(cc_runnable 2.1.289)" "runnable prints the entry"
h_assert_ok test -x "$E289"
h_assert_contains "$(cat "$E289")" "# patched-by-fake" "entry is the patched copy"
h_assert_eq "0" "$(leftovers)" "no temp files remain"
h_assert_eq "1" "$(count)" "drydock ran once"
h_assert_eq "$E289" "$(cc_runnable 2.1.289)" "second call prints the same entry"
h_assert_eq "1" "$(count)" "second call does not invoke drydock"
h_assert_eq "1" "$(find "$CC_CACHE" -name claude | wc -l | tr -d ' ')" "one entry"

OLDID="$ID"
printf '%s\n' "$(printf 'another recipe' | shasum -a 256 | cut -d' ' -f1)" > "$CC_TREE/share/claude-code/recipe-id"
printf 'another recipe\n' > "$CC_TREE/share/claude-code/recipe"
ID2="$(cut -c1-16 "$CC_TREE/share/claude-code/recipe-id")"
h_assert_eq "$CC_CACHE/2.1.289-$ID2/claude" "$(cc_runnable 2.1.289)" "different recipe id, different entry"
h_assert_eq "2" "$(count)" "different recipe id patches again"
h_assert_ok test -f "$E289"
h_assert_eq "different" "$([ "$OLDID" = "$ID2" ] && echo same || echo different)" "the alternate recipe id differs"

rm -rf "$CC_CACHE"
: > "$H/drydock.log"
printf '#!/bin/sh\necho tampered\n' > "$CC_VERSIONS/2.1.289"
h_assert_eq "$(cc_entry 2.1.289)" "$(cc_runnable 2.1.289)" "tampered version is replaced"
h_assert_eq "$(cc_sha256 "$H/cdn/2.1.289/darwin-x64/claude")" "$(cc_sha256 "$CC_VERSIONS/2.1.289")" "tampered version was refetched"
h_assert_eq "0" "$(grep -c tampered "$(cc_entry 2.1.289)" || true)" "entry holds the genuine bytes"

printf '2.1.290\n' > "$H/drydock-refuses"
ERR="$(cc_runnable 2.1.290 2>&1 >/dev/null)"
h_assert_contains "$ERR" "could not patch Claude Code 2.1.290" "refusal note names the version"
h_assert_contains "$ERR" "running 2.1.289" "refusal note names the fallback"
h_assert_eq "$(cc_entry 2.1.289)" "$(cc_runnable 2.1.290 2>/dev/null)" "refusal falls back to the cached version"
h_assert_contains "$(cat "$CC_STATE/last-patch-error")" "fake drydock: detail on stderr" "last-patch-error keeps drydock's stderr"
h_assert_contains "$(cat "$CC_STATE/last-patch-error")" "fake drydock: progress on stdout" "last-patch-error keeps drydock's stdout"
h_assert_eq "0" "$(leftovers)" "refusal leaves no temp files"

mkdir -p "$H/save"
mv "$H/cdn" "$H/save/cdn"
mv "$CC_STATE/verified/2.1.290" "$H/save/verified-2.1.290"
rm -f "$H/drydock-refuses"
BEFORE="$(count)"
ERR="$(cc_runnable 2.1.290 2>&1 >/dev/null)"
h_assert_contains "$ERR" "could not verify Claude Code 2.1.290 while offline" "offline note"
h_assert_contains "$ERR" "running 2.1.289" "offline names the fallback"
h_assert_eq "$(cc_entry 2.1.289)" "$(cc_runnable 2.1.290 2>/dev/null)" "offline with no entry and no recorded checksum runs the cached version"
h_assert_ok test -f "$CC_VERSIONS/2.1.290"
h_assert_eq "$BEFORE" "$(count)" "offline does not invoke drydock"
mv "$H/save/verified-2.1.290" "$CC_STATE/verified/2.1.290"
h_assert_eq "$(cc_entry 2.1.290)" "$(cc_runnable 2.1.290 2>/dev/null)" "offline with a recorded checksum builds"
cp "$CC_TREE/share/claude-code/recipe" "$H/save/recipe"
cp "$CC_TREE/share/claude-code/recipe-id" "$H/save/recipe-id"
printf 'a third recipe\n' > "$CC_TREE/share/claude-code/recipe"
cc_sha256 "$CC_TREE/share/claude-code/recipe" > "$CC_TREE/share/claude-code/recipe-id"
BEFORE="$(count)"
h_assert_eq "$(cc_entry 2.1.290)" "$(cc_runnable 2.1.290 2>/dev/null)" "offline after a recipe change, the recorded checksum still builds"
h_assert_eq "$((BEFORE+1))" "$(count)" "and that build ran drydock"
cp "$H/save/recipe" "$H/save/recipe-id" "$CC_TREE/share/claude-code/"
mv "$H/save/cdn" "$H/cdn"

rm -rf "$CC_CACHE"
printf '2.1.290\n' > "$H/drydock-refuses"
h_assert_eq "died" "$( (cc_runnable 2.1.290 >/dev/null 2>&1) && echo ok || echo died)" "refusal with nothing cached dies"
ERR="$( (cc_runnable 2.1.290 2>&1 >/dev/null) || true)"
h_assert_contains "$ERR" "cannot run Claude Code 2.1.290" "die names the version"
rm -f "$H/drydock-refuses"

rm -rf "$CC_CACHE"
: > "$H/drydock.log"
: > "$H/drydock-out.log"
: > "$H/drydock-barrier"
cc_runnable 2.1.289 > "$H/out1" 2>/dev/null &
P1=$!
cc_runnable 2.1.289 > "$H/out2" 2>/dev/null &
P2=$!
R1=0; R2=0
wait "$P1" || R1=$?
wait "$P2" || R2=$?
rm -f "$H/drydock-barrier"
h_assert_eq "0" "$R1" "first concurrent runnable exits 0"
h_assert_eq "0" "$R2" "second concurrent runnable exits 0"
h_assert_eq "2" "$(count)" "both concurrent builds ran drydock"
h_assert_eq "1" "$(find "$CC_CACHE" -name claude | wc -l | tr -d ' ')" "one entry after concurrent builds"
h_assert_eq "0" "$(leftovers)" "no temp files after concurrent builds"
h_assert_eq "$(cc_entry 2.1.289)" "$(cat "$H/out1")" "first prints the entry"
h_assert_eq "$(cc_entry 2.1.289)" "$(cat "$H/out2")" "second prints the entry"
O1="$(sed -n 1p "$H/drydock-out.log")"
O2="$(sed -n 2p "$H/drydock-out.log")"
h_assert_eq "$(dirname "$(cc_entry 2.1.289)")" "$(dirname "$O1")" "first temp file is in the entry's directory"
h_assert_eq "$(dirname "$(cc_entry 2.1.289)")" "$(dirname "$O2")" "second temp file is in the entry's directory"
h_assert_eq "different" "$([ "$O1" = "$O2" ] && echo same || echo different)" "concurrent builds use distinct temp files"
h_assert_eq "different" "$([ "$O1" = "$(cc_entry 2.1.289)" ] && echo same || echo different)" "temp file is not the entry"

rm -rf "$CC_CACHE"
mkdir -p "$(dirname "$(cc_entry 2.1.289)")"
touch -t 200001010000 "$(dirname "$(cc_entry 2.1.289)")/claude.1.STALE0"
touch "$(dirname "$(cc_entry 2.1.289)")/claude.2.FRESH0"
cc_build 2.1.289
h_assert_absent "$(dirname "$(cc_entry 2.1.289)")/claude.1.STALE0" "stale temp file is removed"
h_assert_ok test -f "$(dirname "$(cc_entry 2.1.289)")/claude.2.FRESH0"
rm -f "$(dirname "$(cc_entry 2.1.289)")/claude.2.FRESH0"

rm -rf "$CC_CACHE"
: > "$CC_CACHE"
echo stale > "$CC_STATE/last-patch-error"
RC=0
cc_build 2.1.289 2>/dev/null || RC=$?
h_assert_eq "3" "$RC" "unusable cache directory returns 3"
h_assert_contains "$(cat "$CC_STATE/last-patch-error")" "could not create" "last-patch-error says why"
rm -f "$CC_CACHE"

mv "$CC_TREE/share/claude-code/recipe-id" "$H/recipe-id.save"
ERR="$( (cc_runnable 2.1.289 2>&1 >/dev/null) || true)"
h_assert_contains "$ERR" "recipe-id" "missing recipe-id dies"
: > "$CC_TREE/share/claude-code/recipe-id"
ERR="$( (cc_runnable 2.1.289 2>&1 >/dev/null) || true)"
h_assert_contains "$ERR" "recipe-id" "empty recipe-id dies"
h_assert_absent "$CC_CACHE" "no cache entry without a recipe id"
mv "$H/recipe-id.save" "$CC_TREE/share/claude-code/recipe-id"

KEY="$(cut -c1-16 "$CC_TREE/share/claude-code/recipe-id")"
h_cdn_publish 2.1.299
cc_fetch 2.1.299
for v in 2.1.100 2.1.289; do mkdir -p "$CC_CACHE/$v-$KEY"; : > "$CC_CACHE/$v-$KEY/claude"; done
mkdir -p "$CC_CACHE/2.1.295-0123456789abcdef"; : > "$CC_CACHE/2.1.295-0123456789abcdef/claude"
printf '2.1.299\n' > "$H/drydock-refuses"
h_assert_eq "$CC_CACHE/2.1.289-$KEY/claude" "$(cc_runnable 2.1.299 2>/dev/null)" "fallback picks the newest entry for this recipe id by version order"
