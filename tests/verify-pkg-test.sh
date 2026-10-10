#!/bin/sh
# platform: macOS-only -- builds a package with pkgbuild and expands it with pkgutil
set -eu
. "$(dirname "$0")/lib/harness.sh"
command -v pkgbuild >/dev/null 2>&1 && command -v pkgutil >/dev/null 2>&1 || exit 77
h_setup
VP="$H_REPO/packaging/verify-pkg.sh"
mk() {
  r="$H/$1"
  t="$r/usr/local/mavergreen/claude-code"
  mkdir -p "$t/bin" "$t/libexec/mavergreen" "$t/libexec/claude-code/shell-bin" "$t/share/claude-code/computer-use" "$r/Library/Application Support/Mavergreen/claude-code-updater.app"
  printf '#!/bin/sh\n' > "$t/bin/claude"; chmod +x "$t/bin/claude"
  printf 'drydock\n' > "$t/libexec/drydock-macho-rewrite"
  printf '#!/bin/sh\n' > "$t/libexec/mavergreen/pre-uninstall"
  printf 'recipe\n' > "$t/share/claude-code/recipe"
  cat "$t/share/claude-code/recipe" "$t/libexec/drydock-macho-rewrite" | shasum -a 256 | cut -d' ' -f1 > "$t/share/claude-code/recipe-id"
  : > "$t/share/claude-code/requires"; : > "$t/share/claude-code/settings.json"; : > "$t/share/claude-code/mcp-config.json"
  printf '#!/usr/bin/python\n' > "$t/share/claude-code/computer-use/mcp_server.py"; chmod +x "$t/share/claude-code/computer-use/mcp_server.py"
  : > "$t/share/claude-code/claude-env.sh"
  for _f in mktemp timeout env setsid base64 cat head paste readlink realpath tac xargs; do printf '#!/bin/sh\n' > "$t/libexec/claude-code/shell-bin/$_f"; chmod +x "$t/libexec/claude-code/shell-bin/$_f"; done
  printf '#!/bin/sh\n' > "$t/libexec/claude-code/prepare"; chmod +x "$t/libexec/claude-code/prepare"
  : > "$t/libexec/claude-code/canonical.pl"
  : > "$r/Library/Application Support/Mavergreen/claude-code-updater.app/Info.plist"
}
comp() { pkgbuild --root "$H/$1" --identifier "$2" --version 1 --install-location / "$H/$3" >/dev/null 2>&1; }
build() { comp "$1" dev.mavergreen.claude-code "$1.pkg"; }
printf 'drydock\n' > "$H/dd"
mk good; build good
h_assert_ok sh "$VP" "$H/good.pkg" "$H/dd"
mk bad; rm "$H/bad/usr/local/mavergreen/claude-code/bin/claude"; build bad
rc=0; out="$(sh "$VP" "$H/bad.pkg" "$H/dd" 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "a payload without bin/claude fails"
h_assert_contains "$out" "bin/claude" "the failure names the missing file"
mk noenvfile; rm "$H/noenvfile/usr/local/mavergreen/claude-code/share/claude-code/claude-env.sh"; build noenvfile
rc=0; out="$(sh "$VP" "$H/noenvfile.pkg" "$H/dd" 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "a payload without claude-env.sh fails"
h_assert_contains "$out" "share/claude-code/claude-env.sh" "the failure names the env file"
for f in mktemp timeout env setsid base64 cat head paste readlink realpath tac xargs; do
  mk "no$f"; rm "$H/no$f/usr/local/mavergreen/claude-code/libexec/claude-code/shell-bin/$f"; build "no$f"
  rc=0; out="$(sh "$VP" "$H/no$f.pkg" "$H/dd" 2>&1)" || rc=$?
  h_assert_eq "1" "$rc" "a payload without shell-bin/$f fails"
  h_assert_contains "$out" "libexec/claude-code/shell-bin/$f" "the failure names shell-bin/$f"
done
mk nocanonical; rm "$H/nocanonical/usr/local/mavergreen/claude-code/libexec/claude-code/canonical.pl"; build nocanonical
rc=0; out="$(sh "$VP" "$H/nocanonical.pkg" "$H/dd" 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "a payload without libexec/claude-code/canonical.pl fails"
h_assert_contains "$out" "libexec/claude-code/canonical.pl" "the failure names canonical.pl"
mk noprepare; rm "$H/noprepare/usr/local/mavergreen/claude-code/libexec/claude-code/prepare"; build noprepare
rc=0; out="$(sh "$VP" "$H/noprepare.pkg" "$H/dd" 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "a payload without libexec/claude-code/prepare fails"
h_assert_contains "$out" "libexec/claude-code/prepare" "the failure names prepare"
mk noxprepare; chmod -x "$H/noxprepare/usr/local/mavergreen/claude-code/libexec/claude-code/prepare"; build noxprepare
rc=0; out="$(sh "$VP" "$H/noxprepare.pkg" "$H/dd" 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "a payload whose prepare is not executable fails"
h_assert_contains "$out" "prepare is not executable" "the failure says prepare is not executable"
mk noxenv; chmod -x "$H/noxenv/usr/local/mavergreen/claude-code/libexec/claude-code/shell-bin/env"; build noxenv
rc=0; out="$(sh "$VP" "$H/noxenv.pkg" "$H/dd" 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "a payload whose shell-bin/env is not executable fails"
h_assert_contains "$out" "shell-bin/env is not executable" "the failure says so"
printf 'other\n' > "$H/dd2"
rc=0; out="$(sh "$VP" "$H/good.pkg" "$H/dd2" 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "a different drydock fails"
h_assert_contains "$out" "drydock-macho-rewrite" "the failure names the drydock"
mkdir -p "$H/base/usr/local/mavergreen/base"; : > "$H/base/usr/local/mavergreen/base/file"
comp base dev.mavergreen.base base.pkg
comp good dev.mavergreen.claude-code cc.pkg
productbuild --package "$H/base.pkg" --package "$H/cc.pkg" "$H/prod.pkg" >/dev/null 2>&1
h_assert_ok sh "$VP" "$H/prod.pkg" "$H/dd"
comp good dev.mavergreen.other other.pkg
productbuild --package "$H/base.pkg" --package "$H/other.pkg" "$H/noprod.pkg" >/dev/null 2>&1
rc=0; out="$(sh "$VP" "$H/noprod.pkg" "$H/dd" 2>&1)" || rc=$?
h_assert_eq "1" "$rc" "a product archive without the claude-code component fails"
h_assert_contains "$out" "dev.mavergreen.claude-code" "the failure names the identifier"
