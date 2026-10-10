#!/bin/sh
# platform: macOS-only -- the launcher chooses among versions Anthropic's updater installs on 10.9

cc_predates_launcher() { cc_ver_gt 2.1.207 "$1"; }

cc_refuse_predating() {
  [ "${1-}" = install ] && cc_is_version "${2-}" && cc_predates_launcher "$2" || return 0
  cc_die "Claude Code $2 predates 2.1.207, the first version that runs under this launcher; not installing it"
}

cc_record_intent() {
  case "${1-}" in
    update) mkdir -p "$CC_STATE" && printf 'update\n' > "$CC_STATE/repick" ;;
    install) mkdir -p "$CC_STATE" && printf 'install%s\n' "${2:+ $2}" > "$CC_STATE/repick" ;;
  esac
  return 0
}

cc_setting() {
  _cc_sf="$1"
  shift
  for _cc_sk in "$@"; do :; done
  [ -f "$_cc_sf" ] && [ -r "$_cc_sf" ] || return 0
  grep -q "\"$_cc_sk\"" "$_cc_sf" 2>/dev/null || return 0
  _cc_py="${CC_PYTHON:-/usr/bin/python}"
  if [ -f "$_cc_py" ] && [ -x "$_cc_py" ]; then
    "$_cc_py" -c '
import json, sys
try:
    v = json.load(open(sys.argv[1]))
    for k in sys.argv[2:]:
        v = v[k]
    if isinstance(v, bool):
        v = v and "true" or "false"
    sys.stdout.write(str(v))
except Exception:
    pass
' "$_cc_sf" "$@" 2>/dev/null || :
  else
    tr -d '\n\r' < "$_cc_sf" \
      | grep -Eo "\"$_cc_sk\"[[:space:]]*:[[:space:]]*(\"[^\"]*\"|[A-Za-z0-9.]+)" | head -n 1 \
      | sed -E 's/^"[^"]*"[[:space:]]*:[[:space:]]*//; s/^"//; s/"$//'
  fi
  return 0
}

cc_user_settings() { printf '%s/settings.json\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }

cc_held() {
  cc_truthy "${DISABLE_AUTOUPDATER-}" && return 0
  cc_truthy "$(cc_setting "$(cc_user_settings)" env DISABLE_AUTOUPDATER)" && return 0
  cc_truthy "$(cc_setting "${CC_MANAGED_SETTINGS:-/Library/Application Support/ClaudeCode/managed-settings.json}" env DISABLE_AUTOUPDATER)"
}

cc_installed() {
  for _cc_f in "$CC_VERSIONS"/*; do
    [ -f "$_cc_f" ] && [ -x "$_cc_f" ] || continue
    _cc_n="${_cc_f##*/}"
    cc_is_version "$_cc_n" && printf '%s\n' "$_cc_n"
  done
  return 0
}

cc_newest() {
  _cc_best=""
  for _cc_c in $(cc_installed); do
    cc_predates_launcher "$_cc_c" && continue
    if [ -z "$_cc_best" ] || cc_ver_gt "$_cc_c" "$_cc_best"; then _cc_best="$_cc_c"; fi
  done
  [ -z "$_cc_best" ] || printf '%s\n' "$_cc_best"
}

cc_last_downloaded() {
  _cc_best=""
  for _cc_c in $(cc_installed); do
    cc_predates_launcher "$_cc_c" && continue
    if [ -z "$_cc_best" ] || [ "$CC_VERSIONS/$_cc_c" -nt "$CC_VERSIONS/$_cc_best" ] \
      || { [ ! "$CC_VERSIONS/$_cc_best" -nt "$CC_VERSIONS/$_cc_c" ] && cc_ver_gt "$_cc_c" "$_cc_best"; }; then
      _cc_best="$_cc_c"
    fi
  done
  [ -z "$_cc_best" ] || printf '%s\n' "$_cc_best"
}

cc_usual() {
  case "$(cc_setting "$(cc_user_settings)" autoUpdatesChannel)" in
    ''|latest) cc_newest ;;
    *) cc_last_downloaded ;;
  esac
}

cc_is_installed() {
  cc_is_version "$1" && [ -f "$CC_VERSIONS/$1" ] && [ -x "$CC_VERSIONS/$1" ]
}

cc_choose() {
  mkdir -p "$CC_STATE" || cc_die "could not create $CC_STATE"
  _cc_pick=""
  if [ -f "$CC_STATE/repick" ]; then
    _cc_mk="$(cat "$CC_STATE/repick")"
    case "$_cc_mk" in
      "install "*)
        _cc_arg="$(printf '%s' "${_cc_mk#install }" | tr -d '[:space:]')"
        case "$_cc_arg" in
          latest|stable|rc)
            _cc_rv="$(cc_get "$CC_CDN/$_cc_arg" 2>/dev/null)" || _cc_rv=""
            _cc_rv="$(printf '%s' "$_cc_rv" | tr -d '[:space:]')"
            if ! cc_is_version "$_cc_rv"; then
              cc_note "could not resolve the $_cc_arg channel from $CC_CDN; using the newest installed version"
            elif cc_is_installed "$_cc_rv" || (cc_fetch "$_cc_rv"); then
              _cc_pick="$_cc_rv"
            else
              cc_note "could not fetch Claude Code $_cc_rv for the $_cc_arg channel; using the newest installed version"
            fi ;;
          *) if cc_is_installed "$_cc_arg" && ! cc_predates_launcher "$_cc_arg"; then _cc_pick="$_cc_arg"; fi ;;
        esac ;;
    esac
    if [ -n "$_cc_pick" ]; then touch "$CC_VERSIONS/$_cc_pick" 2>/dev/null || :; else _cc_pick="$(cc_usual)"; fi
  fi
  if [ -z "$_cc_pick" ] && [ -f "$CC_STATE/current" ] && cc_held; then
    _cc_cur="$(tr -d '[:space:]' < "$CC_STATE/current")"
    if cc_is_installed "$_cc_cur" && ! cc_predates_launcher "$_cc_cur"; then _cc_pick="$_cc_cur"; fi
  fi
  [ -n "$_cc_pick" ] || _cc_pick="$(cc_usual)"
  if [ -z "$_cc_pick" ]; then
    _cc_pick="$(cc_latest)" || exit 1
    cc_fetch "$_cc_pick"
  fi
  rm -f "$CC_STATE/repick"
  printf '%s\n' "$_cc_pick" > "$CC_STATE/current"
  printf '%s\n' "$_cc_pick"
}
