#!/bin/sh
# platform: macOS-only -- the launcher exists to run Claude Code on Mac OS X 10.9

cc_die() { echo "claude: $*" >&2; exit 1; }
cc_note() { echo "claude: $*" >&2; }

cc_resolve() {
  _cc_rp="$1"
  _cc_hops=0
  while [ -L "$_cc_rp" ]; do
    _cc_hops=$((_cc_hops+1))
    [ "$_cc_hops" -le 40 ] || cc_die "too many symlinks: $1"
    _cc_rt="$(readlink "$_cc_rp")"
    case "$_cc_rt" in
      /*) _cc_rp="$_cc_rt" ;;
      *) _cc_rp="$(dirname "$_cc_rp")/$_cc_rt" ;;
    esac
  done
  _cc_rd="$(CDPATH= cd -P "$(dirname "$_cc_rp")" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s\n' "$_cc_rd" "$(basename "$_cc_rp")"
}

cc_data_home() {
  case "${XDG_DATA_HOME-}" in
    /*) printf '%s\n' "$XDG_DATA_HOME" ;;
    *) printf '%s\n' "$HOME/.local/share" ;;
  esac
}

cc_init() {
  case "${HOME-}" in /*[!/.]*) ;; *) cc_die "HOME must be an absolute path other than / (it is '${HOME-}')" ;; esac
  _cc_p="$(cc_resolve "$1")" || exit 1
  _cc_d="$(dirname "$_cc_p")"
  CC_TREE="$(dirname "$_cc_d")"
  CC_MG="$(dirname "$CC_TREE")"
  CC_VERSIONS="$(cc_data_home)/claude/versions"
  CC_STATE="$HOME/Library/Application Support/dev.mavergreen.claude-code"
  CC_CACHE="$HOME/Library/Caches/dev.mavergreen.claude-code"
  CC_LINK="$HOME/.local/bin/claude"
  CC_CDN="${CLAUDE_CODE_CDN:-https://downloads.claude.ai/claude-code-releases}"
}

cc_is_version() {
  case "$1" in
    ''|*[!0-9.]*|.*|*.|*..*) return 1 ;;
  esac
  return 0
}

cc_ver_gt() {
  _cc_a="$1"; _cc_b="$2"
  while [ -n "$_cc_a" ] || [ -n "$_cc_b" ]; do
    _cc_fa="${_cc_a%%.*}"; _cc_fb="${_cc_b%%.*}"
    case "$_cc_a" in *.*) _cc_a="${_cc_a#*.}" ;; *) _cc_a="" ;; esac
    case "$_cc_b" in *.*) _cc_b="${_cc_b#*.}" ;; *) _cc_b="" ;; esac
    while :; do case "$_cc_fa" in 0?*) _cc_fa="${_cc_fa#0}" ;; *) break ;; esac; done
    while :; do case "$_cc_fb" in 0?*) _cc_fb="${_cc_fb#0}" ;; *) break ;; esac; done
    : "${_cc_fa:=0}" "${_cc_fb:=0}"
    [ "${#_cc_fa}" -gt "${#_cc_fb}" ] && return 0
    [ "${#_cc_fa}" -lt "${#_cc_fb}" ] && return 1
    while [ -n "$_cc_fa" ]; do
      _cc_da="${_cc_fa%"${_cc_fa#?}"}"; _cc_db="${_cc_fb%"${_cc_fb#?}"}"
      [ "$_cc_da" -gt "$_cc_db" ] && return 0
      [ "$_cc_da" -lt "$_cc_db" ] && return 1
      _cc_fa="${_cc_fa#?}"; _cc_fb="${_cc_fb#?}"
    done
  done
  return 1
}

cc_sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

cc_truthy() {
  _cc_v="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  case "$_cc_v" in 1|true|yes|on) return 0 ;; esac
  return 1
}
