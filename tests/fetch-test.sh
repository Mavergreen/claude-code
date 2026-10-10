#!/bin/sh
# platform: macOS-only -- the launcher fetches with 10.9's curl and shasum
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
CC_LIBEXEC="$H/root/usr/local/mavergreen/claude-code/libexec/claude-code"
. "$CC_LIBEXEC/lib.sh"
. "$CC_LIBEXEC/fetch.sh"
cc_init "$H/root/usr/local/mavergreen/claude-code/bin/claude"
h_assert_eq "$H/root/usr/local/mavergreen/claude-code" "$CC_TREE" "the tests run against the copied tree"

h_cdn_publish 2.1.289
h_cdn_publish 2.1.290 "newer"
h_cdn_latest 2.1.290
h_assert_eq "2.1.290" "$(cc_latest)" "cc_latest reads and strips the channel file"

want_x64="$(cc_sha256 "$H/cdn/2.1.289/darwin-x64/claude")"
want_arm64="$(printf 'arm64-2.1.289' | shasum -a 256 | cut -d' ' -f1)"
cc_manifest_sum 2.1.289
got="$_cc_msum"
h_assert_eq "$want_x64" "$got" "manifest sum is darwin-x64's"
h_assert_eq "no" "$([ "$got" = "$want_arm64" ] && echo yes || echo no)" "manifest sum is not darwin-arm64's"

h_assert_absent "$CC_VERSIONS" "versions dir absent before fetch"
h_assert_ok cc_fetch 2.1.289
h_assert_ok test -x "$CC_VERSIONS/2.1.289"
h_assert_eq "$want_x64" "$(cc_sha256 "$CC_VERSIONS/2.1.289")" "fetched file is the CDN binary"
h_assert_eq "" "$(ls "$CC_VERSIONS" | grep 'mavergreen-dl' || true)" "no temp file left"

h_assert_ok cc_verified 2.1.289
printf '# tampered\n' >> "$CC_VERSIONS/2.1.289"
rc=0; cc_verified 2.1.289 || rc=$?
h_assert_eq "1" "$rc" "cc_verified: 1 on mismatch"
h_assert_fails test -e "$CC_STATE/verified/2.1.289"
rc=0; cc_verified 9.9.9 || rc=$?
h_assert_eq "3" "$rc" "cc_verified: 3 when the version is not published (file:// reports a missing manifest as curl's 37)"

printf '# changed after manifest\n' >> "$H/cdn/2.1.290/darwin-x64/claude"
rc=0; out="$(cc_fetch 2.1.290 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "cc_fetch fails on mismatch"
h_assert_contains "$out" "Claude Code 2.1.290 failed its checksum (expected " "mismatch message"
h_assert_absent "$CC_VERSIONS/2.1.290" "no binary on mismatch"
h_assert_eq "" "$(ls "$CC_VERSIONS" | grep 'mavergreen-dl' || true)" "no temp file after mismatch"

mkdir -p "$H/cdn/2.1.291/darwin-x64"
printf 'x' > "$H/cdn/2.1.291/darwin-x64/claude"
printf '{\n  "platforms": {\n    "darwin-arm64": {\n      "checksum": "%s"\n    }\n  }\n}\n' "$want_arm64" > "$H/cdn/2.1.291/manifest.json"
rc=0; cc_manifest_sum 2.1.291 || rc=$?
h_assert_eq "1" "$rc" "no darwin-x64 block: no sum"
rc=0; out="$(cc_fetch 2.1.291 2>&1)" || rc=$?
h_assert_contains "$out" "could not read the checksum for Claude Code 2.1.291" "no-checksum message"
h_assert_contains "$out" "from $CC_CDN: its manifest lists no darwin-x64 checksum" "the no-checksum message says what the manifest lacked"
h_assert_eq "1" "$rc" "cc_fetch fails without a darwin-x64 checksum"
h_assert_absent "$CC_VERSIONS/2.1.291" "no binary without checksum"

h_cdn_publish 2.1.292
rm "$H/cdn/2.1.292/darwin-x64/claude"
rc=0; out="$(cc_fetch 2.1.292 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "cc_fetch fails when the binary is missing from the CDN"
h_assert_contains "$out" "could not download Claude Code 2.1.292" "download failure message"
h_assert_contains "$out" "from $CC_CDN: curl: (37) " "the download failure message carries curl's own error, so a missing file and an unreachable CDN read differently"
h_assert_absent "$CC_VERSIONS/2.1.292" "no binary on download failure"
h_assert_eq "" "$(ls "$CC_VERSIONS" | grep 'mavergreen-dl' || true)" "no temp file after download failure"

h_cdn_publish 2.1.293
rc=0; cc_verified 2.1.293 || rc=$?
h_assert_eq "1" "$rc" "cc_verified: 1 when the local binary is missing"

printf '<html>oops</html>\n' > "$H/cdn/latest"
rc=0; out="$(cc_latest 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "cc_latest refuses an answer that is not a version"
h_assert_contains "$out" "unexpected answer from $CC_CDN" "and says whose answer it was"
h_cdn_latest 2.1.290

h_cdn_publish 2.1.294
cc_fetch 2.1.294 2>"$H/err"
h_assert_contains "$(cat "$H/err")" "claude: downloading Claude Code 2.1.294..." "a download says so"
h_assert_eq "$(cc_sha256 "$CC_VERSIONS/2.1.294")" "$(cat "$CC_STATE/verified/2.1.294")" "a fetch records the checksum it verified"
trap > "$H/traps"
h_assert_eq "" "$(grep -E 'INT|TERM|HUP' "$H/traps" || true)" "the download's traps are gone afterwards"
rm -f "$CC_STATE/verified/2.1.294"
h_assert_ok cc_verified 2.1.294
h_assert_eq "$(cc_sha256 "$CC_VERSIONS/2.1.294")" "$(cat "$CC_STATE/verified/2.1.294" 2>/dev/null || :)" "a manifest match records the checksum"

