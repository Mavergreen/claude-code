#!/bin/sh
# platform: macOS-only -- tests/manual/search-check.sh checks Claude Code's built-in tools on Mac OS X 10.9
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
SC="$H_REPO/tests/manual/search-check.sh"
mkdir -p "$H/bin2" "$H/out"
printf '#!/bin/sh\nexit 0\n' > "$H/claude"; chmod +x "$H/claude"
ln -s "$H/claude" "$H/bin2/rg"
printf '#!/bin/sh\nexit 0\n' > "$H/bin2/real-rg"; chmod +x "$H/bin2/real-rg"

for rg in "$H/claude" "$H/bin2/rg"; do
  rc=0; err="$(SEARCH_CHECK_RG="$rg" sh "$SC" "$H/claude" "$H/out" 2>&1)" || rc=$?
  h_assert_eq "2" "$rc" "an rg that is the binary under test ($rg) is refused: comparing the built-in rg with itself always agrees"
  h_assert_contains "$err" "is the binary under test" "the refusal says why"
done
rc=0; err="$(SEARCH_CHECK_RG="$H/bin2/real-rg" SEARCH_CHECK_UGREP=/nonexistent/ugrep sh "$SC" "$H/claude" "$H/out" 2>&1)" || rc=$?
case "$err" in *"is the binary under test"*) got=refused ;; *) got=accepted ;; esac
h_assert_eq "accepted" "$got" "a different rg gets past the check (the run then stops at the missing ugrep): $err"
