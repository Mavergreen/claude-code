#!/bin/sh
# platform: macOS-only -- the packaging scripts use curl and shasum, and the harness targets 10.9's sh
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
PK="$H_REPO/packaging"

mkdir "$H/shipyard"
cat > "$H/shipyard/product-name.sh" <<'STUB'
#!/bin/sh
[ "$1" = repo ] || { echo "unsupported: $1" >&2; exit 1; }
case "$2" in
  avxemu) echo avxemu ;;
  recaulk) echo recaulk ;;
  libcxx22) echo clang-22 ;;
  icu) echo icu ;;
  *) echo "unregistered: $2" >&2; exit 1 ;;
esac
STUB
SHIPYARD_SCRIPTS="$H/shipyard"; export SHIPYARD_SCRIPTS

printf 'drydock one\n' > "$H/dd1"
printf 'drydock two\n' > "$H/dd2"
mkdir "$H/out1" "$H/out2"
sh "$PK/render-recipe.sh" "$H/dd1" "$H/out1"
sh "$PK/render-recipe.sh" "$H/dd2" "$H/out2"

h_assert_eq "0" "$(grep -c '@' "$H/out1/recipe")" "no placeholder survives"
h_assert_eq "dylib         replace  /usr/lib/libSystem.B.dylib   /usr/local/mavergreen/recaulk/lib/libRecaulkSystem.dylib" "$(grep 'libSystem.B' "$H/out1/recipe")" "libSystem replacement"
h_assert_eq "dylib         replace  /usr/lib/libc++.1.dylib      /usr/local/mavergreen/libcxx22/lib/libc++.1.dylib" "$(grep 'libc++' "$H/out1/recipe")" "libc++ replacement"
h_assert_eq "dylib         replace  /usr/lib/libicucore.A.dylib  /usr/local/mavergreen/icu/lib/libicucore.dylib" "$(grep 'libicucore' "$H/out1/recipe")" "libicucore replacement"
h_assert_eq "4" "$(grep -c '^dylib' "$H/out1/recipe")" "three replacements and one insert"
h_assert_eq "dylib         insert   /usr/local/mavergreen/avxemu/lib/libavxemu.dylib" "$(sed -n 8p "$H/out1/recipe")" "avxemu is linked by an insert on line 8"
h_assert_contains "$(sed -n 1p "$H/out1/recipe")" "fixups        set      classic" "recipe starts with fixups"
h_assert_eq "$(cat "$H/out1/recipe" "$H/dd1" | shasum -a 256 | cut -d' ' -f1)" "$(cat "$H/out1/recipe-id")" "recipe-id is sha256 of recipe then binary"
h_assert_eq "65" "$(wc -c < "$H/out1/recipe-id" | tr -d ' ')" "recipe-id is 64 hex chars and a newline"
h_assert_ne() { [ "$1" != "$2" ] || { echo "FAIL: $3" >&2; H_FAILS=$((H_FAILS+1)); }; }
h_assert_ne "$(cat "$H/out1/recipe-id")" "$(cat "$H/out2/recipe-id")" "recipe-id changes with the binary"
h_assert_eq "4" "$(wc -l < "$H/out1/requires" | tr -d ' ')" "requires has four lines"
h_assert_eq "avxemu https://github.com/Mavergreen/avxemu/releases/latest" "$(sed -n 1p "$H/out1/requires")" "avxemu line"
h_assert_eq "recaulk https://github.com/Mavergreen/recaulk/releases/latest" "$(sed -n 2p "$H/out1/requires")" "recaulk line"
h_assert_eq "libcxx22 https://github.com/Mavergreen/clang-22/releases/latest" "$(sed -n 3p "$H/out1/requires")" "libcxx22 line"
h_assert_eq "icu https://github.com/Mavergreen/icu/releases/latest" "$(sed -n 4p "$H/out1/requires")" "icu line"
rc=0; out="$(sh "$PK/render-recipe.sh" "$H/dd1" 2>&1)" || rc=$?
h_assert_eq "2" "$rc" "wrong argument count exits 2"
h_assert_contains "$out" "usage:" "wrong argument count prints usage"

mkdir "$H/shipyard2" "$H/out5"
cat > "$H/shipyard2/product-name.sh" <<'STUB'
#!/bin/sh
[ "$2" = avxemu ] || { echo "unregistered: $2" >&2; exit 1; }
echo avxemu
STUB
rc=0; out="$(SHIPYARD_SCRIPTS="$H/shipyard2" sh "$PK/render-recipe.sh" "$H/dd1" "$H/out5" 2>&1)" || rc=$?
h_assert_ne "0" "$rc" "an unregistered product fails"
h_assert_contains "$out" "unregistered" "an unregistered product says why"

