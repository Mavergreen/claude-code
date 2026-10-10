#!/bin/sh
# platform: macOS-only -- drives packaging/install.sh, which reads plists with 10.9's /usr/libexec/PlistBuddy
set -eu
. "$(dirname "$0")/lib/harness.sh"
[ -x /usr/libexec/PlistBuddy ] || exit 77
h_setup
I="$H_REPO/packaging/install.sh"
REL="$H/rel"
mkdir -p "$H/tmp"
MAVERGREEN_RELEASES="file://$(printf %s "$REL" | sed "s/%/%25/g; s/ /%20/g; s/#/%23/g; s/?/%3F/g")"
MAVERGREEN_INSTALL_ROOT="$H/root"
TMPDIR="$H/tmp/"
export MAVERGREEN_RELEASES MAVERGREEN_INSTALL_ROOT TMPDIR

cat > "$H/bin/sudo" <<'SUDO'
#!/bin/sh
if [ "$*" = "-v" ]; then echo "sudo -v" >> "$H/run.log"; exit 0; fi
if [ "$1" = /usr/sbin/installer ] && [ "$2" = -pkg ] && [ "$4" = -target ] && [ "$5" = / ] && [ $# -eq 5 ]; then
  [ -f "$3" ] || { echo "missing $3" >> "$H/run.log"; exit 1; }
  case "$3" in "$H/tmp/"*) ;; *) echo "outside the temp dir: $3" >> "$H/run.log"; exit 1 ;; esac
  echo "install $(basename "$3") $(cat "$3")" >> "$H/run.log"
  exit 0
fi
echo "unexpected sudo $*" >> "$H/run.log"
exit 1
SUDO
cat > "$H/bin/sw_vers" <<'SW'
#!/bin/sh
[ "$*" = "-productVersion" ] || exit 1
printf '%s\n' "${H_OSVER-10.9.5}"
SW
cat > "$H/bin/uname" <<'UN'
#!/bin/sh
case "$*" in
  -s) printf '%s\n' "${H_KERNEL-Darwin}" ;;
  -m) printf '%s\n' "${H_ARCH-x86_64}" ;;
  *) exec /usr/bin/uname "$@" ;;
esac
UN
cat > "$H/bin/installer" <<'INS'
#!/bin/sh
echo "installer reached without sudo: $*" >> "$H/run.log"
exit 1
INS
chmod +x "$H/bin/sudo" "$H/bin/sw_vers" "$H/bin/uname" "$H/bin/installer"
hash -r

pub() {
  _d="$REL/$1/releases/latest/download"
  mkdir -p "$_d"
  shift
  for _a in "$@"; do printf 'payload %s\n' "$_a" > "$_d/$_a"; done
  (cd "$_d" && shasum -a 256 "$@" > SHA256SUMS)
}
release_all() {
  rm -rf "$REL"
  pub avxemu avxemu-20261005.1.pkg
  pub recaulk recaulk-20261006.1.pkg
  pub clang-22 mavericks-clang-22-native-22.1.1-mavericks.7.pkg libcxx22-22.1.1-mavericks.7.pkg mavericks-clang-22-cross-22.1.1-mavericks.7.pkg clang22.xml clang22-cross.xml
  pub icu icu-78.3-mavericks.1.pkg
  pub claude-code claude-code-20261007.1.pkg claude-code.xml install.sh
}
installed() {
  _p="$MAVERGREEN_INSTALL_ROOT/usr/local/mavergreen/$1/mavergreen.plist"
  mkdir -p "$(dirname "$_p")"
  rm -f "$_p"
  /usr/libexec/PlistBuddy -c "Add :version string $2" "$_p" >/dev/null
}
fresh() {
  rm -rf "$MAVERGREEN_INSTALL_ROOT/usr/local/mavergreen" "$H/run.log"
  : > "$H/run.log"
  release_all
}
run() { rc=0; out="$(sh "$I" 2>&1)" || rc=$?; log="$(cat "$H/run.log")"; last="$(printf '%s\n' "$out" | tail -n 1)"; }
DONE="Claude Code for Mavericks: done. Open a new Terminal window, then run claude."
tmp_left() { ls -A "$H/tmp"; }

ALL="sudo -v
install avxemu-20261005.1.pkg payload avxemu-20261005.1.pkg
install recaulk-20261006.1.pkg payload recaulk-20261006.1.pkg
install libcxx22-22.1.1-mavericks.7.pkg payload libcxx22-22.1.1-mavericks.7.pkg
install icu-78.3-mavericks.1.pkg payload icu-78.3-mavericks.1.pkg
install claude-code-20261007.1.pkg payload claude-code-20261007.1.pkg"

