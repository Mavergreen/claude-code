#!/bin/sh
# platform: macOS-only -- the launcher targets Mac OS X 10.9's sh and tools
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
CC_LIBEXEC="$H/root/usr/local/mavergreen/claude-code/libexec/claude-code"
. "$CC_LIBEXEC/lib.sh"
. "$CC_LIBEXEC/fetch.sh"
. "$CC_LIBEXEC/select.sh"
cc_init "$CC_LIBEXEC/lib.sh"
unset DISABLE_AUTOUPDATER

mkv() { mkdir -p "$CC_VERSIONS"; printf '#!/bin/sh\n' > "$CC_VERSIONS/$1"; chmod +x "$CC_VERSIONS/$1"; }

mkv 2.1.288
mkv 2.1.289
mkv 2.1.290.tmp.1
mkv 2.1.290.new
mkdir "$CC_VERSIONS/staging"
printf '#!/bin/sh\n' > "$CC_VERSIONS/2.1.291"
mkdir "$H/somedir"; mkdir "$CC_VERSIONS/2.1.292"
ln -s "$H/somedir" "$CC_VERSIONS/2.1.293"

h_assert_eq "2.1.288
2.1.289" "$(cc_installed | sort)" "cc_installed lists only executable regular files with version names"
h_assert_eq "2.1.289" "$(cc_newest)" "newest ignores temp, new, dirs, non-executable"
h_assert_eq "2.1.289" "$(cc_choose)" "choose picks newest"
h_assert_eq "2.1.289" "$(cat "$CC_STATE/current")" "current is written"

printf '2.1.288\n' > "$CC_STATE/current"
h_assert_eq "2.1.288" "$(DISABLE_AUTOUPDATER=1 cc_choose)" "hold keeps current"
h_assert_eq "2.1.289" "$(cc_choose)" "no hold: newest"
rm -f "$CC_STATE/current"
h_assert_eq "2.1.289" "$(DISABLE_AUTOUPDATER=1 cc_choose)" "hold without current: newest"
printf '2.1.250\n' > "$CC_STATE/current"
h_assert_eq "2.1.289" "$(DISABLE_AUTOUPDATER=1 cc_choose)" "hold with uninstalled current: newest"

printf '2.1.288\n' > "$CC_STATE/current"
cc_record_intent update
h_assert_eq "update" "$(cat "$CC_STATE/repick")" "update intent recorded"
h_assert_eq "2.1.289" "$(DISABLE_AUTOUPDATER=1 cc_choose)" "update beats hold"
h_assert_eq "no" "$([ -e "$CC_STATE/repick" ] && echo yes || echo no)" "marker is gone"

cc_record_intent install 2.1.288
h_assert_eq "install 2.1.288" "$(cat "$CC_STATE/repick")" "install intent recorded"
h_assert_eq "2.1.288" "$(cc_choose)" "install V honoured without hold"
h_assert_eq "2.1.289" "$(cc_choose)" "install applies once"

cc_record_intent install 9.9.9
h_assert_eq "2.1.289" "$(cc_choose)" "install of absent version: newest"
cc_record_intent install
h_assert_eq "install" "$(cat "$CC_STATE/repick")" "bare install recorded"
h_assert_eq "2.1.289" "$(cc_choose)" "bare install: newest"

cc_record_intent mcp list
h_assert_eq "no" "$([ -e "$CC_STATE/repick" ] && echo yes || echo no)" "other commands write nothing"

h_fake_curl
h_cdn_publish 2.1.287
printf '2.1.287\n' > "$H/cdn/stable"
cc_record_intent install stable
h_assert_eq "2.1.287" "$(cc_choose)" "install stable fetches the channel's version"
h_assert_ok test -x "$CC_VERSIONS/2.1.287"
h_assert_eq "2.1.289" "$(cc_choose)" "channel install applies once"
printf '2.1.288\n' > "$H/cdn/stable"
cc_record_intent install stable
h_assert_eq "2.1.288" "$(cc_choose)" "install stable uses an installed version"
h_assert_contains "$(grep -F /stable "$H/curl.log" | tail -n 1)" "--connect-timeout 20 --max-time 60" "the channel request is bounded"

cc_record_intent install rc
rc=0; out="$(cc_choose 2>&1)" || rc=$?
h_assert_eq "0" "$rc" "unreachable channel does not fail"
h_assert_contains "$out" "could not resolve" "unreachable channel is noted"
h_assert_contains "$out" "2.1.289" "unreachable channel falls back to newest"

rm -rf "$CC_VERSIONS" "$CC_STATE"
h_cdn_publish 2.1.289
h_cdn_latest 2.1.289
h_assert_eq "2.1.289" "$(cc_choose)" "empty versions: bootstrap from latest"
h_assert_ok test -x "$CC_VERSIONS/2.1.289"
h_assert_eq "2.1.289" "$(cat "$CC_STATE/current")" "bootstrap writes current"

