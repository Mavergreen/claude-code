#!/bin/sh
# platform: macOS-only -- the environment Claude Code needs on Mac OS X 10.9 (avxemu on CPUs without AVX2)

cc_setup_env() {
  JSC_numberOfGCMarkers=1
  DISABLE_INSTALLATION_CHECKS=1
  export JSC_numberOfGCMarkers DISABLE_INSTALLATION_CHECKS
  case " $(PATH="${PATH:+$PATH:}${CC_SBIN:-/usr/sbin}" sysctl -n machdep.cpu.leaf7_features 2>/dev/null) " in
    *" AVX2 "*) ;;
    *) case "${DYLD_INSERT_LIBRARIES-}" in
         "$CC_MG/avxemu/lib/libavxemu.dylib"|"$CC_MG/avxemu/lib/libavxemu.dylib":*) ;;
         *) DYLD_INSERT_LIBRARIES="$CC_MG/avxemu/lib/libavxemu.dylib${DYLD_INSERT_LIBRARIES:+:$DYLD_INSERT_LIBRARIES}"
            export DYLD_INSERT_LIBRARIES ;;
       esac ;;
  esac
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
  return 0
}
