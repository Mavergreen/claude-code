#!/bin/sh
# platform: macOS-only -- the shell guards target Claude Code's Bash tool on Mac OS X 10.9, under its sh, zsh 5.0.2 and bash 3.2
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
TREE="$H/root/usr/local/mavergreen/claude-code"
E="$TREE/share/claude-code/claude-env.sh"
SB="$TREE/libexec/claude-code/shell-bin"
NL='
'
mkdir -p "$H/work" "$H/tmp" "$H/my env"
h_assert_ok test -f "$E"
for f in mktemp timeout env setsid base64 cat date head paste readlink realpath sed sort tac uniq xargs; do h_assert_ok test -x "$SB/$f"; done

_probe="$(TMPDIR="$H/tmp/" /usr/bin/mktemp -t probe)"
REFDIR="$(cd "$(dirname "$_probe")" && pwd -P)"
rm -f "$_probe"
under_tmp() {
  case "$1" in /*) ;; *) echo no; return ;; esac
  _ud="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || _ud=
  if [ "$_ud" = "$REFDIR" ]; then echo yes; else echo no; fi
}
M="$SB/mktemp"
for args in "-d" "" "-q" "-dq" "-d -q" "-u"; do
  rc=0
  # shellcheck disable=SC2086
  out="$(TMPDIR="$H/tmp/" "$M" $args 2>&1)" || rc=$?
  h_assert_eq "0" "$rc" "mktemp ${args:-(no args)} succeeds with no template"
  h_assert_eq "yes" "$(under_tmp "$out")" "mktemp ${args:-(no args)} gives a path in the directory the host mktemp -t picks: $out"
  case "$(basename "$out")" in tmp.*) n=yes ;; *) n=no ;; esac
  h_assert_eq "yes" "$n" "mktemp ${args:-(no args)} names it tmp.*, as modern macOS does: $out"
done
out="$(TMPDIR="$H/tmp/" "$M" -d)"
h_assert_ok test -d "$out"
out="$(TMPDIR="$H/tmp/" "$M")"
h_assert_ok test -f "$out"
rc=0; out="$(env -i PATH=/usr/bin:/bin "$M" -d 2>&1)" || rc=$?
h_assert_eq "0" "$rc" "mktemp -d with TMPDIR unset succeeds"
case "$out" in /*/tmp.*) n=yes ;; *) n=no ;; esac
h_assert_eq "yes" "$n" "mktemp -d with TMPDIR unset names an absolute tmp.* path: $out"
h_assert_ok test -d "$out"
[ ! -d "$out" ] || rmdir "$out"
out="$("$M" -d "$H/tmp/explicit.XXXXXX")"
case "$out" in "$H/tmp/explicit."*) n=yes ;; *) n=no ;; esac
h_assert_eq "yes" "$n" "an explicit template is passed through: $out"
out="$(TMPDIR="$H/tmp/" "$M" -t mine)"
case "$(basename "$out")" in mine.*) n=yes ;; *) n=no ;; esac
h_assert_eq "yes" "$n" "-t prefix is passed through: $out"
out="$(TMPDIR="$H/tmp/" "$M" -dt mine)"
h_assert_ok test -d "$out"
case "$(basename "$out")" in mine.*) n=yes ;; *) n=no ;; esac
h_assert_eq "yes" "$n" "-dt prefix is passed through: $out"
h_assert_fails sh -c '"$@" 2>/dev/null' sh "$M" -d "$H/tmp/nonexistent-parent/x.XXXXXX"

