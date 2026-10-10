#!/bin/sh
# platform: macOS-only -- the launcher patches Claude Code for Mac OS X 10.9 with drydock-macho-rewrite

cc_recipe_key() {
  _cc_k=""
  IFS= read -r _cc_k < "$CC_TREE/share/claude-code/recipe-id" || :
  [ -n "$_cc_k" ] || cc_die "missing or empty $CC_TREE/share/claude-code/recipe-id"
  printf '%s\n' "$_cc_k" | cut -c1-16
}

cc_entry() {
  _cc_ek="$(cc_recipe_key)" || return 1
  printf '%s/%s-%s/claude\n' "$CC_CACHE" "$1" "$_cc_ek"
}

cc_entry_version() {
  _cc_ev="${1%/claude}"
  _cc_ev="${_cc_ev##*/}"
  printf '%s\n' "${_cc_ev%-*}"
}

cc_build() {
  _cc_bv="$1"
  _cc_be="$(cc_entry "$_cc_bv")" || exit 1
  [ -f "$_cc_be" ] && return 0
  _cc_vr=0
  cc_verified "$_cc_bv" || _cc_vr=$?
  case "$_cc_vr" in
    0) ;;
    1) rm -f "$CC_VERSIONS/$_cc_bv"
       (cc_fetch "$_cc_bv") || return 2 ;;
    3) return 4 ;;
    *) return 2 ;;
  esac
  _cc_bd="$(dirname "$_cc_be")"
  mkdir -p "$CC_STATE" || return 3
  mkdir -p "$_cc_bd" || { echo "could not create $_cc_bd" > "$CC_STATE/last-patch-error"; return 3; }
  find "$_cc_bd" -name 'claude.*' -type f -mmin +60 -exec rm -f {} + 2>/dev/null
  _cc_bt="$(mktemp "$_cc_bd/claude.$$.XXXXXX")" || { echo "could not create a temporary file in $_cc_bd" > "$CC_STATE/last-patch-error"; return 3; }
  if ! "$CC_TREE/libexec/drydock-macho-rewrite" "$CC_VERSIONS/$_cc_bv" "$_cc_bt" \
      < "$CC_TREE/share/claude-code/recipe" > "$CC_STATE/last-patch-error" 2>&1; then
    rm -f "$_cc_bt"
    return 3
  fi
  if ! { chmod +x "$_cc_bt" && mv -f "$_cc_bt" "$_cc_be"; }; then
    rm -f "$_cc_bt"
    return 3
  fi
  return 0
}

cc_cached_newest() {
  _cc_ck="$(cc_recipe_key)"
  _cc_cb=""
  for _cc_ce in "$CC_CACHE"/*-"$_cc_ck"/claude; do
    [ -f "$_cc_ce" ] || continue
    _cc_cn="${_cc_ce%/claude}"
    _cc_cn="${_cc_cn##*/}"
    _cc_cn="${_cc_cn%-"$_cc_ck"}"
    cc_is_version "$_cc_cn" || continue
    if [ -z "$_cc_cb" ] || cc_ver_gt "$_cc_cn" "$_cc_cb"; then _cc_cb="$_cc_cn"; fi
  done
  [ -z "$_cc_cb" ] || printf '%s\n' "$_cc_cb"
}

cc_runnable() {
  _cc_rv="$1"
  _cc_rr=0
  cc_recipe_key >/dev/null || exit 1
  cc_build "$_cc_rv" || _cc_rr=$?
  if [ "$_cc_rr" -eq 0 ]; then
    cc_entry "$_cc_rv"
    return 0
  fi
  if [ "$_cc_rr" -eq 4 ]; then
    _cc_why="Claude Code $_cc_rv is not published at $CC_CDN"
    _cc_rl="$(cc_latest 2>/dev/null)" || _cc_rl=""
    if [ -n "$_cc_rl" ] && [ "$_cc_rl" != "$_cc_rv" ]; then
      cc_note "$_cc_why; running the latest, $_cc_rl"
      cc_runnable "$_cc_rl"
      return
    fi
  elif [ "$_cc_rr" -eq 2 ]; then
    _cc_why="could not verify Claude Code $_cc_rv while offline"
  else
    _cc_why="could not patch Claude Code $_cc_rv (see $CC_STATE/last-patch-error)"
  fi
  _cc_ro="$(cc_cached_newest)"
  [ -n "$_cc_ro" ] || cc_die "cannot run Claude Code $_cc_rv: $_cc_why"
  cc_note "$_cc_why; running $_cc_ro"
  cc_entry "$_cc_ro"
}
