#!/bin/sh
# platform: macOS-only -- the computer-use server drives the system Python 2.7 and PyObjC of Mac OS X 10.9
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
CU="$H/root/usr/local/mavergreen/claude-code/share/claude-code"
SERVER="/usr/local/mavergreen/claude-code/share/claude-code/computer-use/mcp_server.py"

h_assert_ok test -x "$CU/computer-use/mcp_server.py"
h_assert_ok test -f "$CU/computer-use/cu_actions.py"

for f in mcp_server.py cu_actions.py; do
  want="$(grep "^| \`$f\` |" "$H_REPO/PROVENANCE.md" | cut -d'|' -f4 | tr -d '` ')"
  got="$(shasum -a 256 "$CU/computer-use/$f" | cut -d' ' -f1)"
  h_assert_eq "$want" "$got" "$f matches the hash committed in PROVENANCE.md"
done

P27=""
if [ -x /usr/bin/python2.7 ]; then P27=/usr/bin/python2.7
elif command -v python2.7 >/dev/null 2>&1; then P27="$(command -v python2.7)"; fi
if [ -n "$P27" ]; then PY="$P27"
elif command -v python3 >/dev/null 2>&1; then PY=python3
else PY=""; fi

jget() { "$PY" -c 'import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2:]:
    d=d[int(k)] if isinstance(d,list) else d[k]
print(d)' "$@"; }

if [ -n "$PY" ]; then
  h_assert_ok "$PY" -c 'import json,sys;json.load(open(sys.argv[1]))' "$CU/mcp-config.json"
  h_assert_ok "$PY" -c 'import json,sys;json.load(open(sys.argv[1]))' "$CU/settings.json"
  h_assert_eq "$SERVER" "$(jget "$CU/mcp-config.json" mcpServers computer-use-mavericks command)" "server command is the fixed path"
  h_assert_eq stdio "$(jget "$CU/mcp-config.json" mcpServers computer-use-mavericks type)" "server type"
  h_assert_eq "[]" "$(jget "$CU/mcp-config.json" mcpServers computer-use-mavericks args)" "server args"
  h_assert_eq "{}" "$(jget "$CU/mcp-config.json" mcpServers computer-use-mavericks env)" "server env"
  h_assert_eq "mcp__computer-use-mavericks" "$(jget "$CU/settings.json" permissions allow 0)" "settings allows the server"
else
  echo "SKIP: no python, so mcp-config.json and settings.json are not parsed or checked" >&2
fi

if [ -n "$P27" ]; then
  mkdir -p "$H/pyc"
  for f in mcp_server.py cu_actions.py; do
    h_assert_ok "$P27" -c 'import sys,py_compile;py_compile.compile(sys.argv[1],cfile=sys.argv[2],doraise=True)' "$CU/computer-use/$f" "$H/pyc/$f.pyc"
  done
else
  echo "SKIP: no python2.7, so mcp_server.py and cu_actions.py are not compiled" >&2
fi