fresh; run
h_assert_eq 0 "$rc" "a fresh install succeeds: $out"
h_assert_eq "$ALL" "$log" "installs all five, in order, after one sudo -v"
h_assert_eq "$DONE" "$last" "ends saying to open a new Terminal window, then run claude"
h_assert_eq "" "$(tmp_left)" "the temp dir is removed after success"

fresh; installed recaulk 20261006.1; installed icu 78.2-mavericks.3; run
h_assert_eq 0 "$rc" "an update succeeds: $out"
h_assert_eq "sudo -v
install avxemu-20261005.1.pkg payload avxemu-20261005.1.pkg
install libcxx22-22.1.1-mavericks.7.pkg payload libcxx22-22.1.1-mavericks.7.pkg
install icu-78.3-mavericks.1.pkg payload icu-78.3-mavericks.1.pkg
install claude-code-20261007.1.pkg payload claude-code-20261007.1.pkg" "$log" "skips the product whose manifest records the release's version"
h_assert_contains "$out" "recaulk 20261006.1" "names the product it skips"

fresh
installed avxemu 20261005.1; installed recaulk 20261006.1; installed libcxx22 22.1.1-mavericks.7
installed icu 78.3-mavericks.1; installed claude-code 20261007.1
run
h_assert_eq 0 "$rc" "an up-to-date system succeeds: $out"
h_assert_eq "" "$log" "nothing to install asks for no password"
h_assert_eq "$DONE" "$last" "an up-to-date run still ends saying what to do next"

fresh; H_OSVER=10.8.5; export H_OSVER; run; unset H_OSVER
h_assert_eq 1 "$rc" "refuses 10.8"
h_assert_contains "$out" "Mac OS X 10.9.5 is required" "the 10.8 refusal says 10.9.5 is required"
h_assert_contains "$out" "10.8.5" "the 10.8 refusal names the running version"
h_assert_eq "" "$log" "refusing 10.8 runs nothing"

fresh; H_OSVER=10.10.5; export H_OSVER; run; unset H_OSVER
h_assert_eq 1 "$rc" "refuses 10.10"

for _v in 10.9 10.9.4 10.9.0; do
  fresh; H_OSVER=$_v; export H_OSVER; run; unset H_OSVER
  h_assert_eq 1 "$rc" "refuses $_v"
  h_assert_contains "$out" "Mac OS X 10.9.5 is required" "the $_v refusal says 10.9.5 is required"
  h_assert_eq "" "$log" "refusing $_v runs nothing"
done

fresh; H_OSVER=10.9.5; export H_OSVER; run; unset H_OSVER
h_assert_eq 0 "$rc" "accepts 10.9.5: $out"

fresh; H_CPU_FEATURES=" FPU VME SSE4.2 "; export H_CPU_FEATURES; run; unset H_CPU_FEATURES
h_assert_eq 1 "$rc" "refuses a CPU without AVX"
h_assert_contains "$out" "Your CPU has no AVX support. This machine is too old to run Claude Code." "the AVX refusal keeps its wording"
h_assert_eq "" "$log" "refusing a CPU without AVX runs nothing"

fresh; H_CPU_FEATURES=""; export H_CPU_FEATURES; run; unset H_CPU_FEATURES
h_assert_eq 1 "$rc" "refuses when the CPU features are unreadable"
h_assert_contains "$out" "could not read this Mac's CPU features" "unreadable features get their own message"
case "$out" in *"no AVX"*) h_assert_eq "no AVX message" "$out" "unreadable features are not reported as no AVX" ;; esac
h_assert_eq "" "$log" "unreadable CPU features run nothing"

fresh
mkdir -p "$MAVERGREEN_INSTALL_ROOT/usr/local/mavergreen/avxemu" "$MAVERGREEN_INSTALL_ROOT/usr/local/mavergreen/icu"
: > "$MAVERGREEN_INSTALL_ROOT/usr/local/mavergreen/avxemu/mavergreen.plist"
/usr/libexec/PlistBuddy -c "Add :name string icu" "$MAVERGREEN_INSTALL_ROOT/usr/local/mavergreen/icu/mavergreen.plist" >/dev/null
run
h_assert_eq 0 "$rc" "an empty or versionless manifest does not stop the install: $out"
h_assert_eq "$ALL" "$log" "an empty or versionless manifest counts as not installed"