refusal() { printf "claude-env: refusing '%s' with no directory or an empty one -- an unset or empty variable would send the rest of this command to \$HOME (write '%s ~' to go home on purpose)" "$1" "$1"; }
shells=/bin/sh
for s in /bin/zsh /bin/bash; do [ ! -x "$s" ] || shells="$shells $s"; done
srun() {
  _s=$1 _f=$2; shift 2
  (
    unset BASH_ENV ENV ZDOTDIR MAVERGREEN_USER_CLAUDE_ENV_FILE
    cd "$H/work" && HOME="$H/home" TMPDIR="$H/tmp/" CLAUDE_ENV_FILE="$_f" PATH=/usr/bin:/bin "$_s" -c "$@" 2>&1
  )
}
run() { _rs=$1; shift; srun "$_rs" "$E" '. "$CLAUDE_ENV_FILE"; '"$1"; }
for sh in $shells; do
  for cmd in cd pushd; do
    for line in "$cmd" "$cmd \"\"" "$cmd -L \"\"" "T=\"\"; $cmd \$T" "T=\"\"; $cmd -- \$T"; do
      rc=0; out="$(run "$sh" "$line; echo REACHED-NEXT")" || rc=$?
      h_assert_eq "1" "$rc" "[$sh] '$line' exits 1"
      h_assert_contains "$out" "$(refusal "$cmd")" "[$sh] '$line' refuses"
      case "$out" in *REACHED-NEXT*) n=yes ;; *) n=no ;; esac
      h_assert_eq "no" "$n" "[$sh] '$line' aborts the rest of the command"
    done
  done
  h_assert_eq "$H/home" "$(run "$sh" 'cd ~ && pwd')" "[$sh] cd ~ still goes home on purpose"
  h_assert_eq "$H/home" "$(run "$sh" 'cd "$HOME" && pwd')" "[$sh] cd to a real directory works"
  h_assert_eq "$H/work" "$(run "$sh" 'cd "$HOME" && cd - >/dev/null && pwd')" "[$sh] cd - works"
  h_assert_eq "$H/home" "$(run "$sh" 'pushd "$HOME" >/dev/null && pwd')" "[$sh] pushd to a real directory works"
  for f in mktemp timeout env setsid base64 cat date head paste readlink realpath sed sort tac uniq xargs; do
    h_assert_eq "$SB/$f" "$(run "$sh" "command -v $f")" "[$sh] $f resolves to the shim"
  done
  p="$(run "$sh" '. "$CLAUDE_ENV_FILE"; printf %s "$PATH"')"
  case "$p" in "$SB:"*) n=yes ;; *) n=no ;; esac
  h_assert_eq "yes" "$n" "[$sh] the shims go first on PATH: $p"
  case ":${p#"$SB:"}:" in *":$SB:"*) n=yes ;; *) n=no ;; esac
  h_assert_eq "no" "$n" "[$sh] the shims go on PATH once: $p"
  out="$(run "$sh" 'T=$(mktemp -d); cd "$T" && pwd')" || : # portability-ok: the mktemp under test is the shim, which supplies the template
  h_assert_eq "yes" "$(under_tmp "$out")" "[$sh] a bare mktemp -d, then cd into it, lands in a fresh temp dir: $out"
done

