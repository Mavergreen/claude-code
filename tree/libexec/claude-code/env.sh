#!/bin/sh
# platform: macOS-only -- the environment Claude Code needs on Mac OS X 10.9

cc_setup_env() {
  JSC_numberOfGCMarkers=1
  DISABLE_INSTALLATION_CHECKS=1
  export JSC_numberOfGCMarkers DISABLE_INSTALLATION_CHECKS
  _cc_lb="$HOME/.local/bin"
  _cc_lp="$(CDPATH= cd -P "$_cc_lb" 2>/dev/null && pwd -P)" || _cc_lp=""
  _cc_have=0
  _cc_oifs="$IFS"
  case "$-" in *f*) _cc_nf=1 ;; *) _cc_nf=0; set -f ;; esac
  IFS=:
  for _cc_pe in $PATH; do
    if [ "$_cc_pe" = "$_cc_lb" ] || { [ -n "$_cc_lp" ] && [ "$_cc_pe" = "$_cc_lp" ]; }; then _cc_have=1; fi
  done
  IFS="$_cc_oifs"
  [ "$_cc_nf" -eq 1 ] || set +f
  if [ "$_cc_have" -eq 0 ]; then
    PATH="${PATH:+$PATH:}${_cc_lp:-$_cc_lb}"
    export PATH
  fi
  _cc_ours="$CC_TREE/share/claude-code/claude-env.sh"
  if [ -f "$_cc_ours" ] && [ -r "$_cc_ours" ]; then
    case "${CLAUDE_ENV_FILE-}" in
      ''|*/share/claude-code/claude-env.sh) ;;
      /*) MAVERGREEN_USER_CLAUDE_ENV_FILE="$CLAUDE_ENV_FILE"; export MAVERGREEN_USER_CLAUDE_ENV_FILE ;;
      *) MAVERGREEN_USER_CLAUDE_ENV_FILE="$PWD/$CLAUDE_ENV_FILE"; export MAVERGREEN_USER_CLAUDE_ENV_FILE ;;
    esac
    CLAUDE_ENV_FILE="$_cc_ours"
    export CLAUDE_ENV_FILE
  fi
  return 0
}
