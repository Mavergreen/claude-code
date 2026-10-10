#!/bin/sh
# platform: macOS-only -- builds a package with pkgbuild and expands it with pkgutil
set -eu
. "$(dirname "$0")/lib/harness.sh"
command -v pkgbuild >/dev/null 2>&1 && command -v pkgutil >/dev/null 2>&1 || exit 77
h_setup
X="$H_REPO/packaging/extract-component.sh"
mkdir -p "$H/root/f" "$H/dest"
echo hi > "$H/root/f/file"
pkgbuild --root "$H/root" --identifier "com.example-comp" --version 1 --install-location / "$H/c.pkg" >/dev/null 2>&1

rc=0; sh "$X" "$H/c.pkg" "com.example-comp" "$H/dest" >/dev/null 2>&1 || rc=$?
h_assert_eq 0 "$rc" "extracts the component whose identifier matches"
h_assert_ok test -f "$H/dest/f/file"

rc=0; err="$(sh "$X" "$H/c.pkg" "com.example.comp" "$H/dest" 2>&1)" || rc=$?
h_assert_eq 1 "$rc" "an identifier is a fixed string, not a pattern"
h_assert_contains "$err" "no component com.example.comp" "the refusal names the identifier"

mkdir -p "$H/np/scripts"
printf '#!/bin/sh\nexit 0\n' > "$H/np/scripts/postinstall"; chmod +x "$H/np/scripts/postinstall"
pkgbuild --nopayload --scripts "$H/np/scripts" --identifier com.example.np --version 1 "$H/np.pkg" >/dev/null 2>&1
rc=0; err="$(sh "$X" "$H/np.pkg" com.example.np "$H/dest" 2>&1)" || rc=$?
h_assert_eq 1 "$rc" "a component without a payload fails"
h_assert_eq "extract-component: component com.example.np has no payload" "$err" "and says so, naming it"

rc=0; err="$(sh "$X" "$H/c.pkg" com.example-comp 2>&1)" || rc=$?
h_assert_eq 2 "$rc" "a wrong argument count exits 2"
h_assert_contains "$err" "usage: extract-component.sh PKG IDENTIFIER DESTDIR" "and prints the usage"
rc=0; err="$(sh "$X" "$H/none.pkg" com.example-comp "$H/dest" 2>&1)" || rc=$?
h_assert_eq 1 "$rc" "a missing package fails"
h_assert_eq "extract-component: no such package: $H/none.pkg" "$err" "and names it"
rc=0; err="$(sh "$X" "$H/c.pkg" com.example-comp "$H/nodest" 2>&1)" || rc=$?
h_assert_eq 1 "$rc" "a missing destination fails"
h_assert_eq "extract-component: no such directory: $H/nodest" "$err" "and names it"
printf 'not a package\n' > "$H/bad.pkg"
rc=0; err="$(sh "$X" "$H/bad.pkg" com.example-comp "$H/dest" 2>&1)" || rc=$?
h_assert_eq 1 "$rc" "a file that is not a package fails"
h_assert_contains "$err" "extract-component: cannot expand $H/bad.pkg" "and says it cannot expand it"

pkgutil --expand "$H/c.pkg" "$H/cx"
printf 'not a cpio archive\n' | gzip -c > "$H/cx/Payload"
pkgutil --flatten "$H/cx" "$H/badpayload.pkg"
mkdir "$H/dest2"
rc=0; err="$(sh "$X" "$H/badpayload.pkg" com.example-comp "$H/dest2" 2>&1)" || rc=$?
h_assert_eq 1 "$rc" "a payload cpio cannot read fails"
h_assert_contains "$err" "extract-component: cannot unpack component com.example-comp: cpio: " "and says why, in cpio's own words"
rc=0; err="$(sh "$X" "$H/c.pkg" com.example-comp "$H/dest2" 2>&1)" || rc=$?
h_assert_eq "" "$err" "a payload that unpacks prints nothing, not cpio's block count"