GENV=/opt/pkg/bin/genv
envrun() {
  _rc=0
  # shellcheck disable=SC2086
  _out="$(A=a B=b /usr/bin/env ${ENVX-} "$@" 2>&1)" || _rc=$?
}
envcase() {
  _want=$1 _wrc=$2 _label=$3; shift 3
  envrun "$SB/env" "$@"
  h_assert_eq "$_want" "$_out" "env shim: $_label"
  h_assert_eq "$_wrc" "$_rc" "env shim: $_label exits $_wrc"
  if [ -x "$GENV" ]; then
    envrun "$GENV" "$@"
    h_assert_eq "$_want" "$_out" "GNU env oracle: $_label"
    h_assert_eq "$_wrc" "$_rc" "GNU env oracle: $_label exits $_wrc"
  fi
}
envcase unset 0 "-u A" -u A sh -c 'echo ${A-unset}'
envcase unset 0 "-uA" -uA sh -c 'echo ${A-unset}'
envcase unset 0 "--unset=A" --unset=A sh -c 'echo ${A-unset}'
envcase unset 0 "--unset A" --unset A sh -c 'echo ${A-unset}'
envcase "unset unset" 0 "-u A -u B" -u A -u B sh -c 'echo ${A-unset} ${B-unset}'
envcase "unset b" 0 "-u A leaves B" -u A sh -c 'echo ${A-unset} ${B-unset}'
envcase "" 0 "-u NOPE" -u NOPE true
envcase unset1 0 "-u A -i B=1" -u A -i B=1 sh -c 'echo ${A-unset}$B'
envcase unset1 0 "-i -u A B=1" -i -u A B=1 sh -c 'echo ${A-unset}$B'
envcase unset1 0 "-u A B=1" -u A B=1 sh -c 'echo ${A-unset}$B'
envcase "" 0 "--" -- true
envcase a 0 "-- then a utility" -- sh -c 'echo ${A-unset}'
envcase "" 3 "the utility's status" -u A sh -c 'exit 3'
envcase unset 0 "-i -u __cc_i still clears the environment" -i -u __cc_i sh -c 'echo ${A-unset}'
envcase "unset unset" 0 "the shim's own state never reaches the command" -u A sh -c 'echo ${__cc_i-unset} ${__cc_u-unset}'
ENVX="__cc_i=1 __cc_u=2"
envcase "1 2" 0 "inherited __cc_i and __cc_u pass through" sh -c 'echo ${__cc_i-unset} ${__cc_u-unset}'
envcase "1 2 unset" 0 "inherited __cc_i and __cc_u pass through -u A" -u A sh -c 'echo ${__cc_i-unset} ${__cc_u-unset} ${A-unset}'
envcase "unset 2 a" 0 "-u __cc_i unsets only that" -u __cc_i sh -c 'echo ${__cc_i-unset} ${__cc_u-unset} ${A-unset}'
ENVX="UID=5"
envcase "" 1 "-u UID unsets UID quietly" -u UID printenv UID
ENVX=""
envcase "" 1 "-u UID with no UID in the environment is quiet" -u UID printenv UID
ENVX="a.b=1 1z=2"
envcase "" 1 "-u a.b unsets a name sh cannot" -u a.b printenv a.b
envcase "2" 0 "-u a.b leaves 1z" -u a.b printenv 1z
envcase "" 1 "-u 1z unsets a name sh cannot" -u 1z printenv 1z
ENVX=""
for impl in "$SB/env" "$GENV"; do
  [ -x "$impl" ] || continue
  h_assert_eq "x${NL}Q=z${NL}|1" "$(/usr/bin/env "M=x${NL}Q=z" a.b=1 "$impl" -u a.b printenv M; /usr/bin/env "M=x${NL}Q=z" a.b=1 "$impl" -u a.b printenv Q || echo "|$?")" "$impl -u a.b keeps a multi-line value whole"
  for bad in "" "a=b"; do
    envrun "$impl" -u "$bad" true
    h_assert_eq "125" "$_rc" "$impl -u '$bad' fails as GNU env does"
    h_assert_contains "$_out" "cannot unset" "$impl -u '$bad' says it cannot unset"
  done
done
ENVX="OLDPWD=/x PWD=/y _=/z"
for v in OLDPWD:/x PWD:/y _:/z; do
  envcase "${v#*:}" 0 "${v%%:*} passes through as it came" printenv "${v%%:*}"
  envcase "${v#*:}" 0 "${v%%:*} passes through -u A as it came" -u A printenv "${v%%:*}"
done
ENVX=""
for impl in "$SB/env" "$GENV"; do
  [ -x "$impl" ] || continue
  envrun "$impl" -u A
  h_assert_eq "0" "$_rc" "$impl -u A with no utility exits 0"
  case "$NL$_out" in *"${NL}A="*) n=yes ;; *) n=no ;; esac
  h_assert_eq "no" "$n" "$impl -u A with no utility prints the environment without A"
  case "$NL$_out" in *"${NL}B=b$NL"*) n=yes ;; *) n=no ;; esac
  h_assert_eq "yes" "$n" "$impl -u A with no utility prints B"
  h_assert_contains "$NL$_out" "${NL}HOME=" "$impl -u A with no utility prints HOME"
done