cat > "$H/bin/curl" <<'CURL'
#!/bin/sh
echo "$*" >> "$H/curl.log"
exec /usr/bin/curl "$@"
CURL
chmod +x "$H/bin/curl"; hash -r
fresh; : > "$H/curl.log"; run
h_assert_eq 0 "$rc" "install with a logging curl succeeds: $out"
_n="$(grep -c . "$H/curl.log" || :)"; _p="$(grep -c -F -e '--proto-redir =https' "$H/curl.log" || :)"
h_assert_ok test "$_n" -ge 10
h_assert_eq "$_n" "$_p" "every curl call restricts redirects to https"
rm "$H/bin/curl"; hash -r

fresh; H_KERNEL=Linux; export H_KERNEL; run; unset H_KERNEL
h_assert_eq 1 "$rc" "refuses a kernel other than Darwin"
h_assert_contains "$out" "only macOS is supported" "the kernel refusal keeps its wording"

fresh; H_ARCH=i386; export H_ARCH; run; unset H_ARCH
h_assert_eq 1 "$rc" "refuses a 32-bit Mac"
h_assert_contains "$out" "unsupported arch: i386" "the arch refusal keeps its wording"

fresh; printf 'tampered\n' > "$REL/icu/releases/latest/download/icu-78.3-mavericks.1.pkg"; run
h_assert_eq 1 "$rc" "a checksum mismatch fails"
h_assert_contains "$out" "icu-78.3-mavericks.1.pkg" "the mismatch names the pkg"
h_assert_eq "" "$log" "a checksum mismatch is found before anything is installed"
h_assert_eq "" "$(tmp_left)" "the temp dir is removed after a failure"

fresh
_d="$REL/clang-22/releases/latest/download"
printf 'payload old\n' > "$_d/libcxx22-22.1.1-mavericks.6.pkg"
(cd "$_d" && shasum -a 256 libcxx22-22.1.1-mavericks.6.pkg >> SHA256SUMS)
run
h_assert_eq 1 "$rc" "a release with two matching pkgs fails"
h_assert_contains "$out" "clang-22" "the failure names the repo"
h_assert_eq "" "$log" "two matching pkgs install nothing"

fresh
_d="$REL/recaulk/releases/latest/download"
(cd "$_d" && shasum -a 256 SHA256SUMS > SHA256SUMS.new && mv SHA256SUMS.new SHA256SUMS)
run
h_assert_eq 1 "$rc" "a release with no matching pkg fails"
h_assert_contains "$out" "recaulk" "the failure names the repo"
h_assert_eq "" "$log" "no matching pkg installs nothing"

fresh
_d="$REL/recaulk/releases/latest/download"
printf '%s extra\n' "$(cat "$_d/SHA256SUMS")" > "$_d/SHA256SUMS.new"; mv "$_d/SHA256SUMS.new" "$_d/SHA256SUMS"
run
h_assert_eq 1 "$rc" "a SHA256SUMS line with an extra field does not match"
h_assert_contains "$out" "recaulk" "the failure names the repo"
h_assert_eq "" "$log" "an extra-field line installs nothing"

fresh; rm "$REL/icu/releases/latest/download/SHA256SUMS"; run
h_assert_eq 1 "$rc" "a release without SHA256SUMS fails"
h_assert_contains "$out" "icu" "the failure names the repo"
h_assert_eq "" "$log" "a missing SHA256SUMS installs nothing"
h_assert_eq "" "$(tmp_left)" "the temp dir is removed after a fetch failure"

fresh
rc=0; out="$(cat "$I" | sh 2>&1)" || rc=$?; log="$(cat "$H/run.log")"; last="$(printf '%s\n' "$out" | tail -n 1)"
h_assert_eq 0 "$rc" "works when piped into sh: $out"
h_assert_eq "$ALL" "$log" "piped into sh, installs all five in order"
h_assert_eq "$DONE" "$last" "piped into sh, ends saying what to do next"
h_assert_eq "" "$(tmp_left)" "piped into sh, the temp dir is removed"

W="$H_REPO/.github/workflows/release.yml"
_wc="$(grep -n -F 'cp packaging/install.sh "$BUILD/dist/install.sh"' "$W" | head -n 1 | cut -d: -f1)"
_wp="$(grep -n -F 'sh packaging/verify-pkg.sh' "$W" | head -n 1 | cut -d: -f1)"
_wn="$(grep -n -F -- '- name: Release notes' "$W" | head -n 1 | cut -d: -f1)"
h_assert_ok test "${_wp:-99}" -lt "${_wc:-0}"
h_assert_ok test "${_wc:-99}" -lt "${_wn:-0}"
