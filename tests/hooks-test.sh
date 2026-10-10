#!/bin/sh
# platform: macOS-only -- the hooks target Mac OS X 10.9's sh and shasum
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
PK="$H_REPO/packaging"
UN="$H_REPO/tree/libexec/mavergreen/pre-uninstall"
MFRG=7f7640eedc1dd6dcc04d6ebb34733622cf982e8121c3e0cc68f86b49606fdb07
V="$H/vol"
LOG="$V/usr/local/mavergreen/var/claude-code/removed-mavericks-forever"
unset MF_RG_SHA256 || true

fresh() {
  rm -rf "$V"
  mkdir -p "$V/usr/local/bin"
}
post() {
  _rc=0
  ROOT="$V" sh "$PK/postinstall-hook.sh" || _rc=$?
  return "$_rc"
}
listed() { sed '/^#/d' "$LOG"; }

fresh
printf '#!/bin/sh\nMF_GEN=3\nexec true\n' > "$V/usr/local/bin/claude"
printf 'rg bytes\n' > "$V/usr/local/bin/rg"
h_assert_ok post
h_assert_fails test -e "$V/usr/local/bin/claude"
h_assert_ok test -f "$V/usr/local/bin/rg"
h_assert_eq "/usr/local/bin/claude" "$(listed)" "only the removed wrapper is recorded"
h_assert_eq "1" "$(grep -c '^# ' "$LOG")" "under one stamp line"

fresh
printf '#!/bin/sh\nexec true\n' > "$V/usr/local/bin/claude"
h_assert_ok post
h_assert_ok test -f "$V/usr/local/bin/claude"
h_assert_fails test -s "$LOG"
h_assert_ok test -d "$V/usr/local/mavergreen/var/claude-code"

fresh
printf '#!/bin/sh\n# MF_GEN=3 in a comment\nexec true\n' > "$V/usr/local/bin/claude"
h_assert_ok post
h_assert_ok test -f "$V/usr/local/bin/claude"

fresh
printf 'x\nMF_GEN=3\n' > "$H/elsewhere"
ln -s "$H/elsewhere" "$V/usr/local/bin/claude"
h_assert_ok post
h_assert_ok test -L "$V/usr/local/bin/claude"
h_assert_ok test -f "$H/elsewhere"

fresh
mkdir "$V/usr/local/bin/claude"
printf 'MF_GEN=3\n' > "$V/usr/local/bin/claude/inner"
h_assert_ok post
h_assert_ok test -f "$V/usr/local/bin/claude/inner"

fresh
printf 'ripgrep fixture\n' > "$V/usr/local/bin/rg"
h_assert_ok post
h_assert_ok test -f "$V/usr/local/bin/rg"
MF_RG_SHA256="$(shasum -a 256 "$V/usr/local/bin/rg" | cut -d' ' -f1)"
export MF_RG_SHA256
h_assert_ok post
h_assert_fails test -e "$V/usr/local/bin/rg"
h_assert_eq "/usr/local/bin/rg" "$(listed)" "the matching rg is recorded"
unset MF_RG_SHA256

fresh
printf 'ripgrep fixture\n' > "$H/rgreal"
ln -s "$H/rgreal" "$V/usr/local/bin/rg"
MF_RG_SHA256="$(shasum -a 256 "$H/rgreal" | cut -d' ' -f1)"
export MF_RG_SHA256
h_assert_ok post
h_assert_ok test -L "$V/usr/local/bin/rg"
unset MF_RG_SHA256

fresh
printf 'not the real rg\n' > "$V/usr/local/bin/rg"
h_assert_ok post
h_assert_ok test -f "$V/usr/local/bin/rg"
h_assert_contains "$(cat "$PK/postinstall-hook.sh")" '_cc_rg="${MF_RG_SHA256:-'"$MFRG"'}"' "the default hash is Wowfunhappy's ripgrep 13.0.0"
fresh
printf 'stand-in for ripgrep 13.0.0\n' > "$V/usr/local/bin/rg"
cat > "$H/bin/shasum" <<SHA
#!/bin/sh
for f in "\$@"; do :; done
if grep -q 'stand-in for ripgrep 13.0.0' "\$f"; then echo "$MFRG  \$f"; else exec /usr/bin/shasum "\$@"; fi
SHA
chmod +x "$H/bin/shasum"
h_assert_ok post
rm -f "$H/bin/shasum"
h_assert_fails test -e "$V/usr/local/bin/rg"
h_assert_eq "/usr/local/bin/rg" "$(listed)" "with no MF_RG_SHA256, the default hash is what is compared"

fresh
printf '#!/bin/sh\nMF_GEN=3\n' > "$V/usr/local/bin/claude"
printf 'ripgrep fixture\n' > "$V/usr/local/bin/rg"
MF_RG_SHA256="$(shasum -a 256 "$V/usr/local/bin/rg" | cut -d' ' -f1)"
export MF_RG_SHA256
h_assert_ok post
h_assert_eq "/usr/local/bin/claude
/usr/local/bin/rg" "$(listed)" "two removals, claude then rg"
cp "$LOG" "$H/log1"
h_assert_ok post
h_assert_ok cmp -s "$LOG" "$H/log1"
printf '#!/bin/sh\nMF_GEN=4\n' > "$V/usr/local/bin/claude"
h_assert_ok post
h_assert_eq "/usr/local/bin/claude" "$(listed)" "a run that removes something rewrites the list with just its own removals"
h_assert_fails cmp -s "$LOG" "$H/log1"
h_assert_fails test -e "$V/usr/local/bin/claude"
cp "$LOG" "$H/log2"
printf '#!/bin/sh\nMF_GEN=4\n' > "$V/usr/local/bin/claude"
h_assert_ok post
h_assert_eq "/usr/local/bin/claude" "$(listed)" "the same removal again"
h_assert_fails cmp -s "$LOG" "$H/log2"
unset MF_RG_SHA256

