#!/bin/sh
# platform: macOS-only -- sourced through CLAUDE_ENV_FILE before every Bash-tool command, by zsh 5.0.2 or bash 3.2 on Mac OS X 10.9

__cc_bin="${CLAUDE_ENV_FILE%/share/claude-code/claude-env.sh}/libexec/claude-code/shell-bin"
case ":${PATH-}:" in
  *":$__cc_bin:"*) ;;
  *) PATH="$__cc_bin${PATH:+:$PATH}"; export PATH ;;
esac
unset __cc_bin

unalias cd pushd 2>/dev/null || :
__cc_cd_guard() {
  local __cc_cmd=$1; shift
  while [ "$#" -gt 0 ]; do
    case $1 in
      --) shift; break ;;
      -[LPeqs]*) shift ;;
      *) break ;;
    esac
  done
  if [ "$#" -eq 0 ] || [ -z "$1" ]; then
    echo "claude-env: refusing '$__cc_cmd' with no directory or an empty one -- an unset or empty variable would send the rest of this command to \$HOME (write '$__cc_cmd ~' to go home on purpose)" >&2
    exit 1
  fi
}
cd() { __cc_cd_guard cd "$@"; builtin cd "$@"; }
pushd() { __cc_cd_guard pushd "$@"; builtin pushd "$@"; }

if [ -n "${ZSH_VERSION-}" ]; then setopt SH_WORD_SPLIT NO_NOMATCH KSH_TYPESET; fi

if [ -z "${__cc_chaining-}" ] && [ -n "${MAVERGREEN_USER_CLAUDE_ENV_FILE-}" ] && [ -f "$MAVERGREEN_USER_CLAUDE_ENV_FILE" ] && [ -r "$MAVERGREEN_USER_CLAUDE_ENV_FILE" ]; then
  __cc_chaining=1
  . "$MAVERGREEN_USER_CLAUDE_ENV_FILE"
  unset __cc_chaining
fi
