#!/bin/sh
# platform: macOS-only -- the shims give Claude Code's Bash tool on Mac OS X 10.9 the GNU and modern-macOS behaviors its tools lack
#   Each case states the expected output; when pkgsrc's GNU tool is installed, it is checked against that too.
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
SB="$H/root/usr/local/mavergreen/claude-code/libexec/claude-code/shell-bin"
NL='
'
mkdir -p "$H/w"
cd "$H/w"

gnu() {
  for _g in "/opt/pkg/bin/g$1" "/opt/pkg/gnu/bin/$1"; do
    if [ -x "$_g" ]; then printf '%s\n' "$_g"; return 0; fi
  done
}
# same TOOL INPUT WANT LABEL ARG... -- runs the shim (and the GNU oracle, if any) with INPUT on stdin;
# WANT is the output, stdout and stderr together, followed by "rc=N".
same() {
  _st=$1 _si=$2 _sw=$3 _sl=$4; shift 4
  _so="$(set +e; printf '%s' "$_si" | "$SB/$_st" "$@" 2>&1; echo "rc=$?")"
  h_assert_eq "$_sw" "$_so" "$_st shim: $_sl"
  _sg="$(gnu "$_st")"
  if [ -n "$_sg" ]; then
    _so="$(set +e; printf '%s' "$_si" | "$_sg" "$@" 2>&1; echo "rc=$?")"
    h_assert_eq "$_sw" "$_so" "GNU $_st oracle: $_sl"
  fi
}
# shim TOOL INPUT WANT LABEL ARG... -- the shim alone, for cases where GNU differs on purpose or prints its own wording.
shim() {
  _st=$1 _si=$2 _sw=$3 _sl=$4; shift 4
  _so="$(set +e; printf '%s' "$_si" | "$SB/$_st" "$@" 2>&1; echo "rc=$?")"
  h_assert_eq "$_sw" "$_so" "$_st shim: $_sl"
}
platform() { h_assert_eq "# platform: macOS-only -- $2" "$(sed -n 2p "$SB/$1")" "$1 declares its platform"; }

# --- base64
platform base64 "Mac OS X 10.9's base64 decodes with -D; its -d means debug, and re-encodes"
same base64 'hi' "aGk=${NL}rc=0" "encodes"
same base64 'aGkK' "hi${NL}rc=0" "-d decodes" -d
same base64 'aGkK' "hi${NL}rc=0" "--decode decodes" --decode
shim base64 'aGkK' "hi${NL}rc=0" "-D still decodes" -D
same base64 "aGVsbG8gd29y${NL}bGQK${NL}" "hello world${NL}rc=0" "-d decodes input wrapped across lines" -d
printf 'aGkK' > b64
same base64 '' "hi${NL}rc=0" "-d FILE decodes the file" -d b64
same base64 'aGkK' "hi${NL}rc=0" "-d - decodes stdin" -d -
same base64 'abcdefghij' "YWJj${NL}ZGVm${NL}Z2hp${NL}ag==${NL}rc=0" "-w N wraps at N" -w 4
same base64 'abcdefghij' "YWJj${NL}ZGVm${NL}Z2hp${NL}ag==${NL}rc=0" "--wrap=N wraps at N" --wrap=4
same base64 'abcdefghijkl' "YWJj${NL}ZGVm${NL}Z2hp${NL}amts${NL}rc=0" "-w N with an exact multiple" -w 4
same base64 'abcdefghij' "YWJjZGVmZ2hpag==rc=0" "-w 0 does not wrap, or end the line" -w 0
same base64 'abcdefghij' "YWJjZGVmZ2hpag==rc=0" "-w0 does not wrap" -w0
printf 'abcdefghij' > b64w
same base64 '' "YWJjZGVmZ2hpag==rc=0" "-w 0 FILE encodes the file" -w 0 b64w
shim base64 '' "base64: nonexistent: No such file or directory${NL}rc=1" "-d with a missing file fails" -d nonexistent
shim base64 '' "hi${NL}rc=0" "-d -i FILE decodes, with 10.9's -i" -d -i b64
shim base64 'aGkK' "rc=0" "-d -o FILE decodes into FILE, with 10.9's -o" -d -o b64out
h_assert_eq "hi" "$(cat b64out)" "base64 shim: -d -o FILE wrote FILE"

# --- paste
platform paste "Mac OS X 10.9's paste needs a file operand, where GNU reads stdin"
same paste "a${NL}b${NL}c${NL}" "a,b,c${NL}rc=0" "-sd, with no file reads stdin" -sd,
same paste "a${NL}b${NL}c${NL}" "a+b+c${NL}rc=0" "-s -d + with no file reads stdin" -s -d +
same paste "a${NL}b${NL}" "a${NL}b${NL}rc=0" "no options and no file reads stdin"
printf '1\n2\n' > p1
same paste "x${NL}y${NL}" "1	x${NL}2	y${NL}rc=0" "file operands pass through" p1 -
same paste "" "1,2${NL}rc=0" "-s -d, FILE passes through" -s -d, p1