touch -t 200001010000 "$CC_VERSIONS/2.1.200.mavergreen-dl.111"
: > "$CC_VERSIONS/2.1.201.mavergreen-dl.222"
h_cdn_publish 2.1.295
cc_fetch 2.1.295 2>/dev/null
h_assert_fails test -e "$CC_VERSIONS/2.1.200.mavergreen-dl.111"
h_assert_ok test -e "$CC_VERSIONS/2.1.201.mavergreen-dl.222"
rm -f "$CC_VERSIONS/2.1.201.mavergreen-dl.222"

h_cdn_publish 2.1.299
printf '#!/bin/sh\nexit 1\n' > "$H/bin/mv"; chmod +x "$H/bin/mv"; hash -r
rc=0; out="$(cc_fetch 2.1.299 2>&1)" || rc=$?
rm -f "$H/bin/mv"; hash -r
h_assert_eq "1" "$rc" "cc_fetch fails when the verified download cannot be moved into place"
h_assert_contains "$out" "could not install Claude Code 2.1.299 into $CC_VERSIONS" "and says where it could not install it"
h_assert_absent "$CC_VERSIONS/2.1.299" "no binary when the move fails"
h_assert_eq "" "$(ls "$CC_VERSIONS" | grep 'mavergreen-dl' || true)" "no temp file when the move fails"
h_assert_absent "$CC_STATE/verified/2.1.299" "no recorded checksum when the move fails"

h_fake_curl
h_cdn_publish 2.1.296
: > "$H/curl.log"
cc_latest >/dev/null
cc_fetch 2.1.296 2>/dev/null
curlargs() { grep -F "$1" "$H/curl.log" | tail -n 1; }
for u in /latest /2.1.296/manifest.json; do
  h_assert_contains "$(curlargs "$u")" "--connect-timeout 20" "$u: connect timeout"
  h_assert_contains "$(curlargs "$u")" "--max-time 60" "$u: overall timeout"
done
h_assert_contains "$(curlargs /2.1.296/darwin-x64/claude)" "--connect-timeout 20" "download: connect timeout"
h_assert_contains "$(curlargs /2.1.296/darwin-x64/claude)" "--speed-limit 1024 --speed-time 60" "download: stall timeout"

h_cdn_publish 2.1.297
: > "$H/curl-hang"
( cc_fetch 2.1.297 ) 2>/dev/null &
fp=$!
n=0
until [ -s "$H/curl.pid" ] || [ "$n" -ge 30 ]; do sleep 1; n=$((n+1)); done
kill -TERM "$(cat "$H/curl.pid")" "$fp" 2>/dev/null || :
rc=0; { wait "$fp"; } 2>/dev/null || rc=$?
rm -f "$H/curl-hang" "$H/bin/curl"
h_assert_eq "143" "$rc" "an interrupted download ends by that signal"
h_assert_eq "" "$(ls "$CC_VERSIONS" | grep 'mavergreen-dl' || true)" "an interrupted download leaves no temp file"

cp "$CC_VERSIONS/2.1.294" "$CC_VERSIONS/2.1.298"
for f in "7 curl: (7) Failed to connect to downloads.claude.ai port 443: Connection refused" "6 curl: (6) Could not resolve host: downloads.claude.ai" "28 curl: (28) Connection timed out after 20001 milliseconds"; do
  h_curl_fails "${f%% *}" "${f#* }"
  rc=0; cc_verified 2.1.294 || rc=$?
  h_assert_eq "0" "$rc" "offline (curl ${f%% *}): the recorded checksum verifies"
  rc=0; cc_verified 2.1.298 || rc=$?
  h_assert_eq "2" "$rc" "offline (curl ${f%% *}) without a record: cannot verify"
done
for f in "22 curl: (22) The requested URL returned error: 404" "37 curl: (37) Couldn't open file /cdn/2.1.298/manifest.json"; do
  h_curl_fails "${f%% *}" "${f#* }"
  rc=0; cc_verified 2.1.294 || rc=$?
  h_assert_eq "0" "$rc" "not published (curl ${f%% *}): the recorded checksum still verifies"
  rc=0; cc_verified 2.1.298 || rc=$?
  h_assert_eq "3" "$rc" "not published (curl ${f%% *}) without a record: 3, which is not the offline 2"
done
h_offline
printf '# tampered\n' >> "$CC_VERSIONS/2.1.294"
rc=0; cc_verified 2.1.294 || rc=$?
h_assert_eq "1" "$rc" "offline: a record that does not match the binary is a mismatch"
h_online

CLAUDE_CODE_CDN="file:///nonexistent"; cc_init "$CC_TREE/bin/claude"

rc=0; out="$(cc_latest 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "cc_latest fails on unreachable CDN"
h_assert_contains "$out" "could not reach file:///nonexistent" "unreachable message"
h_assert_contains "$out" "could not reach file:///nonexistent: curl: (37) " "the unreachable message carries curl's own error"

echo "fetch-test: ok"

h_offline
rc=0; out="$(cc_fetch 2.1.296 2>&1)" || rc=$?
h_online
h_assert_eq "1" "$rc" "cc_fetch fails when the CDN cannot be reached"
h_assert_contains "$out" "could not read the checksum for Claude Code 2.1.296 from $CC_CDN: curl: (7) Failed to connect" "and the message carries curl's own error"
