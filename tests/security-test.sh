#!/bin/sh
# platform: macOS-only -- Claude Code stores its credentials with security(1), whose 10.9 version has no -X
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
CB="$H/root/usr/local/mavergreen/claude-code/libexec/claude-code/claude-bin"
SEC="$CB/security"
NL='
'
cat > "$H/bin/fake-security" <<'FAKE'
#!/bin/sh
printf '%s\n' "$@" > "$H/sec.argv"
cat > "$H/sec.stdin"
[ ! -f "$H/sec.stderr" ] || cat "$H/sec.stderr" >&2
exit "$(cat "$H/sec.rc" 2>/dev/null || echo 0)"
FAKE
chmod +x "$H/bin/fake-security"
CC_SECURITY="$H/bin/fake-security"
export CC_SECURITY
reset() { rm -f "$H/sec.argv" "$H/sec.stdin" "$H/sec.stderr" "$H/sec.rc"; }
hex() { printf '%s' "$1" | od -An -tx1 | tr -d ' \n'; }
argv() { tr '\n' '|' < "$H/sec.argv"; }

h_assert_ok test -x "$SEC"
h_assert_eq "# platform: macOS-only -- Mac OS X 10.9's security has no -X, and its -i exits 0 when its command fails" "$(sed -n 2p "$SEC")" "security declares its platform"

reset; printf '44' > "$H/sec.rc"
rc=0; "$SEC" find-generic-password -a acct -w -s svc </dev/null || rc=$?
h_assert_eq "find-generic-password|-a|acct|-w|-s|svc|" "$(argv)" "a call without -X or -i passes through unchanged"
h_assert_eq "44" "$rc" "its exit status passes through"

J='{"claudeAiOauth":{"accessToken":"a'"'"'b\\c","scopes":["x y"]}}'
reset
rc=0; "$SEC" add-generic-password -U -a acct -s svc -X "$(hex "$J")" </dev/null || rc=$?
h_assert_eq "add-generic-password|-U|-a|acct|-s|svc|-w|$J|" "$(argv)" "argv -X HEX becomes -w with the decoded value"
h_assert_eq "0" "$rc" "argv -X succeeds"

reset
rc=0; printf 'add-generic-password -U -a "acct" -s "svc" -X "%s"\n' "$(hex "$J")" | "$SEC" -i || rc=$?
h_assert_eq "-i|" "$(argv)" "-i keeps the secret off the command line"
want="'add-generic-password' '-U' '-a' 'acct' '-s' 'svc' '-w' '{\"claudeAiOauth\":{\"accessToken\":\"a\\'b\\\\\\\\c\",\"scopes\":[\"x y\"]}}'"
h_assert_eq "$want" "$(cat "$H/sec.stdin")" "-i: -X HEX becomes -w, single-quoted with \\ and ' escaped, as 10.9's -i reads it"
h_assert_eq "0" "$rc" "-i success exits 0"

reset; printf 'security: SecKeychainItemCreateFromContent: User interaction is not allowed.\nadd-generic-password: returned -25308\n' > "$H/sec.stderr"
rc=0; err="$(printf 'add-generic-password -U -a "acct" -s "svc" -X "%s"\n' "$(hex x)" | "$SEC" -i 2>&1)" || rc=$?
h_assert_eq "36" "$rc" "-i exits with the failed command's status, as modern macOS does (36: keychain locked)"
h_assert_contains "$err" "returned -25308" "-i passes security's own message through"

reset; printf 'find-generic-password: returned -25300\n' > "$H/sec.stderr"
rc=0; printf 'find-generic-password -a "acct" -s "svc"\n' | "$SEC" -i 2>/dev/null || rc=$?
h_assert_eq "44" "$rc" "-i without -X still reports a failure (44: not found)"
h_assert_eq "find-generic-password -a \"acct\" -s \"svc\"" "$(cat "$H/sec.stdin")" "-i lines without -X pass through unchanged"

reset
rc=0; err="$("$SEC" add-generic-password -a acct -s svc -X 7g </dev/null 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "-X with bad hex fails"
h_assert_contains "$err" "-X" "the failure names -X"
h_assert_fails test -e "$H/sec.argv"
