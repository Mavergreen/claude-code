#!/bin/sh
# platform: macOS-only -- expands the package with pkgutil
#   usage: verify-pkg.sh PKG STAGED-DRYDOCK
#          Fails, naming the first problem, unless PKG's payload holds the launcher, its share files,
#          the shell guards, the pre-uninstall hook, the updater app and a drydock byte-equal to
#          STAGED-DRYDOCK, and its recipe-id is sha256 of the recipe followed by that drydock.
set -eu
[ $# -eq 2 ] || { echo "usage: verify-pkg.sh PKG STAGED-DRYDOCK" >&2; exit 2; }
pkg="$1"; dd="$2"
[ -f "$pkg" ] || { echo "verify-pkg: no such package: $pkg" >&2; exit 1; }
[ -f "$dd" ] || { echo "verify-pkg: no such drydock: $dd" >&2; exit 1; }
work="$(mktemp -d "${TMPDIR:-/tmp}/verify-pkg.XXXXXX")"
trap 'rm -rf "$work"' EXIT
id=dev.mavergreen.claude-code
root="$work/root"
mkdir "$root"
sh "$(dirname "$0")/extract-component.sh" "$pkg" "$id" "$root"
t="$root/usr/local/mavergreen/claude-code"
need() { [ -e "$1" ] || { echo "verify-pkg: payload lacks ${1#"$root"/}" >&2; exit 1; }; }
needx() { need "$1"; [ -x "$1" ] || { echo "verify-pkg: ${1#"$root"/} is not executable" >&2; exit 1; }; }
needx "$t/bin/claude"
for f in recipe recipe-id requires settings.json mcp-config.json claude-env.sh; do need "$t/share/claude-code/$f"; done
for f in mktemp timeout env setsid base64 paste; do needx "$t/libexec/claude-code/shell-bin/$f"; done
needx "$t/libexec/claude-code/prepare"
needx "$t/share/claude-code/computer-use/mcp_server.py"
need "$t/libexec/drydock-macho-rewrite"
need "$t/libexec/mavergreen/pre-uninstall"
need "$root/Library/Application Support/Mavergreen/claude-code-updater.app"
cmp -s "$t/libexec/drydock-macho-rewrite" "$dd" \
  || { echo "verify-pkg: libexec/drydock-macho-rewrite differs from $dd" >&2; exit 1; }
want="$(cat "$t/share/claude-code/recipe" "$dd" | shasum -a 256 | cut -d' ' -f1)"
got="$(cat "$t/share/claude-code/recipe-id")"
[ "$want" = "$got" ] || { echo "verify-pkg: recipe-id is $got, not sha256 of recipe and drydock ($want)" >&2; exit 1; }