url() { printf 'file://%s' "$(printf %s "$1" | sed "s/%/%25/g; s/ /%20/g; s/#/%23/g; s/?/%3F/g")"; }
command -v pkgbuild >/dev/null 2>&1 && command -v productbuild >/dev/null 2>&1 && command -v pkgutil >/dev/null 2>&1 || exit 77
rel="$H/rel/v0.1.0"
mkdir -p "$rel"
comp() { pkgbuild --root "$H/$1" --identifier "$2" --version 1 --install-location / "$H/$3" >/dev/null 2>&1; }
mkdir -p "$H/pbase/usr/local/mavergreen/base" "$H/pdd/usr/local/mavergreen/drydock/bin" "$H/pother/usr/local/mavergreen/other"
: > "$H/pbase/usr/local/mavergreen/base/file"
: > "$H/pother/usr/local/mavergreen/other/file"
printf 'binary bytes\n' > "$H/pdd/usr/local/mavergreen/drydock/bin/drydock-macho-rewrite"
comp pbase dev.mavergreen.base pbase.pkg
comp pdd dev.mavergreen.drydock pdd.pkg
comp pother dev.mavergreen.other pother.pkg
productbuild --package "$H/pbase.pkg" --package "$H/pdd.pkg" "$rel/drydock-0.1.0.pkg" >/dev/null 2>&1
good="$(shasum -a 256 "$rel/drydock-0.1.0.pkg" | cut -d' ' -f1)"
export DRYDOCK_RELEASES="$(url "$H/rel")"

printf '%s  drydock-0.1.0.pkg\n' "$good" > "$rel/SHA256SUMS"
mkdir "$H/f1"
h_assert_ok sh "$PK/fetch-drydock.sh" 0.1.0 "$H/f1"
h_assert_ok test -x "$H/f1/drydock-macho-rewrite"
h_assert_eq "binary bytes" "$(cat "$H/f1/drydock-macho-rewrite")" "fetched bytes"
h_assert_eq "drydock-macho-rewrite" "$(ls -A "$H/f1")" "OUTDIR holds exactly the binary"

printf '%064d  drydock-0.1.0.pkg\n' 0 > "$rel/SHA256SUMS"
mkdir "$H/f2"
rc=0; out="$(sh "$PK/fetch-drydock.sh" 0.1.0 "$H/f2" 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "wrong digest fails"
h_assert_contains "$out" "does not match" "mismatch message"
h_assert_eq "" "$(ls -A "$H/f2")" "nothing left in OUTDIR after a mismatch"

printf '%s  drydock-0.1.0.pkg.sig\n' "$good" > "$rel/SHA256SUMS"
mkdir "$H/f4"
rc=0; out="$(sh "$PK/fetch-drydock.sh" 0.1.0 "$H/f4" 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "near-miss name fails"
h_assert_contains "$out" "not listed" "near-miss name is not listed"

printf '%s *drydock-0.1.0.pkg\n' "$good" > "$rel/SHA256SUMS"
mkdir "$H/f5"
h_assert_ok sh "$PK/fetch-drydock.sh" 0.1.0 "$H/f5"

printf '%s  other-asset\n' "$good" > "$rel/SHA256SUMS"
mkdir "$H/f3"
rc=0; out="$(sh "$PK/fetch-drydock.sh" 0.1.0 "$H/f3" 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "unlisted asset fails"
h_assert_contains "$out" "not listed" "unlisted message"
h_assert_eq "" "$(ls -A "$H/f3")" "nothing left in OUTDIR when unlisted"

productbuild --package "$H/pbase.pkg" --package "$H/pother.pkg" "$rel/drydock-0.1.0.pkg" >/dev/null 2>&1
printf '%s  drydock-0.1.0.pkg\n' "$(shasum -a 256 "$rel/drydock-0.1.0.pkg" | cut -d' ' -f1)" > "$rel/SHA256SUMS"
mkdir "$H/f6"
rc=0; out="$(sh "$PK/fetch-drydock.sh" 0.1.0 "$H/f6" 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "a pkg without the drydock component fails"
h_assert_contains "$out" "dev.mavergreen.drydock" "the failure names the identifier"
h_assert_eq "" "$(ls -A "$H/f6")" "nothing left in OUTDIR without the component"

if [ -x /usr/bin/python2.7 ]; then PY=/usr/bin/python2.7
elif command -v python3 >/dev/null 2>&1; then PY=python3
else PY=""; fi
if [ -n "$PY" ]; then
  rc=0
  out="$("$PY" - "$H_REPO/.github/renovate.json" 2>&1 <<'PYEOF'
import json, sys
c = json.load(open(sys.argv[1]))
m = [x for x in c["customManagers"] if x.get("depNameTemplate") == "Mavergreen/drydock"]
assert len(m) == 1, "no single drydock manager"
m = m[0]
assert m["managerFilePatterns"] == ["/^components/drydock/version$/"], m["managerFilePatterns"]
assert m["datasourceTemplate"] == "github-releases"
assert m["extractVersionTemplate"] == "^v(?<version>.+)$"
PYEOF
)" || rc=$?
  h_assert_eq "0" "$rc" "renovate.json parses and its drydock manager is right: $out"
fi