U="$H/my env/u.sh"
printf 'CC_T=user\necho sourced >> "$(dirname "$MAVERGREEN_USER_CLAUDE_ENV_FILE")/count"\n' > "$U"
CT="$H/chain tree"
cp -R "$TREE" "$CT"
CE="$CT/share/claude-code/claude-env.sh"
{ printf 'CC_T=ours\n'; cat "$E"; } > "$CE"
urun() { _us=$1 _uf=$2; shift 2; srun "$_us" "$CE" 'export MAVERGREEN_USER_CLAUDE_ENV_FILE="$1"; '"$1" "$_us" "$_uf"; }
count() { if [ -f "$H/my env/count" ]; then wc -l < "$H/my env/count" | tr -d ' '; else echo 0; fi; }
for sh in $shells; do
  rm -f "$H/my env/count"
  h_assert_eq "user" "$(urun "$sh" "$U" '. "$CLAUDE_ENV_FILE"; echo "$CC_T"')" "[$sh] the user's env file runs after ours and wins"
  h_assert_eq "1" "$(count)" "[$sh] the user's env file is sourced once per source of ours"
  rm -f "$H/my env/count"
  urun "$sh" "$U" '. "$CLAUDE_ENV_FILE"; . "$CLAUDE_ENV_FILE"' >/dev/null
  h_assert_eq "2" "$(count)" "[$sh] sourcing ours twice sources the user's twice"
  h_assert_eq "ours" "$(urun "$sh" "$H/my env/missing.sh" '. "$CLAUDE_ENV_FILE"; echo "$CC_T"')" "[$sh] a missing user file is skipped"
  h_assert_eq "ours" "$(srun "$sh" "$CE" '. "$CLAUDE_ENV_FILE"; echo "$CC_T"')" "[$sh] with no user file, ours alone runs"
done
cp "$U" "$H/my env/locked.sh"
chmod 000 "$H/my env/locked.sh"
locked_shells=$shells
if [ -r "$H/my env/locked.sh" ]; then
  echo "claude-env-test: skipping the unreadable-file checks: mode 000 is readable to this user" >&2
  locked_shells=""
fi
for sh in $locked_shells; do
  rc=0; out="$(urun "$sh" "$H/my env/locked.sh" '. "$CLAUDE_ENV_FILE"')" || rc=$?
  h_assert_eq "" "$out" "[$sh] an unreadable user file is skipped quietly"
  h_assert_eq "0" "$rc" "[$sh] an unreadable user file still exits 0"
done
chmod 600 "$H/my env/locked.sh"

rm -f "$H/my env/count"
out="$(
  unset MAVERGREEN_USER_CLAUDE_ENV_FILE BASH_ENV ENV
  . "$CT/libexec/claude-code/env.sh"
  CC_TREE="$CT"
  CLAUDE_ENV_FILE="$U"
  cc_setup_env
  cc_setup_env
  . "$CLAUDE_ENV_FILE"
  printf '%s|%s|%s' "$CLAUDE_ENV_FILE" "${MAVERGREEN_USER_CLAUDE_ENV_FILE-}" "$CC_T"
)"
h_assert_eq "$CE|$U|user" "$out" "a nested launch keeps ours and the user's, and chains once"
h_assert_eq "1" "$(count)" "a nested launch sources the user's env file once"
out="$(
  unset MAVERGREEN_USER_CLAUDE_ENV_FILE BASH_ENV ENV
  . "$CT/libexec/claude-code/env.sh"
  CC_TREE="$CT"
  cd "$H/my env"
  CLAUDE_ENV_FILE="u.sh"
  cc_setup_env
  cd "$H/work"
  . "$CLAUDE_ENV_FILE"
  printf '%s|%s' "${MAVERGREEN_USER_CLAUDE_ENV_FILE-}" "$CC_T"
)"
h_assert_eq "$U|user" "$out" "a relative user env file still chains after the Bash tool's cwd moves"

