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

# --- xargs
platform xargs "Mac OS X 10.9's xargs has no -r; it already skips the command when input is empty"
same xargs "" "rc=0" "-r with empty input runs nothing" -r echo RAN
same xargs "a b${NL}" "RAN a b${NL}rc=0" "-r with input runs the command" -r echo RAN
same xargs "" "rc=0" "--no-run-if-empty with empty input runs nothing" --no-run-if-empty echo RAN
same xargs "a b${NL}" "RAN a${NL}RAN b${NL}rc=0" "-r combines with -n 1" -r -n 1 echo RAN
same xargs "a b${NL}" "RAN a${NL}RAN b${NL}rc=0" "-rn1 combines" -rn1 echo RAN
same xargs "a${NL}" "-r a${NL}rc=0" "an -r after the command is the command's" echo -r
same xargs "a${NL}" "a${NL}rc=0" "no options passes through" echo

# --- tac
platform tac "Mac OS X 10.9 has no tac"
same tac "1${NL}2${NL}3${NL}" "3${NL}2${NL}1${NL}rc=0" "reverses stdin"
same tac "1${NL}2${NL}3" "32${NL}1${NL}rc=0" "a last line without a newline comes first, as GNU does"
printf 'a\nb\n' > t1; printf 'c\nd\n' > t2
same tac "" "b${NL}a${NL}d${NL}c${NL}rc=0" "reverses each file in turn" t1 t2
same tac "x${NL}y${NL}" "b${NL}a${NL}y${NL}x${NL}rc=0" "- is stdin" t1 -
same tac "" "rc=0" "an empty input gives nothing"
shim tac "" "tac: nonexistent: No such file or directory${NL}rc=1" "a missing file fails" nonexistent
shim tac "" "tac: -s is not supported${NL}rc=1" "options are refused" -s x

# --- readlink
platform readlink "Mac OS X 10.9's readlink has no -f, -e or -m"
W="$H/w"
mkdir -p "$W/d/sub"
: > "$W/d/file"
ln -s d/file "$W/lf"
ln -s ../../d "$W/d/sub/up"
ln -s lf "$W/l2"
ln -s loop1 "$W/loop2"; ln -s loop2 "$W/loop1"
ln -s nowhere "$W/dangling"
same readlink "" "$W/d/file${NL}rc=0" "-f follows a chain of links" -f l2
same readlink "" "$W/d/file${NL}rc=0" "-f resolves .. after a link" -f d/sub/up/sub/../file
same readlink "" "$W/d/new${NL}rc=0" "-f allows a missing last component" -f d/new
same readlink "" "$W/nowhere${NL}rc=0" "-f follows a dangling link to its missing target" -f dangling
same readlink "" "rc=1" "-f fails quietly on a missing directory" -f nodir/new
same readlink "" "rc=1" "-e fails on a missing last component" -e d/new
same readlink "" "$W/d/file${NL}rc=0" "-e resolves an existing path" -e lf
same readlink "" "$W/nodir/new${NL}rc=0" "-m needs nothing to exist" -m nodir/new
same readlink "" "$W/d${NL}rc=0" "-f on a directory, trailing slash" -f d/
same readlink "" "/${NL}rc=0" "-f /" -f /
same readlink "" "rc=1" "-f fails on a loop" -f loop1
same readlink "" "$W/d/filerc=0" "-n -f prints no newline" -n -f lf
same readlink "" "$W/d/file${NL}$W/d${NL}rc=0" "-f takes several files" -f lf d
same readlink "" "d/file${NL}rc=0" "no option prints the link itself" lf
same readlink "" "rc=1" "no option on a non-link fails" d/file

# --- realpath
platform realpath "Mac OS X 10.9 has no realpath"
same realpath "" "$W/d/file${NL}rc=0" "follows links" l2
same realpath "" "$W/d/new${NL}rc=0" "allows a missing last component" d/new
same realpath "" "$W/lf${NL}rc=0" "-s does not follow links" -s lf
same realpath "" "$W/d/file${NL}rc=0" "-e resolves an existing path" -e lf
same realpath "" "$W/nodir/new${NL}rc=0" "-m needs nothing to exist" -m nodir/new
same realpath "" "rc=1" "-q fails quietly" -q nodir/new
same realpath "" "$W${NL}rc=0" "." .
shim realpath "" "realpath: nodir/new: No such file or directory${NL}rc=1" "a missing directory fails" nodir/new
shim realpath "" "realpath: d/new: No such file or directory${NL}rc=1" "-e fails on a missing last component" -e d/new
shim realpath "" "realpath: loop1: Too many levels of symbolic links${NL}rc=1" "a loop fails" loop1
shim realpath "" "realpath: d/file/x: Not a directory${NL}rc=1" "a file used as a directory fails" d/file/x
shim realpath "" "realpath: missing operand${NL}rc=1" "no operand fails"
shim realpath "" "$W/d/file${NL}realpath: nodir/x: No such file or directory${NL}$W/d${NL}rc=1" "carries on after a failure" lf nodir/x d

# --- head
platform head "Mac OS X 10.9's head refuses a count of 0, a negative count, and GNU's long options"
L4="1${NL}2${NL}3${NL}4${NL}"
same head "$L4" "rc=0" "-0 prints nothing" -0
same head "$L4" "rc=0" "-n 0 prints nothing" -n 0
same head "$L4" "rc=0" "-c 0 prints nothing" -c 0
same head "$L4" "1${NL}2${NL}rc=0" "-n -2 prints all but the last 2 lines" -n -2
same head "$L4" "1${NL}2${NL}rc=0" "-n-2 prints all but the last 2 lines" -n-2
same head "1${NL}2" "1${NL}rc=0" "-n -1 with no final newline" -n -1
same head "abcdef" "abcdrc=0" "-c -2 prints all but the last 2 bytes" -c -2
same head "$L4" "rc=0" "-n -9 of a shorter input prints nothing" -n -9
same head "$L4" "1${NL}rc=0" "--lines=1" --lines=1
same head "$L4" "1${NL}rc=0" "--lines 1" --lines 1
same head "$L4" "1${NL}2rc=0" "--bytes=3" --bytes=3
printf '1\n2\n' > h1; printf '3\n4\n' > h2
same head "" "==> h1 <==${NL}${NL}==> h2 <==${NL}rc=0" "-0 with two files prints their headers" -0 h1 h2
same head "" "==> h1 <==${NL}1${NL}${NL}==> h2 <==${NL}3${NL}rc=0" "-n -1 with two files" -n -1 h1 h2
same head "" "1${NL}3${NL}rc=0" "-q drops the headers" -q -n 1 h1 h2
same head "" "==> h1 <==${NL}1${NL}rc=0" "-v adds a header" -v -n 1 h1
same head "x${NL}" "==> standard input <==${NL}x${NL}rc=0" "-v names stdin" -v -n 1
same head "$L4" "1${NL}2${NL}rc=0" "-2 passes through" -2
same head "$L4" "1${NL}2${NL}3${NL}rc=0" "-n 3 passes through" -n 3
shim head "" "head: nonexistent: No such file or directory${NL}rc=1" "-n -1 with a missing file fails" -n -1 nonexistent
