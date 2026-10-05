#!/bin/sh
# platform: macOS-only -- fetches with curl and verifies with shasum, as 10.9 and the CI Macs provide
#   usage: fetch-drydock.sh VERSION OUTDIR
#          DRYDOCK_RELEASES overrides the base URL that holds VERSION/drydock-macho-rewrite and VERSION/SHA256SUMS.
set -eu
[ $# -eq 2 ] || { echo "usage: fetch-drydock.sh VERSION OUTDIR" >&2; exit 2; }
ver="$1"; out="$2"
asset=drydock-macho-rewrite
base="${DRYDOCK_RELEASES:-https://github.com/Mavergreen/drydock/releases/download}/v$ver"
[ -d "$out" ] || { echo "no such directory: $out" >&2; exit 1; }
tmp="$(mktemp -d "$out/.fetch.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$base/SHA256SUMS" -o "$tmp/SHA256SUMS" || { echo "could not fetch $base/SHA256SUMS" >&2; exit 1; }
curl -fsSL "$base/$asset" -o "$tmp/$asset" || { echo "could not fetch $base/$asset" >&2; exit 1; }
want="$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1; exit }' "$tmp/SHA256SUMS")"
[ -n "$want" ] || { echo "$asset is not listed in $base/SHA256SUMS" >&2; exit 1; }
got="$(shasum -a 256 "$tmp/$asset" | cut -d' ' -f1)"
[ "$got" = "$want" ] || { echo "$asset does not match $base/SHA256SUMS (wanted $want, got $got)" >&2; exit 1; }
chmod +x "$tmp/$asset"
mv -f "$tmp/$asset" "$out/$asset"