mkv 2.1.289
printf '2.1.289\n' > "$CC_STATE/current"
printf '2.1.299\n' > "$H/cdn/stable"
cc_record_intent install stable
rc=0; out="$(cc_choose 2>&1)" || rc=$?
h_assert_eq "0" "$rc" "a failed channel fetch does not fail cc_choose"
h_assert_contains "$out" "could not fetch Claude Code 2.1.299 for the stable channel; using the newest installed version" "it says so"
h_assert_contains "$out" "2.1.289" "and falls back to newest"
h_assert_fails test -f "$CC_STATE/repick"
h_assert_eq "2.1.289" "$(cat "$CC_STATE/current")" "current is the fallback"

rm -rf "$CC_VERSIONS" "$CC_STATE"
mkdir -p "$CC_STATE" "$HOME/.claude"
mkv 2.1.288
mkv 2.1.289
CFG="$HOME/.claude/settings.json"
held() {
  printf '2.1.288\n' > "$CC_STATE/current"
  h_assert_eq "$1" "$(cc_choose)" "$2"
  printf '2.1.288\n' > "$CC_STATE/current"
  h_assert_eq "$1" "$(CC_PYTHON=/nonexistent cc_choose)" "$2 (without python)"
}
held 2.1.289 "no settings: newest"
printf '{\n  "env": {\n    "DISABLE_AUTOUPDATER": "1"\n  }\n}\n' > "$CFG"
held 2.1.288 "hold from settings.json env"
printf '{"env": {"DISABLE_AUTOUPDATER": "TRUE"}}' > "$CFG"
held 2.1.288 "a truthy word holds too"
printf '{"env": {"DISABLE_AUTOUPDATER": true}}' > "$CFG"
held 2.1.288 "a JSON true holds too"
printf '{"env": {"DISABLE_AUTOUPDATER": "0"}}' > "$CFG"
held 2.1.289 "a false value is no hold"
mv "$CFG" "$H/elsewhere.json"
mkdir -p "$H/cfg"
printf '{"env": {"DISABLE_AUTOUPDATER": "1"}}' > "$H/cfg/settings.json"
CLAUDE_CONFIG_DIR="$H/cfg"; export CLAUDE_CONFIG_DIR
held 2.1.288 "hold from CLAUDE_CONFIG_DIR's settings.json"
unset CLAUDE_CONFIG_DIR
held 2.1.289 "without CLAUDE_CONFIG_DIR that file is not read"
printf '{"env": {"DISABLE_AUTOUPDATER": "yes"}}' > "$CC_MANAGED_SETTINGS"
held 2.1.288 "hold from managed settings"
rm -f "$CC_MANAGED_SETTINGS"

touch -t 202601010000 "$CC_VERSIONS/2.1.289"
touch -t 202602010000 "$CC_VERSIONS/2.1.288"
printf '{"autoUpdatesChannel": "stable"}' > "$CFG"
h_assert_eq "2.1.288" "$(cc_choose)" "stable channel: the most recently downloaded, though older"
h_assert_eq "2.1.288" "$(CC_PYTHON=/nonexistent cc_choose)" "stable channel without python"
cc_record_intent update
h_assert_eq "2.1.288" "$(cc_choose)" "stable channel: update also takes the most recently downloaded"
mkv 2.1.206
touch -t 202603010000 "$CC_VERSIONS/2.1.206"
h_assert_eq "2.1.288" "$(cc_choose)" "stable channel never takes a version before 2.1.207"
printf '{"autoUpdatesChannel": "latest"}' > "$CFG"
h_assert_eq "2.1.289" "$(cc_choose)" "latest channel: highest number"
rm -f "$CFG"
h_assert_eq "2.1.289" "$(cc_choose)" "no channel: highest number"

rm -rf "$CC_VERSIONS" "$CC_STATE"
mkv 2.1.206
h_assert_eq "2.1.289" "$(cc_choose 2>/dev/null)" "a version before 2.1.207 is never chosen: bootstrap instead"
printf '2.1.206\n' > "$CC_STATE/current"
h_assert_eq "2.1.289" "$(DISABLE_AUTOUPDATER=1 cc_choose)" "a held current before 2.1.207 is not honoured"
out="$(cc_record_intent install 2.1.206 2>&1)"
h_assert_contains "$out" "Claude Code 2.1.206 predates 2.1.207" "an install before 2.1.207 says why it is not honoured"
h_assert_fails test -e "$CC_STATE/repick"
printf 'install 2.1.206\n' > "$CC_STATE/repick"
h_assert_eq "2.1.289" "$(cc_choose)" "a recorded install before 2.1.207 is not honoured"
mkv 2.1.207
cc_record_intent install 2.1.207
h_assert_eq "2.1.207" "$(cc_choose)" "2.1.207 itself is honoured"

E2E_OLDER="$(sed -n 's/^OLDER="\${CC_E2E_OLDER_VERSION:-\(.*\)}"$/\1/p' "$H_REPO/tests/e2e/run.sh")"
h_assert_ok cc_is_version "$E2E_OLDER"
h_assert_fails cc_predates_launcher "$E2E_OLDER"
