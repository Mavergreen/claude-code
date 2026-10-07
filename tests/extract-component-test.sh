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
