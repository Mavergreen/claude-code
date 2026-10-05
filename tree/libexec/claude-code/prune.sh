#!/bin/sh
# platform: macOS-only -- the launcher owns the version cleanup Anthropic's updater skips on 10.9

cc_prune() {
  cc_is_version "${1-}" || return 0
  _cc_pr="$1"
  _cc_pp=""
  _cc_pi="$(cc_installed)"
  for _cc_pv in $_cc_pi; do
    if cc_ver_gt "$_cc_pr" "$_cc_pv"; then
      if [ -z "$_cc_pp" ] || cc_ver_gt "$_cc_pv" "$_cc_pp"; then _cc_pp="$_cc_pv"; fi
    fi
  done
  _cc_keep=" $_cc_pr $_cc_pp "
  for _cc_pv in $_cc_pi; do
    if cc_ver_gt "$_cc_pv" "$_cc_pr"; then _cc_keep="$_cc_keep$_cc_pv "; fi
  done
  for _cc_pv in $_cc_pi; do
    case "$_cc_keep" in *" $_cc_pv "*) continue ;; esac
    rm -f "$CC_VERSIONS/$_cc_pv" "$CC_STATE/verified/$_cc_pv" 2>/dev/null || :
  done
  _cc_pk="$(cc_recipe_key 2>/dev/null)" || return 0
  for _cc_pd in "$CC_CACHE"/*; do
    [ -d "$_cc_pd" ] && [ ! -L "$_cc_pd" ] || continue
    _cc_pn="${_cc_pd##*/}"
    case "$_cc_pn" in
      *-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
      *) continue ;;
    esac
    _cc_pc="${_cc_pn##*-}"
    _cc_pe="${_cc_pn%-*}"
    cc_is_version "$_cc_pe" || continue
    case "$_cc_keep" in *" $_cc_pe "*) [ "$_cc_pc" != "$_cc_pk" ] || continue ;; esac
    cc_unheld "$_cc_pd/claude" || continue
    rm -rf "$_cc_pd" 2>/dev/null || :
  done
  return 0
}

cc_unheld() {
  [ -e "$1" ] || [ -L "$1" ] || return 0
  CC_LSOF="${CC_LSOF:-/usr/sbin/lsof}"
  [ -f "$CC_LSOF" ] && [ -x "$CC_LSOF" ] || return 1
  _cc_uo="$("$CC_LSOF" -a -c claude -w -t "$1" 2>&1)"
  [ "$?" -eq 1 ] && [ -z "$_cc_uo" ]
}