PERL=/usr/bin/perl
now() { "$PERL" -MTime::HiRes=time -e 'printf "%.2f\n", time'; }
expect() {
  _impl=$1 _bin=$2 _want=$3 _max=$4; shift 4
  _t0=$(now); _rc=$(sh -c '"$@" >/dev/null 2>&1; echo $?' sh "$_bin" "$@" 2>/dev/null); _t1=$(now)
  _slow=$("$PERL" -e "print(($_t1 - $_t0) > $_max ? 1 : 0)")
  h_assert_eq "$_want" "$_rc" "[timeout:$_impl] $* exits $_want, as GNU timeout(1) does"
  h_assert_eq "0" "$_slow" "[timeout:$_impl] $* finishes within ${_max}s"
}
TO="$SB/timeout"
GTO=""
for g in /opt/pkg/bin/gtimeout /opt/pkg/gnu/bin/timeout /opt/local/bin/gtimeout /usr/local/bin/gtimeout; do
  if [ -x "$g" ]; then GTO="$g"; break; fi
done
h_assert_eq "# platform: macOS-only -- GNU timeout for Mac OS X 10.9, which has none, in its perl 5.16" "$(sed -n 2p "$TO")" "timeout declares its platform"
timeout_impls="shim gnu-oracle"
if [ ! -x "$PERL" ]; then
  echo "claude-env-test: skipping the timeout checks: no $PERL to run the shim or time it" >&2
  timeout_impls=""
fi
for impl in $timeout_impls; do
  case "$impl" in shim) bin="$TO" ;; *) bin="$GTO" ;; esac
  [ -n "$bin" ] || continue
  expect "$impl" "$bin" 0   15 30 true
  expect "$impl" "$bin" 3   15 30 sh -c 'exit 3'
  expect "$impl" "$bin" 124 15 1 sleep 30
  expect "$impl" "$bin" 124 15 0.5 sleep 30
  expect "$impl" "$bin" 0   15 1m true
  expect "$impl" "$bin" 137 15 -s KILL 1 sleep 30
  expect "$impl" "$bin" 143 15 --preserve-status 1 sleep 30
  expect "$impl" "$bin" 137 15 -k 1 1 sh -c 'trap "" TERM; sleep 30'
  expect "$impl" "$bin" 127 15 30 /nonexistent/command
  expect "$impl" "$bin" 126 15 30 /etc/passwd
  expect "$impl" "$bin" 125 15 bogus true
  rm -f "$H/gc.pid"
  "$bin" 1 sh -c 'sleep 30 & echo $! > "$1"; wait' sh "$H/gc.pid" >/dev/null 2>&1 || :
  h_assert_ok test -s "$H/gc.pid"
  gc="$(cat "$H/gc.pid" 2>/dev/null || :)"
  alive=no
  if [ -n "$gc" ]; then
    i=0
    while kill -0 "$gc" 2>/dev/null && [ "$i" -lt 10 ]; do /bin/sleep 1; i=$((i+1)); done
    if kill -0 "$gc" 2>/dev/null; then alive=yes; kill "$gc" 2>/dev/null || :; fi
  fi
  h_assert_eq "no" "$alive" "[timeout:$impl] the command's whole process group is signalled"
  h_assert_eq "" "$("$bin" 5 true 2>&1)" "[timeout:$impl] a run that succeeds prints nothing of its own"
  h_assert_eq "" "$("$bin" 1 sleep 5 2>&1 || :)" "[timeout:$impl] a run that times out prints nothing of its own"
done

