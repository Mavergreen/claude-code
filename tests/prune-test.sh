#!/bin/sh
# platform: macOS-only -- the launcher targets Mac OS X 10.9's sh and tools
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
CC_LIBEXEC="$H/root/usr/local/mavergreen/claude-code/libexec/claude-code"
. "$CC_LIBEXEC/lib.sh"
. "$CC_LIBEXEC/select.sh"
. "$CC_LIBEXEC/patch.sh"
. "$CC_LIBEXEC/prune.sh"
mkdir -p "$H/root/usr/local/mavergreen/claude-code/bin"
cc_init "$H/root/usr/local/mavergreen/claude-code/bin/claude"

ID="$(cc_recipe_key)"
OLD="0123456789abcdef"

reset() {
  rm -rf "$CC_VERSIONS" "$CC_CACHE" "$CC_STATE/verified"
  mkdir -p "$CC_VERSIONS" "$CC_CACHE" "$CC_STATE/verified"
  for v in "$@"; do
    printf '%064d\n' 0 > "$CC_STATE/verified/$v"
    printf '#!/bin/sh\n' > "$CC_VERSIONS/$v"
    chmod +x "$CC_VERSIONS/$v"
    mkdir -p "$CC_CACHE/$v-$ID"
    : > "$CC_CACHE/$v-$ID/claude"
  done
}
vlist() { ls "$CC_VERSIONS" | tr '\n' ' '; }
clist() { ls "$CC_CACHE" | tr '\n' ' '; }

reset 2.1.284 2.1.286 2.1.288 2.1.289
h_assert_ok cc_prune 2.1.289
h_assert_eq "2.1.288 2.1.289 " "$(vlist)" "running newest: it and its predecessor remain"
h_assert_eq "2.1.288-$ID 2.1.289-$ID " "$(clist)" "cache follows the same rule"
h_assert_eq "2.1.288 2.1.289 " "$(ls "$CC_STATE/verified" | tr '\n' ' ')" "recorded checksums follow their versions"

reset 2.1.284 2.1.286 2.1.288 2.1.289
h_assert_ok cc_prune 2.1.288
h_assert_eq "2.1.286 2.1.288 2.1.289 " "$(vlist)" "held: predecessor, running and newer remain"
h_assert_eq "2.1.286-$ID 2.1.288-$ID 2.1.289-$ID " "$(clist)" "cache keeps newer too"

reset 2.1.288 2.1.289
: > "$CC_VERSIONS/2.1.290.tmp.1"
mkdir "$CC_VERSIONS/staging"
: > "$CC_VERSIONS/2.1.287.new"
h_assert_ok cc_prune 2.1.289
h_assert_eq "2.1.287.new 2.1.288 2.1.289 2.1.290.tmp.1 staging " "$(vlist)" "non-version names are untouched"

reset 2.1.286 2.1.288 2.1.289
mkdir "$CC_CACHE/2.1.289-$OLD" "$CC_CACHE/2.1.100-$OLD" "$CC_CACHE/notes" "$CC_CACHE/2.1.289-xyz" "$CC_CACHE/2.1.289-${OLD}0" "$CC_CACHE/x-$OLD"
: > "$CC_CACHE/2.1.100-$OLD.file"
h_assert_ok cc_prune 2.1.289
h_assert_eq "2.1.100-$OLD.file 2.1.288-$ID 2.1.289-${OLD}0 2.1.289-$ID 2.1.289-xyz notes x-$OLD " "$(clist)" "old recipe entries removed; other shapes left alone"

reset 2.1.286 2.1.288
h_assert_ok cc_prune 2.1.289
h_assert_eq "2.1.288 " "$(vlist)" "running version absent from versions/: predecessor kept"
h_assert_eq "2.1.288-$ID " "$(clist)" "cache likewise"

reset
h_assert_ok cc_prune 2.1.289
h_assert_eq "" "$(vlist)" "empty versions is fine"

reset 2.1.286 2.1.288
OUT="$H/outside"; mkdir -p "$OUT"; : > "$OUT/keep"
: > "$CC_CACHE/2.1.100-$OLD"
ln -s "$OUT" "$CC_CACHE/2.1.101-$OLD"
mkdir "$H/vt"; printf '#!/bin/sh\n' > "$H/vt/target"; chmod +x "$H/vt/target"
ln -s "$H/vt/target" "$CC_VERSIONS/2.1.100"
h_assert_ok cc_prune 2.1.288
h_assert_eq "2.1.100-$OLD 2.1.101-$OLD 2.1.286-$ID 2.1.288-$ID " "$(clist)" "a file and a symlink with an entry's name survive"
h_assert_ok test -f "$OUT/keep"
h_assert_eq "2.1.286 2.1.288 " "$(vlist)" "symlinked version removed as a link"
h_assert_ok test -x "$H/vt/target"

reset 2.1.99 2.1.289 2.1.999 2.1.1000
h_assert_ok cc_prune 2.1.1001
h_assert_eq "2.1.1000 " "$(vlist)" "numeric order: only the predecessor of 1001"
h_assert_eq "2.1.1000-$ID " "$(clist)" "cache numeric order"

reset 2.1.99 2.1.289 2.1.999 2.1.1000
h_assert_ok cc_prune 2.1.1000
h_assert_eq "2.1.1000 2.1.999 " "$(vlist)" "numeric order: 999 precedes 1000"

reset 2.1.286 2.1.288
mkdir "$CC_CACHE/2.1.100-$OLD"
for bad in 2.1.x ''; do
  h_assert_ok cc_prune "$bad"
done
h_assert_eq "2.1.286 2.1.288 " "$(vlist)" "malformed running version removes nothing"
h_assert_eq "2.1.100-$OLD 2.1.286-$ID 2.1.288-$ID " "$(clist)" "nor cache entries"
h_assert_eq "" "$(cc_prune 2.1.x 2>&1)" "and prints nothing"

reset 2.1.284 2.1.286 2.1.288 2.1.289
mkdir "$H/hold"
cp /bin/sleep "$H/hold/claude"
( exec 3<"$CC_CACHE/2.1.286-$ID/claude"; exec "$H/hold/claude" 30 ) &
hp=$!
n=0
until case "$(ps -p "$hp" -o comm= 2>/dev/null)" in claude|*/claude) true ;; *) false ;; esac || [ "$n" -ge 30 ]; do sleep 1; n=$((n+1)); done
h_assert_ok cc_prune 2.1.289
h_assert_eq "2.1.286-$ID 2.1.288-$ID 2.1.289-$ID " "$(clist)" "an entry a process holds open survives; an unheld one goes"
kill "$hp"
{ wait "$hp"; } 2>/dev/null || :
h_assert_ok cc_prune 2.1.289
h_assert_eq "2.1.288-$ID 2.1.289-$ID " "$(clist)" "released, it is pruned"

reset 2.1.286 2.1.288 2.1.289
CC_LSOF=/nonexistent
h_assert_ok cc_prune 2.1.289
h_assert_eq "2.1.286-$ID 2.1.288-$ID 2.1.289-$ID " "$(clist)" "without lsof, entries are kept"
printf "#!/bin/sh\necho \"lsof: status error\" >&2\nexit 1\n" > "$H/lsof-err"
chmod +x "$H/lsof-err"
CC_LSOF="$H/lsof-err"
h_assert_ok cc_prune 2.1.289
h_assert_eq "2.1.286-$ID 2.1.288-$ID 2.1.289-$ID " "$(clist)" "an lsof error keeps entries"
unset CC_LSOF

h_teardown
