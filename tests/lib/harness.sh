#!/bin/sh
# platform: macOS-only -- the tests drive the launcher, which targets Mac OS X 10.9's sh and tools
#   usage: . "$(dirname "$0")/lib/harness.sh"; h_setup; ... h_assert_* ...  h_setup installs the EXIT trap; h_teardown removes $H and fails the test if any assert failed.
#          asserts must not run inside $(...) or a pipeline: their failure count would be lost.

H_FAILS=0
H_REPO="$(cd "$(dirname "$0")/.." && pwd)"
H_ORIG_HOME="${HOME-}"
H_ORIG_PATH="$PATH"

h_setup() {
  trap h_teardown EXIT
  unset XDG_DATA_HOME CLAUDE_CODE_CDN CLAUDE_CONFIG_DIR DISABLE_AUTOUPDATER CC_SBIN CC_PYTHON CC_LSOF
  H="$(mktemp -d "${TMPDIR:-/tmp}/cc test.XXXXXX")"
  H="$(cd "$H" && pwd -P)"
  export H
  _h_mg="$H/root/usr/local/mavergreen"
  mkdir -p "$_h_mg" "$H/home" "$H/bin" "$H/cdn"
  cp -R "$H_REPO/tree" "$_h_mg/claude-code"
  _h_sh="$_h_mg/claude-code/share/claude-code"
  mkdir -p "$_h_sh"
  printf '# fake recipe\n' > "$_h_sh/recipe"
  shasum -a 256 "$_h_sh/recipe" | cut -d' ' -f1 > "$_h_sh/recipe-id"
  printf 'avxemu https://example.invalid/avxemu/releases\nfakert https://example.invalid/fakert/releases\n' > "$_h_sh/requires"
  mkdir -p "$_h_mg/avxemu/lib" "$_h_mg/fakert"
  : > "$_h_mg/avxemu/mavergreen.plist"
  : > "$_h_mg/avxemu/lib/libavxemu.dylib"
  : > "$_h_mg/fakert/mavergreen.plist"
  cat > "$H/bin/sysctl" <<'SYS'
#!/bin/sh
case "$*" in
  "-n machdep.cpu.features") printf '%s\n' "${H_CPU_FEATURES- FPU VME AVX1.0 SSE4.2 }" ;;
  "-n machdep.cpu.leaf7_features") printf '%s\n' "${H_LEAF7- SMEP AVX2 BMI2 }" ;;
  *) exit 1 ;;
esac
SYS
  chmod +x "$H/bin/sysctl"
  HOME="$H/home"
  PATH="$H/bin:$PATH"
  CLAUDE_CODE_CDN="file://$(printf %s "$H/cdn" | sed "s/%/%25/g; s/ /%20/g; s/#/%23/g; s/?/%3F/g")"
  CC_MANAGED_SETTINGS="$H/managed-settings.json"
  export HOME PATH CLAUDE_CODE_CDN CC_MANAGED_SETTINGS
}

h_teardown() {
  [ -n "${H-}" ] && rm -rf "$H"
  HOME="$H_ORIG_HOME"
  PATH="$H_ORIG_PATH"
  export HOME PATH
  [ "${H_FAILS:-0}" -eq 0 ] || exit 1
}

h_cdn_publish() {
  _h_v="$1"
  _h_dir="$H/cdn/$_h_v/darwin-x64"
  mkdir -p "$_h_dir"
  {
    printf '#!/bin/sh\n'
    printf 'echo "fake-claude %s"\n' "$_h_v"
    cat <<'BODY'
for a in "$@"; do echo "arg:$a"; done
echo "env:JSC_numberOfGCMarkers=${JSC_numberOfGCMarkers-}"
echo "env:DISABLE_INSTALLATION_CHECKS=${DISABLE_INSTALLATION_CHECKS-}"
echo "env:USE_BUILTIN_RIPGREP=${USE_BUILTIN_RIPGREP-}"
echo "env:CLAUDE_ENV_FILE=${CLAUDE_ENV_FILE-}"
echo "env:PATH=${PATH-}"
BODY
    [ -z "${2-}" ] || printf '# %s\n' "$2"
  } > "$_h_dir/claude"
  chmod +x "$_h_dir/claude"
  _h_sum="$(shasum -a 256 "$_h_dir/claude" | cut -d' ' -f1)"
  _h_size="$(wc -c < "$_h_dir/claude" | tr -d ' ')"
  printf '{\n  "version": "%s",\n  "platforms": {\n    "darwin-arm64": {\n      "checksum": "%s",\n      "size": %s\n    },\n    "darwin-x64": {\n      "checksum": "%s",\n      "size": %s\n    }\n  }\n}\n' "$_h_v" "$(printf "arm64-%s" "$_h_v" | shasum -a 256 | cut -d" " -f1)" "$_h_size" "$_h_sum" "$_h_size" > "$H/cdn/$_h_v/manifest.json"
}

h_cdn_latest() { printf '%s\n' "$1" > "$H/cdn/latest"; }

h_fake_curl() {
  cat > "$H/bin/curl" <<'CURL'
#!/bin/sh
printf '%s\n' "$*" >> "$H/curl.log"
if [ -f "$H/curl-hang" ]; then
  o=""; prev=""
  for a in "$@"; do [ "$prev" != "-o" ] || o="$a"; prev="$a"; done
  if [ -n "$o" ]; then
    printf 'partial' > "$o"
    echo "$$" > "$H/curl.pid"
    exec sleep 30
  fi
fi
exec /usr/bin/curl "$@"
CURL
  chmod +x "$H/bin/curl"
  hash -r
}

h_fake_drydock() {
  _h_bin="$H/root/usr/local/mavergreen/claude-code/libexec"
  mkdir -p "$_h_bin"
  cat > "$_h_bin/drydock-macho-rewrite" <<'DD'
#!/bin/sh
in="$1"; out="$2"
echo "$in" >> "$H/drydock.log"
echo "$out" >> "$H/drydock-out.log"
echo "fake drydock: progress on stdout"
echo "fake drydock: detail on stderr" >&2
if [ -f "$H/drydock-barrier" ]; then
  n=0
  while [ "$(wc -l < "$H/drydock.log" | tr -d ' ')" -lt 2 ] && [ "$n" -lt 10 ]; do sleep 1; n=$((n+1)); done
fi
if [ -f "$H/drydock-refuses" ] && grep -qx "$(basename "$in")" "$H/drydock-refuses"; then
  exit 3
fi
recipe="$(mktemp "${TMPDIR:-/tmp}/recipe.XXXXXX")"
cat > "$recipe"
cp "$in" "$out"
printf '# patched-by-fake %s\n' "$(shasum -a 256 "$recipe" | cut -d' ' -f1)" >> "$out"
rm -f "$recipe"
DD
  chmod +x "$_h_bin/drydock-macho-rewrite"
}

h_assert_eq() {
  if [ "$1" != "$2" ]; then
    echo "FAIL: $3" >&2
    echo "  expected: $1" >&2
    echo "  actual:   $2" >&2
    H_FAILS=$((H_FAILS+1))
  fi
}

h_assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) echo "FAIL: $3" >&2; echo "  missing: $2" >&2; echo "  in: $1" >&2; H_FAILS=$((H_FAILS+1)) ;;
  esac
}

h_assert_ok() {
  "$@" || { echo "FAIL: expected success: $*" >&2; H_FAILS=$((H_FAILS+1)); }
}

h_assert_fails() {
  if "$@"; then echo "FAIL: expected failure: $*" >&2; H_FAILS=$((H_FAILS+1)); fi
}
