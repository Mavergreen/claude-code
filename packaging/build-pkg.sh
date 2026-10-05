#!/bin/sh
# platform: macOS-only -- drives shipyard's stage_product.sh, build_component_pkg.sh and set_install_floor.sh
#   usage: build-pkg.sh BUILD-DIR VERSION OUT.pkg
#          Stages tree/, the pinned drydock, the rendered recipe, the docs and the updater under
#          /usr/local/mavergreen/claude-code, and wraps them in a 10.9.5-floored product archive.
#          The runtime product's short name is the first line of RUNTIME_PRODUCT.
set -eu
B=${1:?usage: build-pkg.sh BUILD-DIR VERSION OUT.pkg}
V=${2:?usage: build-pkg.sh BUILD-DIR VERSION OUT.pkg}
OUT=${3:?usage: build-pkg.sh BUILD-DIR VERSION OUT.pkg}
REPO=$(cd "$(dirname "$0")/.." && pwd)
. "$REPO/build/msc.sh"
SHIPYARD=$SHIPYARD_SCRIPTS
[ -f "$REPO/RUNTIME_PRODUCT" ] || { echo "build-pkg: no $REPO/RUNTIME_PRODUCT; it names the runtime product's short name" >&2; exit 1; }
RT=$(sed -n 1p "$REPO/RUNTIME_PRODUCT")
[ -n "$RT" ] || { echo "build-pkg: $REPO/RUNTIME_PRODUCT is empty" >&2; exit 1; }
[ -d "$B/claude-code-updater.app" ] || { echo "build-pkg: no updater; configure with -DCLAUDE_CODE_BUILD_UPDATER=ON" >&2; exit 1; }
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-code-pkg.XXXXXX")
trap 'rm -rf "$work"' EXIT
ROOT=$work/root
T=$ROOT/usr/local/mavergreen/claude-code
install -d "$T" "$T/libexec" "$T/share/claude-code" "$T/share/doc/claude-code"
if command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$REPO" archive HEAD tree | tar -x -C "$work"
  cp -Rp "$work/tree/." "$T/"
  rm -rf "$work/tree"
else
  echo "build-pkg: no git here; staging tree/ as it is on disk, tracked or not" >&2
  cp -Rp "$REPO/tree/." "$T/"
fi
sh "$REPO/packaging/fetch-drydock.sh" "$(cat "$REPO/components/drydock/version")" "$T/libexec"
sh "$REPO/packaging/render-recipe.sh" "$RT" "$T/libexec/drydock-macho-rewrite" "$T/share/claude-code"
cp "$REPO/LICENSE" "$REPO/README.md" "$T/share/doc/claude-code/"
find "$ROOT" -name '._*' -delete
sh "$SHIPYARD/stage_product.sh" --stage "$ROOT" --product claude-code --name "Mavericks Claude Code" \
  --version "$V" --requires avxemu --requires "$RT" \
  --preinstall-hook "$REPO/packaging/preinstall-hook.sh" --postinstall-hook "$REPO/packaging/postinstall-hook.sh" \
  --scripts-out "$work/scripts" --updater-app "$B/claude-code-updater.app"
sh "$SHIPYARD/build_component_pkg.sh" --root "$ROOT" --identifier dev.mavergreen.claude-code \
  --version "$V" --install-location / --scripts "$work/scripts" --out "$work/claude-code-component.pkg" >&2
mkdir -p "$(dirname "$OUT")"
sh "$SHIPYARD/set_install_floor.sh" --identifier dev.mavergreen.claude-code --title "Claude Code for Mavericks" \
  --component "$work/claude-code-component.pkg" --out "$OUT" --require-scripts --host-arch x86_64 >&2
echo "built $OUT"