SS="$SB/setsid"
h_assert_eq "# platform: macOS-only -- util-linux setsid for Mac OS X 10.9, which has none, in its perl 5.16" "$(sed -n 2p "$SS")" "setsid declares its platform"
if [ -x "$PERL" ]; then
  sid_of_self='printf "%s %s %s\n" "$$" "$(/usr/bin/perl -e "print syscall(310, getppid())")" "$(ps -o pgid= -p $$ | tr -d " ")"'
  out="$("$SS" -f -w sh -c "$sid_of_self")"
  pid="${out%% *}"
  h_assert_eq "$pid $pid $pid" "$out" "setsid -f -w runs the forked command as the leader of a new session and process group"
  out="$("$SS" sh -c "$sid_of_self")"
  pid="${out%% *}"
  h_assert_eq "$pid $pid $pid" "$out" "setsid in place (not a group leader) also leads a new session and process group"
  out="$("$PERL" -e 'setpgrp(0, 0); exec @ARGV' "$SS" -w sh -c "$sid_of_self")"
  pid="${out%% *}"
  h_assert_eq "$pid $pid $pid" "$out" "setsid run as a process group leader forks so the command can lead a new session"
  rc=0; "$SS" sh -c 'exit 3' || rc=$?
  h_assert_eq "3" "$rc" "setsid in place (not a group leader) exits with the command's status"
  rc=0; "$SS" -f -w sh -c 'exit 5' || rc=$?
  h_assert_eq "5" "$rc" "setsid -f -w waits for the forked command and exits with its status"
  rc=0; "$SS" -f -w sh -c 'kill -TERM $$' || rc=$?
  h_assert_eq "143" "$rc" "setsid -f -w exits 128+N when signal N kills the command"
  rc=0; "$SS" /nonexistent/command 2>/dev/null || rc=$?
  h_assert_eq "127" "$rc" "setsid exits 127 when the command is not found"
  rc=0; "$SS" /etc/passwd 2>/dev/null || rc=$?
  h_assert_eq "126" "$rc" "setsid exits 126 when the command cannot run"
  rc=0; "$SS" -f -w /nonexistent/command 2>/dev/null || rc=$?
  h_assert_eq "127" "$rc" "setsid -f -w exits 127 when the forked command is not found"
  rc=0; err="$("$SS" 2>&1)" || rc=$?
  h_assert_eq "1" "$rc" "setsid with no command fails"
  h_assert_contains "$err" "usage: setsid" "setsid with no command prints its usage"
  rc=0; err="$("$SS" -c true 2>&1)" || rc=$?
  h_assert_eq "1" "$rc" "setsid -c is not supported"
  h_assert_contains "$err" "-c" "setsid -c says what it does not support"
  rc=0; err="$("$SS" -x true 2>&1)" || rc=$?
  h_assert_eq "1" "$rc" "setsid rejects an unknown option"
  h_assert_eq "ran" "$("$SS" -- sh -c 'echo ran')" "setsid -- ends its options"
  rm -f "$H/detached"
  t0=$(now)
  out="$("$SS" -f sh -c 'sleep 2; echo "$$" > "$1"' sh "$H/detached" </dev/null >/dev/null 2>&1; echo "rc=$?")"
  t1=$(now)
  h_assert_eq "rc=0" "$out" "setsid -f exits 0 at once"
  h_assert_eq "0" "$("$PERL" -e "print(($t1 - $t0) > 1.5 ? 1 : 0)")" "setsid -f does not wait for the command"
  h_assert_fails test -e "$H/detached"
  i=0
  while [ ! -s "$H/detached" ] && [ "$i" -lt 10 ]; do /bin/sleep 1; i=$((i+1)); done
  h_assert_ok test -s "$H/detached"
  h_assert_eq "" "$("$SS" -f true 2>&1)" "setsid -f prints nothing of its own"
fi

