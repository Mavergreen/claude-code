#!/bin/sh
# platform: macOS-only -- the packaging scripts use curl and shasum, and the harness targets 10.9's sh
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
PK="$H_REPO/packaging"
export RUNTIME_RELEASES_URL="https://example.invalid/fakert/releases"

printf 'drydock one\n' > "$H/dd1"
printf 'drydock two\n' > "$H/dd2"
mkdir "$H/out1" "$H/out2" "$H/out3"
sh "$PK/render-recipe.sh" fakert "$H/dd1" "$H/out1"
sh "$PK/render-recipe.sh" fakert "$H/dd2" "$H/out2"
sh "$PK/render-recipe.sh" otherrt "$H/dd1" "$H/out3"

h_assert_eq "0" "$(grep -c '@RUNTIME@' "$H/out1/recipe")" "no placeholder survives"
h_assert_eq "3" "$(grep -c '/usr/local/mavergreen/fakert/lib/' "$H/out1/recipe")" "three dylib targets name the runtime"
h_assert_contains "$(sed -n 1p "$H/out1/recipe")" "fixups        set      classic" "recipe starts with fixups"
h_assert_eq "$(cat "$H/out1/recipe" "$H/dd1" | shasum -a 256 | cut -d' ' -f1)" "$(cat "$H/out1/recipe-id")" "recipe-id is sha256 of recipe then binary"
h_assert_eq "65" "$(wc -c < "$H/out1/recipe-id" | tr -d ' ')" "recipe-id is 64 hex chars and a newline"
h_assert_ne() { [ "$1" != "$2" ] || { echo "FAIL: $3" >&2; H_FAILS=$((H_FAILS+1)); }; }
h_assert_ne "$(cat "$H/out1/recipe-id")" "$(cat "$H/out2/recipe-id")" "recipe-id changes with the binary"
h_assert_ne "$(cat "$H/out1/recipe-id")" "$(cat "$H/out3/recipe-id")" "recipe-id changes with the recipe"
h_assert_eq "2" "$(wc -l < "$H/out1/requires" | tr -d ' ')" "requires has two lines"
h_assert_eq "avxemu https://github.com/Mavergreen/avxemu/releases" "$(sed -n 1p "$H/out1/requires")" "avxemu line"
h_assert_eq "fakert https://example.invalid/fakert/releases" "$(sed -n 2p "$H/out1/requires")" "runtime line"
rc=0; out="$(sh "$PK/render-recipe.sh" fakert "$H/dd1" 2>&1)" || rc=$?
h_assert_eq "2" "$rc" "wrong argument count exits 2"
h_assert_contains "$out" "usage:" "wrong argument count prints usage"
rc=0; out="$(sh "$PK/render-recipe.sh" 'bad/name' "$H/dd1" "$H/out1" 2>&1)" || rc=$?
h_assert_eq "2" "$rc" "invalid runtime name exits 2"
h_assert_contains "$out" "invalid runtime name" "invalid runtime name message"

mkdir "$H/shipyard" "$H/out4" "$H/out5"
cat > "$H/shipyard/product-name.sh" <<'STUB'
#!/bin/sh
[ "$1 $2" = "repo fakert" ] || { echo "unregistered: $2" >&2; exit 1; }
echo mavericks-fakert-repo
STUB
(
  unset RUNTIME_RELEASES_URL
  SHIPYARD_SCRIPTS="$H/shipyard"; export SHIPYARD_SCRIPTS
  sh "$PK/render-recipe.sh" fakert "$H/dd1" "$H/out4"
  rc=0; out="$(sh "$PK/render-recipe.sh" unknownrt "$H/dd1" "$H/out5" 2>&1)" || rc=$?
  echo "$rc" > "$H/rc5"; echo "$out" > "$H/msg5"
)
h_assert_eq "fakert https://github.com/Mavergreen/mavericks-fakert-repo/releases" "$(sed -n 2p "$H/out4/requires")" "runtime url from product-name.sh"
h_assert_ne "0" "$(cat "$H/rc5")" "unregistered runtime fails"
h_assert_contains "$(cat "$H/msg5")" "unregistered" "unregistered runtime says why"

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
