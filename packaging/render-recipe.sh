#!/bin/sh
# platform: host-agnostic
#   usage: render-recipe.sh RUNTIME DRYDOCK-BINARY OUTDIR
#          writes OUTDIR/recipe, OUTDIR/recipe-id and OUTDIR/requires; RUNTIME_RELEASES_URL overrides
#          the runtime's releases URL, which otherwise comes from shipyard's product-name.sh.
set -eu
[ $# -eq 3 ] || { echo "usage: render-recipe.sh RUNTIME DRYDOCK-BINARY OUTDIR" >&2; exit 2; }
rt="$1"; bin="$2"; out="$3"
case "$rt" in ""|*[!a-z0-9-]*) echo "invalid runtime name: $rt" >&2; exit 2 ;; esac
here="$(cd "$(dirname "$0")" && pwd)"
[ -f "$bin" ] || { echo "no such drydock binary: $bin" >&2; exit 1; }
[ -d "$out" ] || { echo "no such directory: $out" >&2; exit 1; }
if [ -n "${RUNTIME_RELEASES_URL-}" ]; then
  url="$RUNTIME_RELEASES_URL"
else
  . "$here/../build/msc.sh"
  repo="$(sh "$SHIPYARD_SCRIPTS/product-name.sh" repo "$rt")"
  [ -n "$repo" ] || { echo "no repo for $rt" >&2; exit 1; }
  url="https://github.com/Mavergreen/$repo/releases"
fi
sed "s|@RUNTIME@|$rt|g" "$here/recipe.in" > "$out/recipe"
cat "$out/recipe" "$bin" | shasum -a 256 | cut -d' ' -f1 > "$out/recipe-id"
printf 'avxemu https://github.com/Mavergreen/avxemu/releases\n%s %s\n' "$rt" "$url" > "$out/requires"
