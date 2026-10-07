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
h_assert_eq "3" "$(grep -c '^dylib ' "$H/out1/recipe")" "exactly three dylib replacements"
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
rel="$H/rel/v0.1.0"
mkdir -p "$rel"
printf 'binary bytes\n' > "$rel/drydock-macho-rewrite"
good="$(shasum -a 256 "$rel/drydock-macho-rewrite" | cut -d' ' -f1)"
export DRYDOCK_RELEASES="$(url "$H/rel")"

printf '%s  drydock-macho-rewrite\n' "$good" > "$rel/SHA256SUMS"
mkdir "$H/f1"
h_assert_ok sh "$PK/fetch-drydock.sh" 0.1.0 "$H/f1"
h_assert_ok test -x "$H/f1/drydock-macho-rewrite"
h_assert_eq "binary bytes" "$(cat "$H/f1/drydock-macho-rewrite")" "fetched bytes"

printf '%064d  drydock-macho-rewrite\n' 0 > "$rel/SHA256SUMS"
mkdir "$H/f2"
rc=0; out="$(sh "$PK/fetch-drydock.sh" 0.1.0 "$H/f2" 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "wrong digest fails"
h_assert_contains "$out" "does not match" "mismatch message"
h_assert_eq "" "$(ls -A "$H/f2")" "nothing left in OUTDIR after a mismatch"

printf '%s  drydock-macho-rewrite-compat.sh\n' "$good" > "$rel/SHA256SUMS"
mkdir "$H/f4"
rc=0; out="$(sh "$PK/fetch-drydock.sh" 0.1.0 "$H/f4" 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "near-miss name fails"
h_assert_contains "$out" "not listed" "near-miss name is not listed"

printf '%s *drydock-macho-rewrite\n' "$good" > "$rel/SHA256SUMS"
mkdir "$H/f5"
h_assert_ok sh "$PK/fetch-drydock.sh" 0.1.0 "$H/f5"

printf '%s  other-asset\n' "$good" > "$rel/SHA256SUMS"
mkdir "$H/f3"
rc=0; out="$(sh "$PK/fetch-drydock.sh" 0.1.0 "$H/f3" 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "unlisted asset fails"
h_assert_contains "$out" "not listed" "unlisted message"
h_assert_eq "" "$(ls -A "$H/f3")" "nothing left in OUTDIR when unlisted"

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

echo "packaging-test: ok"