fresh
mkdir -p "$V/usr/local/mavergreen/var"
: > "$V/usr/local/mavergreen/var/claude-code"
printf '#!/bin/sh\nMF_GEN=3\n' > "$V/usr/local/bin/claude"
_rc=0; out="$(ROOT="$V" sh "$PK/postinstall-hook.sh" 2>&1)" || _rc=$?
h_assert_eq "0" "$_rc" "an uncreatable var dir is not fatal"
h_assert_contains "$out" "could not create" "and it says so"
h_assert_ok test -f "$V/usr/local/bin/claude"

fresh
mkdir -p "$H/outside"
printf '#!/bin/sh\nMF_GEN=3\n' > "$H/outside/claude"
printf 'ripgrep fixture\n' > "$H/outside/rg"
rm -rf "$V/usr/local/bin"
ln -s "$H/outside" "$V/usr/local/bin"
MF_RG_SHA256="$(shasum -a 256 "$H/outside/rg" | cut -d' ' -f1)"
export MF_RG_SHA256
_rc=0; out="$(ROOT="$V" sh "$PK/postinstall-hook.sh" 2>&1)" || _rc=$?
h_assert_eq "0" "$_rc" "a bin dir that leaves the volume is not fatal"
h_assert_contains "$out" "does not resolve inside" "and it says so"
h_assert_ok test -f "$H/outside/claude"
h_assert_ok test -f "$H/outside/rg"
h_assert_fails test -s "$LOG"
unset MF_RG_SHA256

fresh
mkdir -p "$H/outvar" "$V/usr/local/mavergreen"
ln -s "$H/outvar" "$V/usr/local/mavergreen/var"
printf '#!/bin/sh\nMF_GEN=3\n' > "$V/usr/local/bin/claude"
out="$(ROOT="$V" sh "$PK/postinstall-hook.sh" 2>&1)"
h_assert_contains "$out" "symbolic link" "a symlinked var dir is refused with a note"
h_assert_ok test -f "$V/usr/local/bin/claude"
h_assert_eq "0" "$(ls "$H/outvar" | wc -l | tr -d ' ')" "nothing is written through a symlinked var dir"

fresh
printf '#!/bin/sh\nMF_GEN=3\n' > "$V/usr/local/bin/claude"
chmod 555 "$V/usr/local/bin"
_rc=0; ROOT="$V" sh "$PK/postinstall-hook.sh" 2>/dev/null || _rc=$?
chmod 755 "$V/usr/local/bin"
h_assert_eq "0" "$_rc" "a failed rm is not fatal"
h_assert_ok test -f "$V/usr/local/bin/claude"
h_assert_fails test -s "$LOG"

pre() {
  _rc=0
  ROOT="$1" sh "$PK/preinstall-hook.sh" || _rc=$?
  return "$_rc"
}
h_assert_ok pre ""
H_CPU_FEATURES=" FPU VME SSE4.2 "
export H_CPU_FEATURES
_rc=0; out="$(ROOT="" sh "$PK/preinstall-hook.sh" 2>&1)" || _rc=$?
h_assert_eq "1" "$_rc" "no AVX fails"
h_assert_contains "$out" "AVX" "the message names AVX"
h_assert_ok pre "$V"
H_CPU_FEATURES=" FPU XAVX1.0 "
_rc=0; ROOT="" sh "$PK/preinstall-hook.sh" 2>/dev/null || _rc=$?
h_assert_eq "1" "$_rc" "AVX1.0 must be a whole word"
unset H_CPU_FEATURES

if grep -n -E '(^|[;&| 	])exit( |$)|set -e' "$PK/preinstall-hook.sh" "$PK/postinstall-hook.sh"; then
  echo "FAIL: a hook uses exit or set -e" >&2; H_FAILS=$((H_FAILS+1))
fi

h_assert_ok test -f "$UN"
h_assert_fails test -L "$UN"
h_assert_ok test -x "$UN"
h_assert_eq "#!/bin/sh" "$(sed -n 1p "$UN")" "pre-uninstall is a sh script"
_rc=0; out="$("$UN")" || _rc=$?
h_assert_eq "0" "$_rc" "pre-uninstall exits 0"
h_assert_eq "To go back to Mavericks Forever, after this uninstall finishes, rerun https://mavericksforever.com/claude/install.sh" "$(printf '%s\n' "$out" | sed -n 1p)" "pre-uninstall, which runs during the uninstall, says to rerun Mavericks Forever's installer after it, not to uninstall first"
h_assert_contains "$out" "~/Library/Caches/dev.mavergreen.claude-code" "it names the per-user cache"
h_assert_contains "$out" "~/Library/Application Support/dev.mavergreen.claude-code" "and the per-user state"
h_assert_contains "$out" "~/.local/bin/claude" "and the per-user link"
h_assert_contains "$out" "rm -rf ~/Library/Caches/dev.mavergreen.claude-code ~/Library/Application\\ Support/dev.mavergreen.claude-code" "it says how to remove them"
h_assert_contains "$out" '[ "$(readlink ~/.local/bin/claude)" = /usr/local/mavergreen/bin/claude ] && rm -f ~/.local/bin/claude' "including the link, only when it is the launcher's"
