#!/bin/sh
# platform: macOS-only -- the launcher library targets Mac OS X 10.9's sh and tools
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
. "$H/root/usr/local/mavergreen/claude-code/libexec/claude-code/lib.sh"

h_assert_ok cc_ver_gt 2.1.289 2.1.288
h_assert_ok cc_ver_gt 2.1.1000 2.1.999
h_assert_ok cc_ver_gt 2.10.0 2.9.9
h_assert_ok cc_ver_gt 2.1 2.0.9
h_assert_fails cc_ver_gt 2.1.288 2.1.289
h_assert_fails cc_ver_gt 2.1.289 2.1.289
h_assert_fails cc_ver_gt 2.1 2.1.0

h_assert_ok cc_is_version 2.1.289
h_assert_fails cc_is_version 2.1.289.tmp.123
h_assert_fails cc_is_version 2.1.289.new
h_assert_fails cc_is_version staging
h_assert_fails cc_is_version ''

for v in 1 TRUE Yes on; do h_assert_ok cc_truthy "$v"; done
for v in 0 false '' off; do h_assert_fails cc_truthy "$v"; done

printf 'abc' > "$H/sum"
h_assert_eq ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad "$(cc_sha256 "$H/sum")" "cc_sha256"

T="$H/root/usr/local/mavergreen/claude-code"
mkdir -p "$T/bin" "$H/links"
: > "$T/bin/claude"
ln -s "$T/bin/claude" "$H/links/hop2"
ln -s hop2 "$H/links/hop1"
cc_init "$H/links/hop1"
PT="$(cd "$T" && pwd -P)"
h_assert_eq "$PT" "$CC_TREE" "cc_init CC_TREE through two hops"
h_assert_eq "$(dirname "$PT")" "$CC_MG" "cc_init CC_MG"
h_assert_eq "$HOME/.local/bin/claude" "$CC_LINK" "cc_init CC_LINK"
h_assert_eq "$HOME/Library/Caches/dev.mavergreen.claude-code" "$CC_CACHE" "cc_init CC_CACHE"
h_assert_eq "$HOME/Library/Application Support/dev.mavergreen.claude-code" "$CC_STATE" "cc_init CC_STATE"
h_assert_eq "$HOME/.local/share/claude/versions" "$CC_VERSIONS" "cc_init CC_VERSIONS"
case "$CC_CDN" in file://*/cdn) h_assert_eq ok ok "cc_init CC_CDN ends in /cdn" ;; *) h_assert_eq "file://.../cdn" "$CC_CDN" "cc_init CC_CDN ends in /cdn" ;; esac

h_cdn_publish 2.1.5
h_cdn_latest 2.1.5
h_assert_eq 2.1.5 "$(cat "$H/cdn/latest")" "cdn latest"
h_assert_contains "$(cat "$H/cdn/2.1.5/manifest.json")" "\"checksum\": \"$(cc_sha256 "$H/cdn/2.1.5/darwin-x64/claude")\"" "manifest checksum"
out="$("$H/cdn/2.1.5/darwin-x64/claude" a "b c")"
h_assert_contains "$out" "fake-claude 2.1.5" "fake claude banner"
h_assert_contains "$out" "arg:b c" "fake claude argv"
h_assert_contains "$out" "env:CLAUDE_ENV_FILE=" "fake claude env"

h_cdn_publish 2.1.6 extra-content-marker
h_assert_contains "$(cat "$H/cdn/2.1.6/darwin-x64/claude")" "# extra-content-marker" "publish CONTENT"
h_assert_fails test "$(cc_sha256 "$H/cdn/2.1.6/darwin-x64/claude")" = "$(cc_sha256 "$H/cdn/2.1.5/darwin-x64/claude")"
h_assert_contains "$(grep -c checksum "$H/cdn/2.1.5/manifest.json")" 2 "manifest has two platform checksums"
h_assert_eq "darwin-arm64" "$(grep -o "darwin-[a-z0-9]*" "$H/cdn/2.1.5/manifest.json" | head -n 1)" "arm64 listed first"

r=$(cc_note hello 2>&1 >/dev/null)
h_assert_eq "claude: hello" "$r" "cc_note"
rc=0; r=$( (cc_die boom) 2>&1 ) || rc=$?
h_assert_eq 1 "$rc" "cc_die status"
h_assert_eq "claude: boom" "$r" "cc_die message"

R="$T/share/claude-code"
h_assert_eq "$(cc_sha256 "$R/recipe")" "$(cat "$R/recipe-id")" "recipe-id is recipe sha"
h_assert_eq "avxemu https://example.invalid/avxemu/releases
fakert https://example.invalid/fakert/releases" "$(cat "$R/requires")" "requires lines"
h_assert_eq 2 "$(wc -l < "$R/requires" | tr -d " ")" "requires has two lines"
h_assert_ok test -f "$H/root/usr/local/mavergreen/avxemu/mavergreen.plist"
h_assert_ok test -f "$H/root/usr/local/mavergreen/fakert/mavergreen.plist"

h_fake_drydock
printf '# fake recipe\n' | "$T/libexec/drydock-macho-rewrite" "$H/sum" "$H/sum.out"
h_assert_contains "$(tail -n 1 "$H/sum.out")" "# patched-by-fake $(cc_sha256 "$T/share/claude-code/recipe")" "drydock marker"
h_assert_eq 1 "$(wc -l < "$H/drydock.log" | tr -d ' ')" "drydock log"
echo sum > "$H/drydock-refuses"
rc=0; printf 'x\n' | "$T/libexec/drydock-macho-rewrite" "$H/sum" "$H/sum.out2" || rc=$?
h_assert_eq 3 "$rc" "drydock refuses"
h_assert_eq "no" "$([ -e "$H/sum.out2" ] && echo yes || echo no)" "refused writes nothing"
h_assert_contains "$(sysctl -n machdep.cpu.features)" " AVX1.0 " "fake sysctl features"
h_assert_contains "$(sysctl -n machdep.cpu.leaf7_features)" " AVX2 " "fake sysctl leaf7"

echo "lib-test: ok"