shape() {
  _ss=$1 _sf=$2 _sn=$3 _sc=$4 _su=${5-}
  _txt="$(cat "$_sf")"
  (
    unset BASH_ENV ENV ZDOTDIR MAVERGREEN_USER_CLAUDE_ENV_FILE
    if [ -n "$_su" ]; then MAVERGREEN_USER_CLAUDE_ENV_FILE="$_su"; export MAVERGREEN_USER_CLAUDE_ENV_FILE; fi
    cd "$H/work" && HOME="$H/home" TMPDIR="$H/tmp/" CLAUDE_ENV_FILE="$_sf" PATH=/usr/bin:/bin "$_ss" -c "source \"\$1\" 2>/dev/null || true && $_txt
: && eval '$_sc'" "$_ss" "$_sn" 2>&1
  )
}
dotted() {
  _ds=$1 _df=$2 _dn=$3 _dc=$4 _du=${5-}
  (
    unset BASH_ENV ENV ZDOTDIR MAVERGREEN_USER_CLAUDE_ENV_FILE
    if [ -n "$_du" ]; then MAVERGREEN_USER_CLAUDE_ENV_FILE="$_du"; export MAVERGREEN_USER_CLAUDE_ENV_FILE; fi
    cd "$H/work" && HOME="$H/home" TMPDIR="$H/tmp/" CLAUDE_ENV_FILE="$_df" PATH=/usr/bin:/bin "$_ds" -c "source \"\$1\" 2>/dev/null || true
. \"\$CLAUDE_ENV_FILE\"
eval '$_dc'" "$_ds" "$_dn" 2>&1
  )
}
printf "shopt -s expand_aliases\nalias cd='cd -P'\nalias pushd='pushd >/dev/null'\n" > "$H/snap-bash-both"
printf "shopt -s expand_aliases\nalias pushd='pushd >/dev/null'\n" > "$H/snap-bash-pushd"
printf "alias cd=z\nalias pushd='pushd -q'\n" > "$H/snap-zsh-both"
printf "alias pushd=z\n" > "$H/snap-zsh-pushd"
printf ':\n' > "$H/snap-plain"
printf 'setopt WARN_CREATE_GLOBAL\n' > "$H/snap-zsh-warn"
cshells=""
for s in /bin/bash /bin/zsh /opt/pkg/bin/zsh; do [ ! -x "$s" ] || cshells="$cshells $s"; done
for sh in $cshells; do
  case "$sh" in *zsh) snaps="snap-zsh-both snap-zsh-pushd" ;; *) snaps="snap-bash-both snap-bash-pushd" ;; esac
  for form in shape dotted; do
    for snap in $snaps; do
      tag="[$sh $form $snap]"
      for cmd in cd pushd; do
        rc=0; out="$($form "$sh" "$E" "$H/$snap" "$cmd \"\"; echo REACHED-NEXT")" || rc=$?
        h_assert_eq "1" "$rc" "$tag '$cmd \"\"' exits 1 under the user's aliases"
        h_assert_contains "$out" "$(refusal "$cmd")" "$tag '$cmd \"\"' refuses under the user's aliases"
        case "$out" in *REACHED-NEXT*) n=yes ;; *) n=no ;; esac
        h_assert_eq "no" "$n" "$tag '$cmd \"\"' aborts the rest of the command"
      done
      rc=0; out="$($form "$sh" "$E" "$H/$snap" "cd /usr && pwd")" || rc=$?
      h_assert_eq "0|/usr" "$rc|$out" "$tag cd to a real directory works under the user's aliases"
      rc=0; out="$($form "$sh" "$E" "$H/$snap" "pushd /usr >/dev/null && pwd")" || rc=$?
      h_assert_eq "0|/usr" "$rc|$out" "$tag pushd to a real directory works under the user's aliases"
      out="$($form "$sh" "$E" "$H/$snap" "if typeset -f z >/dev/null 2>&1; then echo z-defined; fi")" || :
      h_assert_eq "" "$out" "$tag an alias's target is never redefined"
    done
    out="$($form "$sh" "$E" "$H/snap-plain" "export A=a; env -u A sh -c \"echo \\\${A-unset}\"")" || :
    h_assert_eq "unset" "$out" "[$sh $form] env -u on PATH is the shim"
    case "$sh" in
      *zsh)
        out="$($form "$sh" "$E" "$H/snap-zsh-warn" "cd /usr && pushd /bin >/dev/null && pwd")" || :
        h_assert_eq "/bin" "$out" "[$sh $form] cd and pushd print nothing extra under the snapshot's WARN_CREATE_GLOBAL"
        ;;
    esac
    out="$($form "$sh" "$E" "$H/snap-plain" 'a="x y"; for i in $a; do echo "[$i]"; done')" || :
    h_assert_eq "[x]$NL[y]" "$out" "[$sh $form] an unquoted variable splits into words, as in bash"
    out="$($form "$sh" "$E" "$H/snap-plain" 'for g in /nonexistent-cc-test/*; do echo "[$g]"; done; echo after')" || :
    h_assert_eq "[/nonexistent-cc-test/*]${NL}after" "$out" "[$sh $form] an unmatched pattern reaches the command literally and the command goes on"
    out="$($form "$sh" "$E" "$H/snap-plain" 'f() { local v=$1; echo "[$v]"; }; f "p q"; v="r s"; export X=$v; echo "[$X]"')" || :
    h_assert_eq "[p q]${NL}[r s]" "$out" "[$sh $form] assignments to local and export keep their value whole"
    case "$sh" in
      *zsh)
        printf 'unsetopt SH_WORD_SPLIT\n' > "$H/my env/nosplit.sh"
        out="$($form "$sh" "$E" "$H/snap-plain" 'a="x y"; for i in $a; do echo "[$i]"; done' "$H/my env/nosplit.sh")" || :
        h_assert_eq "[x y]" "$out" "[$sh $form] the user's env file can turn SH_WORD_SPLIT back off"
        ;;
    esac
    rm -f "$H/my env/count"
    out="$($form "$sh" "$CE" "$H/snap-plain" "echo \$CC_T" "$U")" || :
    h_assert_eq "user" "$out" "[$sh $form] the user's env file runs after ours and wins"
    h_assert_eq "1" "$(count)" "[$sh $form] the user's env file is sourced once"
    rc=0; out="$($form "$sh" "$CE" "$H/snap-plain" "echo \$CC_T; cd \"\"" "$CE")" || rc=$?
    h_assert_eq "1" "$rc" "[$sh $form] ours chained to itself still ends, and still guards"
    h_assert_contains "$out" "ours$NL$(refusal cd)" "[$sh $form] ours chained to itself runs once more, then stops"
  done
