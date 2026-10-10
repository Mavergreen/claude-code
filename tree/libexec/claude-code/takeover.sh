#!/bin/sh
# platform: macOS-only -- the launcher exists to run Claude Code on Mac OS X 10.9

cc_take() {
  _cc_rmf=-f
  if [ -d "$1" ] && [ ! -L "$1" ]; then _cc_rmf=-rf; fi
  if rm "$_cc_rmf" "$1" 2>/dev/null; then
    _cc_gone="${_cc_gone}${_cc_gone:+
}$1"
  else
    _cc_stuck=1
  fi
}

cc_takeover() {
  _cc_sys="$CC_MG/var/claude-code/removed-mavericks-forever"
  _cc_dg=none
  if [ -s "$_cc_sys" ] && [ -r "$_cc_sys" ]; then _cc_dg="$(cc_sha256 "$_cc_sys")"; fi
  if [ -f "$CC_STATE/took-over" ]; then
    _cc_was=""
    IFS= read -r _cc_was < "$CC_STATE/took-over" || :
    [ "$_cc_was" = "$_cc_dg" ] && return 0
  fi
  _cc_gone=""
  _cc_stuck=0
  _cc_data="$(cc_data_home)/claude"
  for _cc_p in "$HOME/.local/share/claude-mavericks" "$HOME/.cache/claude-mavericks"; do
    if [ -e "$_cc_p" ] || [ -L "$_cc_p" ]; then
      cc_take "$_cc_p"
    fi
  done
  for _cc_dir in "$_cc_data" "$_cc_data/versions"; do
    for _cc_n in S.dylib I.dylib c++.1.dylib; do
      if [ -L "$_cc_dir/$_cc_n" ]; then
        cc_take "$_cc_dir/$_cc_n"
      fi
    done
    for _cc_p in "$_cc_dir"/*.mf-tmp.*; do
      if [ -e "$_cc_p" ] || [ -L "$_cc_p" ]; then
        cc_take "$_cc_p"
      fi
    done
  done
  if [ -n "$_cc_gone" ] || [ -s "$_cc_sys" ]; then
    cc_note "removed what Mavericks Forever left behind:"
    if [ -n "$_cc_gone" ]; then
      printf '%s\n' "$_cc_gone" | while IFS= read -r _cc_p; do
        case "$_cc_p" in
          "$HOME"/*) _cc_p="~${_cc_p#"$HOME"}" ;;
        esac
        cc_note "  $_cc_p"
      done
    fi
    if [ -s "$_cc_sys" ]; then
      while IFS= read -r _cc_p || [ -n "$_cc_p" ]; do
        case "$_cc_p" in '#'*) continue ;; esac
        cc_note "  $_cc_p"
      done < "$_cc_sys"
    fi
    cc_note "To go back to Mavericks Forever, uninstall Claude Code for Mavericks first (sudo mavergreen uninstall claude-code), then rerun https://mavericksforever.com/claude/install.sh"
  fi
  if [ "$_cc_stuck" -eq 0 ]; then
    { mkdir -p "$CC_STATE" && printf '%s\n' "$_cc_dg" > "$CC_STATE/took-over"; } || true
  fi
  return 0
}

cc_claim_link() {
  _cc_want="$CC_MG/bin/claude"
  if [ -L "$CC_LINK" ]; then
    _cc_a="$(cc_resolve "$CC_LINK")" || _cc_a=""
    _cc_b="$(cc_resolve "$_cc_want")" || _cc_b=""
    if [ -n "$_cc_a" ] && [ "$_cc_a" = "$_cc_b" ]; then
      return 0
    fi
    case "$(readlink "$CC_LINK")" in
      */claude/versions/*) ;;
      *) cc_foreign_link; return 0 ;;
    esac
  elif [ -e "$CC_LINK" ]; then
    cc_foreign_link
    return 0
  fi
  mkdir -p "$(dirname "$CC_LINK")"
  _cc_tmp="$(mktemp -u "$(dirname "$CC_LINK")/.claude-link.XXXXXX")"
  ln -s "$_cc_want" "$_cc_tmp"
  if ! perl -e 'rename($ARGV[0],$ARGV[1]) or die "$!\n"' "$_cc_tmp" "$CC_LINK"; then
    rm -f "$_cc_tmp"
    return 1
  fi
}

cc_foreign_link() {
  [ -f "$CC_STATE/foreign-link" ] && return 0
  cc_note "$CC_LINK is not this launcher's and is left alone"
  mkdir -p "$CC_STATE"
  : > "$CC_STATE/foreign-link"
}
