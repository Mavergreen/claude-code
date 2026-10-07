#!/bin/sh
# platform: macOS-only -- expands the package with pkgutil
#   usage: extract-component.sh PKG IDENTIFIER DESTDIR
#          Expands PKG (flat or product archive), selects the component whose PackageInfo declares
#          identifier IDENTIFIER, and unpacks its gzip+cpio Payload into the existing directory DESTDIR.
#          Exits 1, naming IDENTIFIER, when PKG has no such component or the component has no payload.
set -eu
[ $# -eq 3 ] || { echo "usage: extract-component.sh PKG IDENTIFIER DESTDIR" >&2; exit 2; }
pkg="$1"; id="$2"; dest="$3"
[ -f "$pkg" ] || { echo "extract-component: no such package: $pkg" >&2; exit 1; }
[ -d "$dest" ] || { echo "extract-component: no such directory: $dest" >&2; exit 1; }
work="$(mktemp -d "${TMPDIR:-/tmp}/extract-component.XXXXXX")"
trap 'rm -rf "$work"' EXIT
pkgutil --expand "$pkg" "$work/x" || { echo "extract-component: cannot expand $pkg" >&2; exit 1; }
find "$work/x" -name PackageInfo > "$work/infos"
comp=""
while IFS= read -r info; do
  if grep -qF "identifier=\"$id\"" "$info"; then comp="$(dirname "$info")"; break; fi
done < "$work/infos"
[ -n "$comp" ] || { echo "extract-component: $pkg has no component $id" >&2; exit 1; }
[ -f "$comp/Payload" ] || { echo "extract-component: component $id has no payload" >&2; exit 1; }
(cd "$dest" && gzip -dc < "$comp/Payload" | cpio -idm 2>/dev/null)
