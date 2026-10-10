#!/bin/sh
# platform: macOS-only -- shasum is 10.9's SHA-256 tool
_cc_var="$ROOT/usr/local/mavergreen/var/claude-code"
_cc_log="$_cc_var/removed-mavericks-forever"
_cc_rg="${MF_RG_SHA256:-7f7640eedc1dd6dcc04d6ebb34733622cf982e8121c3e0cc68f86b49606fdb07}"
_cc_first=1
_cc_record() {
  if [ "$_cc_first" -eq 1 ]; then
    printf '# %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" > "$_cc_log"
    _cc_first=0
  fi
  printf '%s\n' "$1" >> "$_cc_log"
}
_cc_inside() {
  _cc_top="$(CDPATH= cd -P "$ROOT/" 2>/dev/null && pwd -P)" || return 1
  _cc_dir="$(CDPATH= cd -P "$1" 2>/dev/null && pwd -P)" || return 1
  case "${_cc_dir%/}/" in "${_cc_top%/}/"*) return 0 ;; *) return 1 ;; esac
}
_cc_existing() {
  _cc_e="$1"
  while [ -n "$_cc_e" ] && [ ! -d "$_cc_e" ]; do _cc_e="${_cc_e%/*}"; done
  printf '%s\n' "${_cc_e:-/}"
}
if [ -L "$ROOT/usr/local/mavergreen/var" ] || [ -L "$_cc_var" ] || [ -L "$_cc_log" ]; then
  echo "claude-code: $_cc_var is or passes through a symbolic link; leaving Mavericks Forever's files in place" >&2
elif ! _cc_inside "$ROOT/usr/local/bin"; then
  echo "claude-code: $ROOT/usr/local/bin does not resolve inside $ROOT/; leaving Mavericks Forever's files in place" >&2
elif ! _cc_inside "$(_cc_existing "$_cc_var")"; then
  echo "claude-code: $_cc_var does not resolve inside $ROOT/; leaving Mavericks Forever's files in place" >&2
elif mkdir -p "$_cc_var" && _cc_inside "$_cc_var"; then
  (
    if CDPATH= cd -P "$ROOT/usr/local/bin"; then
      if [ -f ./claude ] && [ ! -L ./claude ] && grep -q '^MF_GEN=' ./claude; then
        rm -f ./claude && _cc_record /usr/local/bin/claude
      fi
      if [ -f ./rg ] && [ ! -L ./rg ] && [ "$(shasum -a 256 ./rg | cut -d' ' -f1)" = "$_cc_rg" ]; then
        rm -f ./rg && _cc_record /usr/local/bin/rg
      fi
    fi
  )
else
  echo "claude-code: could not create $_cc_var; leaving Mavericks Forever's files in place" >&2
fi
true
