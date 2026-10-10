#!/bin/sh
# platform: macOS-only -- the launcher fetches with 10.9's curl and shasum

cc_get() { curl -fsSL --connect-timeout 20 --max-time 60 "$@"; }

cc_latest() {
  _cc_l="$(cc_get "$CC_CDN/latest" 2>&1)" || cc_die "could not reach $CC_CDN: $_cc_l"
  _cc_l="$(printf '%s' "$_cc_l" | tr -d '[:space:]')"
  cc_is_version "$_cc_l" || cc_die "unexpected answer from $CC_CDN/latest"
  printf '%s\n' "$_cc_l"
}

cc_manifest_sum() {
  _cc_msum=""
  _cc_m="$(cc_get "$CC_CDN/$1/manifest.json" 2>&1)" || { _cc_merr="$_cc_m"; return 1; }
  _cc_msum="$(printf '%s' "$_cc_m" | tr -d '\n\r\t' \
    | grep -Eo "\"darwin-x64\"[^}]*\"checksum\"[[:space:]]*:[[:space:]]*\"[a-f0-9]{64}\"" \
    | grep -Eo '[a-f0-9]{64}')" || :
  [ -n "$_cc_msum" ] || { _cc_merr="its manifest lists no darwin-x64 checksum"; return 1; }
}

cc_remember_verified() {
  { mkdir -p "$CC_STATE/verified" && printf '%s\n' "$2" > "$CC_STATE/verified/$1"; } 2>/dev/null || :
}

cc_fetch_abort() {
  rm -f "$_cc_dlt"
  trap - INT TERM HUP
  kill -s "$1" "$(exec sh -c 'echo "$PPID"')"
  exit 1
}

cc_fetch() {
  _cc_fv="$1"
  cc_manifest_sum "$_cc_fv" || cc_die "could not read the checksum for Claude Code $_cc_fv from $CC_CDN: $_cc_merr"
  _cc_want="$_cc_msum"
  mkdir -p "$CC_VERSIONS" || cc_die "could not create $CC_VERSIONS"
  find "$CC_VERSIONS" -maxdepth 1 -type f -name '*.mavergreen-dl.*' -mmin +60 -exec rm -f {} + 2>/dev/null || :
  _cc_dlt="$CC_VERSIONS/$_cc_fv.mavergreen-dl.$$"
  cc_note "downloading Claude Code $_cc_fv..."
  trap 'cc_fetch_abort INT' INT
  trap 'cc_fetch_abort TERM' TERM
  trap 'cc_fetch_abort HUP' HUP
  _cc_dl=0
  _cc_dle="$(curl -fsSL --connect-timeout 20 --speed-limit 1024 --speed-time 60 -o "$_cc_dlt" "$CC_CDN/$_cc_fv/darwin-x64/claude" 2>&1)" || _cc_dl=1
  trap - INT TERM HUP
  if [ "$_cc_dl" -ne 0 ]; then
    rm -f "$_cc_dlt"
    cc_die "could not download Claude Code $_cc_fv from $CC_CDN: $_cc_dle"
  fi
  _cc_got="$(cc_sha256 "$_cc_dlt")"
  if [ "$_cc_got" != "$_cc_want" ]; then
    rm -f "$_cc_dlt"
    cc_die "Claude Code $_cc_fv failed its checksum (expected $_cc_want, got $_cc_got)"
  fi
  if ! { chmod +x "$_cc_dlt" && mv -f "$_cc_dlt" "$CC_VERSIONS/$_cc_fv"; }; then
    rm -f "$_cc_dlt"
    cc_die "could not install Claude Code $_cc_fv into $CC_VERSIONS"
  fi
  cc_remember_verified "$_cc_fv" "$_cc_want"
}

cc_verified() {
  _cc_vrec="$CC_STATE/verified/$1"
  if cc_manifest_sum "$1"; then
    _cc_want="$_cc_msum"
    if [ -f "$CC_VERSIONS/$1" ] && [ "$(cc_sha256 "$CC_VERSIONS/$1")" = "$_cc_want" ]; then
      cc_remember_verified "$1" "$_cc_want"
      return 0
    fi
    rm -f "$_cc_vrec"
    return 1
  fi
  _cc_want=""
  if [ -f "$_cc_vrec" ]; then IFS= read -r _cc_want < "$_cc_vrec" || :; fi
  case "$_cc_want" in
    *[!0-9a-f]*|'') return 2 ;;
  esac
  [ -f "$CC_VERSIONS/$1" ] || return 1
  [ "$(cc_sha256 "$CC_VERSIONS/$1")" = "$_cc_want" ]
}