done

TB="$H/tree b"
cp -R "$TREE" "$TB"
BE="$TB/share/claude-code/claude-env.sh"
out="$(
  unset MAVERGREEN_USER_CLAUDE_ENV_FILE BASH_ENV ENV
  . "$CT/libexec/claude-code/env.sh"
  CC_TREE="$CT"
  CLAUDE_ENV_FILE="$U"
  cc_setup_env
  . "$TB/libexec/claude-code/env.sh"
  CC_TREE="$TB"
  cc_setup_env
  printf '%s|%s' "$CLAUDE_ENV_FILE" "${MAVERGREEN_USER_CLAUDE_ENV_FILE-}"
)"
h_assert_eq "$BE|$U" "$out" "a launch from another tree, nested in ours, keeps the user's env file"
nest_file="${out%%|*}" nest_user="${out#*|}"
for sh in $cshells; do
  for form in shape dotted; do
    rm -f "$H/my env/count"
    rc=0; out="$($form "$sh" "$nest_file" "$H/snap-plain" "echo \$CC_T" "$nest_user")" || rc=$?
    h_assert_eq "0|user" "$rc|$out" "[$sh $form] a two-tree nest chains to the user's env file"
    h_assert_eq "1" "$(count)" "[$sh $form] a two-tree nest sources the user's env file once"
  done
done

many="$(awk 'BEGIN { for (i = 1; i <= 5000; i++) printf "a%d ", i }')"
t0=0; [ ! -x "$PERL" ] || t0=$(now)
rc=0
# shellcheck disable=SC2086
"$SB/env" true $many || rc=$?
t1=0; [ ! -x "$PERL" ] || t1=$(now)
h_assert_eq "0" "$rc" "env true with 5000 arguments succeeds"
if [ -x "$PERL" ]; then
  h_assert_eq "0" "$("$PERL" -e "print(($t1 - $t0) > 10 ? 1 : 0)")" "env true with 5000 arguments takes under 10s, not the minute a quadratic scan took ($t0 to $t1)"
fi
# shellcheck disable=SC2086
h_assert_eq "5000" "$(A=a "$SB/env" -u A sh -c 'echo $#' sh $many)" "env -u passes 5000 arguments through"
# shellcheck disable=SC2086
h_assert_eq "unset 5000" "$(A=a "$SB/env" -i -u A sh -c 'echo ${A-unset} $#' sh $many)" "env -i -u passes 5000 arguments through"
