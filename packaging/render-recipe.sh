#!/bin/sh
# platform: host-agnostic
#   usage: render-recipe.sh DRYDOCK-BINARY OUTDIR
#          writes OUTDIR/recipe, OUTDIR/recipe-id and OUTDIR/requires; each requires line is a
#          product's short name, its latest-release URL (the repo from shipyard's product-name.sh) and,
#          when it has one, its minimum version.
set -eu
[ $# -eq 2 ] || { echo "usage: render-recipe.sh DRYDOCK-BINARY OUTDIR" >&2; exit 2; }
bin="$1"; out="$2"
here="$(cd "$(dirname "$0")" && pwd)"
[ -f "$bin" ] || { echo "no such drydock binary: $bin" >&2; exit 1; }
[ -d "$out" ] || { echo "no such directory: $out" >&2; exit 1; }
. "$here/../build/msc.sh"
req="$out/.requires.$$"
trap 'rm -f "$req"' EXIT
: > "$req"
for entry in avxemu recaulk 'libcxx22>=22.1.8-mavericks.5' icu; do
  short="${entry%%>=*}"; min=""
  case "$entry" in *">="*) min=" ${entry#*>=}" ;; esac
  repo="$(sh "$SHIPYARD_SCRIPTS/product-name.sh" repo "$short")"
  [ -n "$repo" ] || { echo "no repo for $short" >&2; exit 1; }
  printf '%s https://github.com/Mavergreen/%s/releases/latest%s\n' "$short" "$repo" "$min" >> "$req"
done
mv -f "$req" "$out/requires"
cp "$here/recipe.in" "$out/recipe"
cat "$out/recipe" "$bin" | shasum -a 256 | cut -d' ' -f1 > "$out/recipe-id"
