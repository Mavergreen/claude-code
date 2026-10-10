#!/bin/sh
# platform: macOS-only -- the launcher targets Mac OS X 10.9's sh and tools
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
MG="$H/root/usr/local/mavergreen"
TREE="$MG/claude-code"
mkdir -p "$MG/bin"
ln -s "$TREE/bin/claude" "$MG/bin/claude"
mkdir -p "$HOME/.local/share/claude-mavericks"
h_fake_drydock
h_cdn_publish 2.1.289
h_cdn_latest 2.1.289
export DISABLE_AUTOUPDATER=1
unset USE_BUILTIN_RIPGREP CLAUDE_ENV_FILE MAVERGREEN_USER_CLAUDE_ENV_FILE DYLD_INSERT_LIBRARIES 2>/dev/null || :

run() { "$HOME/.local/bin/claude" "$@" 2>&1 || echo "exit:$?"; }

args() { printf '%s\n' "$1" | grep '^arg:' || :; }
out="$("$MG/bin/claude" mcp list 2>&1 || echo "exit:$?")"
h_assert_eq "$(readlink "$HOME/.local/bin/claude")" "$MG/bin/claude" "launch claimed the link"
h_assert_eq "no" "$([ -e "$HOME/.local/share/claude-mavericks" ] && echo yes || echo no)" "launch ran takeover"
want="$(printf 'arg:--allowedTools=Grep\narg:--settings=%s\narg:--mcp-config=%s\narg:mcp\narg:list' "$TREE/share/claude-code/settings.json" "$TREE/share/claude-code/mcp-config.json")"
h_assert_eq "$want" "$(args "$out")" "argv exactly, order and count"
out="$(run mcp list)"
h_assert_eq "$want" "$(args "$out")" "argv exactly via the link chain"
mkdir -p "$H/decoy/bin"
out="$(cd "$TREE" && CDPATH="$H/decoy" bin/claude mcp list 2>&1 || echo "exit:$?")"
h_assert_eq "$want" "$(args "$out")" "relative invocation ignores an exported CDPATH"
out="$(run "a b" "" --)"
h_assert_eq "$(printf 'arg:--allowedTools=Grep\narg:--settings=%s\narg:--mcp-config=%s\narg:a b\narg:\narg:--' "$TREE/share/claude-code/settings.json" "$TREE/share/claude-code/mcp-config.json")" "$(args "$out")" "user arguments pass verbatim"
mkv() { mkdir -p "$HOME/.local/share/claude/versions"; printf '#!/bin/sh\n' > "$HOME/.local/share/claude/versions/$1"; chmod +x "$HOME/.local/share/claude/versions/$1"; }
mkv 2.1.270
mkv 2.1.275
out="$(run x)"
h_assert_fails test -e "$HOME/.local/share/claude/versions/2.1.270"
h_assert_ok test -e "$HOME/.local/share/claude/versions/2.1.275"
h_assert_contains "$out" "env:JSC_numberOfGCMarkers=1" "JSC env"
h_assert_contains "$out" "env:DISABLE_INSTALLATION_CHECKS=1" "installation checks env"
h_assert_contains "$out" "env:USE_BUILTIN_RIPGREP=
" "ripgrep var not set"
OURS="$TREE/share/claude-code/claude-env.sh"
h_assert_contains "$out" "env:CLAUDE_ENV_FILE=$OURS
" "the env file is ours"
h_assert_contains "$out" "env:MAVERGREEN_USER_CLAUDE_ENV_FILE
" "no user env file is saved when none was inherited"
h_assert_ok test -d "$HOME/Library/Caches"

out="$(CLAUDE_ENV_FILE="$H/my env" run x)"
h_assert_contains "$out" "env:CLAUDE_ENV_FILE=$OURS
" "an inherited CLAUDE_ENV_FILE is replaced by ours"
h_assert_contains "$out" "env:MAVERGREEN_USER_CLAUDE_ENV_FILE=$H/my env
" "an inherited CLAUDE_ENV_FILE is saved for ours to chain to"
out="$(cd "$H" && CLAUDE_ENV_FILE="my env" run x)"
h_assert_contains "$out" "env:MAVERGREEN_USER_CLAUDE_ENV_FILE=$H/my env
" "a relative inherited CLAUDE_ENV_FILE is saved as an absolute path"
out="$(CLAUDE_ENV_FILE="$OURS" MAVERGREEN_USER_CLAUDE_ENV_FILE="$H/my env" run x)"
h_assert_contains "$out" "env:CLAUDE_ENV_FILE=$OURS
" "a nested launch keeps ours"
h_assert_contains "$out" "env:MAVERGREEN_USER_CLAUDE_ENV_FILE=$H/my env
" "a nested launch keeps the saved user env file"
cp -R "$TREE" "$H/tree b"
out="$(CLAUDE_ENV_FILE="$H/tree b/share/claude-code/claude-env.sh" MAVERGREEN_USER_CLAUDE_ENV_FILE="$H/my env" run x)"
h_assert_contains "$out" "env:CLAUDE_ENV_FILE=$OURS
" "a launch nested in another tree's session uses ours"
h_assert_contains "$out" "env:MAVERGREEN_USER_CLAUDE_ENV_FILE=$H/my env
" "a launch nested in another tree's session keeps the user's env file, not that tree's"
UL="$HOME/.local/share/claude-code/claude-env.sh"
out="$(CLAUDE_ENV_FILE="$UL" run x)"
h_assert_contains "$out" "env:CLAUDE_ENV_FILE=$OURS
" "a user env file at a path like a tree's is replaced by ours"
h_assert_contains "$out" "env:MAVERGREEN_USER_CLAUDE_ENV_FILE=$UL
" "a user env file at a path like a tree's, with no tree's shell-bin beside it, is saved for ours to chain to"

pathof() { printf '%s' "${1##*env:PATH=}"; }
P0="$PATH"
CB="$TREE/libexec/claude-code/claude-bin"
out="$(run x)"
h_assert_eq "$CB:$P0:$HOME/.local/bin" "$(pathof "$out")" "absent: appended at the end"
out="$(PATH="$HOME/.local/bin:$P0" run x)"
h_assert_eq "$CB:$HOME/.local/bin:$P0" "$(pathof "$out")" "present: unchanged"
out="$(PATH="$HOME/.local/bin/../bin:$P0" run x)"
h_assert_eq "$CB:$HOME/.local/bin/../bin:$P0:$HOME/.local/bin" "$(pathof "$out")" "non-canonical entry is not equal"
ln -s "$HOME" "$H/homelink"
out="$(PATH="$H/homelink/.local/bin:$P0" run x)"
h_assert_eq "$CB:$H/homelink/.local/bin:$P0:$HOME/.local/bin" "$(pathof "$out")" "symlinked entry is not physical: physical appended"
out="$(HOME="$H/homelink" PATH="$P0:$H/home/.local/bin" run x)"
h_assert_eq "$CB:$P0:$H/home/.local/bin" "$(pathof "$out")" "non-canonical HOME: physical entry counts"
out="$(HOME="$H/homelink" PATH="$P0:$H/homelink/.local/bin" run x)"
h_assert_eq "$CB:$P0:$H/homelink/.local/bin" "$(pathof "$out")" "non-canonical HOME: literal entry counts"
out="$(HOME="$H/homelink" run x)"
h_assert_eq "$CB:$P0:$H/home/.local/bin" "$(pathof "$out")" "non-canonical HOME: physical path appended"
out="$(PATH="$HOME/.local/bi[n]:$P0" run x)"
h_assert_eq "$CB:$HOME/.local/bi[n]:$P0:$HOME/.local/bin" "$(pathof "$out")" "a glob-shaped entry is compared, not expanded"

out="$(PATH="$CB:$P0" run x)"
h_assert_eq "$CB:$P0:$HOME/.local/bin" "$(pathof "$out")" "claude-bin already first: not added again"
out="$(PATH="$P0:$CB" run x)"
h_assert_eq "$CB:$P0:$HOME/.local/bin" "$(pathof "$out")" "claude-bin elsewhere: moved first, once"

out="$(H_CPU_FEATURES=" FPU SSE4.2 " run x)"
h_assert_contains "$out" "AVX" "refuses without AVX1.0"
h_assert_contains "$out" "exit:1" "AVX refusal exits 1"
h_assert_fails sh -c "case \"\$1\" in *fake-claude*) exit 0;; esac; exit 1" x "$out"
out="$(H_CPU_FEATURES="" run x)"
h_assert_contains "$out" "could not read this Mac's CPU features" "an empty features answer is refused"
h_assert_contains "$out" "exit:1" "that refusal exits 1"
mkdir -p "$H/fakesbin"
cp "$H/bin/sysctl" "$H/fakesbin/sysctl"
out="$(PATH=/usr/bin:/bin CC_SBIN="$H/fakesbin" run x)"
h_assert_contains "$out" "fake-claude" "a PATH without sbin still finds sysctl"
out="$(PATH=/usr/bin:/bin CC_SBIN="$H/fakesbin" H_CPU_FEATURES=" FPU SSE4.2 " run x)"
h_assert_contains "$out" "lacks AVX" "the sysctl found that way is the one asked"

mv "$MG/fakert/mavergreen.plist" "$MG/fakert/p"
out="$(run x)"
h_assert_contains "$out" "fakert is not installed; get it from https://example.invalid/fakert/releases" "missing runtime"
h_assert_contains "$out" "exit:1" "missing runtime exits 1"
mv "$MG/fakert/p" "$MG/fakert/mavergreen.plist"
RQ="$TREE/share/claude-code/requires"
cp "$RQ" "$H/requires.orig"
printf "avxemu https://example.invalid/avxemu/releases\nfakert https://example.invalid/fakert/releases" > "$RQ"
mv "$MG/fakert/mavergreen.plist" "$MG/fakert/p"
out="$(run x)"
h_assert_contains "$out" "fakert is not installed; get it from https://example.invalid/fakert/releases" "requires line without a trailing newline is read"
mv "$MG/fakert/p" "$MG/fakert/mavergreen.plist"
rm "$RQ"
out="$(run x)"
h_assert_contains "$out" "missing $RQ" "missing requires file is named"
h_assert_contains "$out" "exit:1" "missing requires file exits 1"
cp "$H/requires.orig" "$RQ"

chmod -x "$TREE/share/claude-code/computer-use/mcp_server.py"
out="$(run mcp list)"
h_assert_contains "$out" "arg:--settings=" "settings still injected"
case "$out" in *"--mcp-config="*) h_assert_eq "no mcp-config" "$out" "non-executable server drops --mcp-config" ;; esac
chmod +x "$TREE/share/claude-code/computer-use/mcp_server.py"
rm "$TREE/share/claude-code/settings.json"
out="$(run mcp list)"
case "$out" in *"--settings="*) h_assert_eq "no settings" "$out" "absent settings.json drops --settings" ;; esac
h_assert_contains "$out" "arg:--allowedTools=Grep
arg:--mcp-config=" "order without settings"

(
  CC_MG="$MG"
  CC_TREE="$TREE"
  . "$TREE/libexec/claude-code/env.sh"
  AV="$MG/avxemu/lib/libavxemu.dylib"
  unset DYLD_INSERT_LIBRARIES
  cc_setup_env
  h_assert_eq "" "${DYLD_INSERT_LIBRARIES-}" "never inserts avxemu"
  DYLD_INSERT_LIBRARIES=/x.dylib; export DYLD_INSERT_LIBRARIES
  cc_setup_env
  h_assert_eq "/x.dylib" "$DYLD_INSERT_LIBRARIES" "a pre-set value is left alone"
  DYLD_INSERT_LIBRARIES="$AV"; export DYLD_INSERT_LIBRARIES
  cc_setup_env
  h_assert_eq "$AV" "$DYLD_INSERT_LIBRARIES" "a pre-set avxemu value is unchanged"
  unset DYLD_INSERT_LIBRARIES
  PATH=""
  cc_setup_env
  h_assert_eq "$CC_TREE/libexec/claude-code/claude-bin:$HOME/.local/bin" "$PATH" "empty PATH gains no empty entry"
  CLAUDE_ENV_FILE=""; export CLAUDE_ENV_FILE
  cc_setup_env
  h_assert_eq "$OURS" "$CLAUDE_ENV_FILE" "an empty inherited CLAUDE_ENV_FILE becomes ours"
  h_assert_eq "unset" "${MAVERGREEN_USER_CLAUDE_ENV_FILE-unset}" "an empty inherited CLAUDE_ENV_FILE is not saved"
  [ "$H_FAILS" -eq 0 ]
) || H_FAILS=$((H_FAILS+1))
(
  CC_MG="$MG"
  CC_TREE="$TREE"
  . "$TREE/libexec/claude-code/env.sh"
  unset DYLD_INSERT_LIBRARIES
  PATH=/usr/bin:/bin
  cc_setup_env
  h_assert_eq "" "${DYLD_INSERT_LIBRARIES-}" "cc_setup_env never inserts avxemu with PATH=/usr/bin:/bin"
  CC_TREE="$H/no tree"
  CLAUDE_ENV_FILE="$H/my env"; export CLAUDE_ENV_FILE
  unset MAVERGREEN_USER_CLAUDE_ENV_FILE
  cc_setup_env
  h_assert_eq "$H/my env" "$CLAUDE_ENV_FILE" "without our env file, an inherited CLAUDE_ENV_FILE is left alone"
  h_assert_eq "unset" "${MAVERGREEN_USER_CLAUDE_ENV_FILE-unset}" "without our env file, nothing is saved"
  unset CLAUDE_ENV_FILE
  cc_setup_env
  h_assert_eq "unset" "${CLAUDE_ENV_FILE-unset}" "without our env file, an unset CLAUDE_ENV_FILE stays unset"
  [ "$H_FAILS" -eq 0 ]
) || H_FAILS=$((H_FAILS+1))

nohold() { (unset DISABLE_AUTOUPDATER; "$HOME/.local/bin/claude" "$@"); }

VD="$HOME/.local/share/claude/versions"
install_cdn() { cp "$H/cdn/$1/darwin-x64/claude" "$VD/$1"; }
runs() { h_assert_contains "$1" "fake-claude $2" "$3"; }
for v in 2.1.284 2.1.285 2.1.288; do h_cdn_publish $v; done
rm -f "$VD"/*
for v in 2.1.284 2.1.285 2.1.288 2.1.289; do install_cdn $v; done
printf '2.1.285\n' > "$HOME/Library/Application Support/dev.mavergreen.claude-code/current"
out="$(DISABLE_AUTOUPDATER=1 "$HOME/.local/bin/claude" update 2>&1 || :)"
runs "$out" 2.1.285 "update under hold: recording launch stays on current"
out="$(DISABLE_AUTOUPDATER=1 "$HOME/.local/bin/claude" x 2>&1 || :)"
runs "$out" 2.1.289 "update is honoured at the next launch"

for v in 2.1.284 2.1.285 2.1.288 2.1.289; do install_cdn $v; done
runs "$(nohold install 2.1.285 2>&1 || :)" 2.1.289 "install of an installed older version: recording launch runs newest"
runs "$(nohold x 2>&1 || :)" 2.1.285 "next launch runs the installed older version"
h_assert_ok test -e "$VD/2.1.284"
runs "$(nohold x 2>&1 || :)" 2.1.289 "the one after is back on newest"
h_assert_fails test -e "$VD/2.1.284"

h_cdn_publish 2.1.287
runs "$(nohold install 2.1.287 2>&1 || :)" 2.1.289 "install of an absent version: recording launch runs newest"
install_cdn 2.1.287
runs "$(nohold x 2>&1 || :)" 2.1.287 "next launch runs the version Claude Code downloaded"
runs "$(nohold x 2>&1 || :)" 2.1.289 "then newest again"

rm -rf "$HOME/.local/share/claude" "$HOME/Library/Caches/dev.mavergreen.claude-code" "$HOME/Library/Application Support/dev.mavergreen.claude-code"
h_cdn_publish 2.1.280
h_cdn_publish 2.1.285
h_cdn_latest 2.1.280
out="$(nohold x 2>&1 || :)"
h_assert_contains "$out" "fake-claude 2.1.280" "280 built and run"
V="$HOME/.local/share/claude/versions"
cp "$H/cdn/2.1.285/darwin-x64/claude" "$V/2.1.285"
cp "$H/cdn/2.1.289/darwin-x64/claude" "$V/2.1.289"
printf '2.1.289\n' > "$H/drydock-refuses"
out="$(nohold x 2>&1 || :)"
h_assert_contains "$out" "fake-claude 2.1.280" "fallback runs the cached older entry"
h_assert_ok test -e "$V/2.1.280"
h_assert_ok test -e "$HOME/Library/Caches/dev.mavergreen.claude-code/2.1.280-$(cut -c1-16 "$TREE/share/claude-code/recipe-id")/claude"

ST="$HOME/Library/Application Support/dev.mavergreen.claude-code"
rm -rf "$V" "$HOME/Library/Caches/dev.mavergreen.claude-code" "$ST"
mkdir -p "$V"
for v in 2.1.288 2.1.289; do install_cdn $v; done
out="$(nohold install 2.1.288 2>&1 || echo "exit:$?")"
h_assert_contains "$out" "cannot run Claude Code 2.1.289" "install launch dies when newest cannot be patched"
h_assert_contains "$out" "exit:1" "that launch exits 1"
runs "$(nohold x 2>&1 || :)" 2.1.288 "the next launch still honours install 2.1.288"

rm -rf "$V" "$ST"
mv "$H/cdn/latest" "$H/latest.off"
out="$(nohold install 2.1.288 2>&1 || echo "exit:$?")"
h_assert_contains "$out" "exit:1" "install launch dies when nothing can be chosen"
h_assert_eq "install 2.1.288" "$(cat "$ST/repick" 2>/dev/null || :)" "the intent is still recorded"
mv "$H/latest.off" "$H/cdn/latest"

rm -rf "$V" "$ST" "$HOME/Library/Caches/dev.mavergreen.claude-code" "$H/drydock-refuses"
h_cdn_latest 2.1.289
runs "$(nohold x 2>&1 || :)" 2.1.289 "bootstrap records the checksum it verified"
cp "$TREE/share/claude-code/recipe" "$H/recipe.orig"
cp "$TREE/share/claude-code/recipe-id" "$H/recipe-id.orig"
mv "$H/cdn" "$H/cdn.off"
printf '# the next recipe\n' > "$TREE/share/claude-code/recipe"
shasum -a 256 "$TREE/share/claude-code/recipe" | cut -d' ' -f1 > "$TREE/share/claude-code/recipe-id"
runs "$(nohold x 2>&1 || :)" 2.1.289 "offline after a recipe change: builds from the recorded checksum and runs"
rm -rf "$HOME/Library/Caches/dev.mavergreen.claude-code"
runs "$(nohold x 2>&1 || :)" 2.1.289 "offline after the cache is purged: builds and runs"
rm -rf "$HOME/Library/Caches/dev.mavergreen.claude-code" "$ST/verified"
out="$(nohold x 2>&1 || echo "exit:$?")"
h_assert_contains "$out" "cannot run Claude Code 2.1.289: could not verify Claude Code 2.1.289 while offline" "offline with no record cannot verify"
h_assert_contains "$out" "exit:1" "and does not run"
mv "$H/cdn.off" "$H/cdn"
cp "$H/recipe.orig" "$TREE/share/claude-code/recipe"
cp "$H/recipe-id.orig" "$TREE/share/claude-code/recipe-id"

rm -rf "$V" "$ST" "$HOME/Library/Caches/dev.mavergreen.claude-code"
mkdir -p "$V"
install_cdn 2.1.289
h_cdn_publish 2.1.290
printf '# changed after its manifest\n' >> "$H/cdn/2.1.290/darwin-x64/claude"
printf '2.1.290\n' > "$H/cdn/stable"
runs "$(nohold install stable 2>&1 || :)" 2.1.289 "install stable: the recording launch runs 2.1.289"
out="$(nohold x 2>&1 || echo "exit:$?")"
h_assert_contains "$out" "could not fetch Claude Code 2.1.290 for the stable channel; using the newest installed version" "a failed channel download is noted"
runs "$out" 2.1.289 "and the launch runs the newest installed version"
h_assert_fails test -e "$ST/repick"
runs "$(nohold x 2>&1 || :)" 2.1.289 "the next launch runs too"

rm -rf "$ST"
out="$(nohold install 2.1.206 2>&1 || echo "exit:$?")"
h_assert_contains "$out" "Claude Code 2.1.206 predates 2.1.207" "install of a version before 2.1.207 is refused, saying why, instead of Claude Code reporting an install the launcher will not run"
h_assert_contains "$out" "exit:1" "that refusal exits 1"
case "$out" in *fake-claude*) h_assert_eq "Claude Code not run" "$out" "a refused install does not run Claude Code" ;; esac
h_assert_fails test -e "$ST/repick"
runs "$(nohold install 2.1.289 2>&1 || :)" 2.1.289 "install of a supported version still runs Claude Code's install"
h_assert_eq "install 2.1.289" "$(cat "$ST/repick" 2>/dev/null || :)" "and records it"
runs "$(nohold install stable 2>&1 || :)" 2.1.289 "install of a channel still runs Claude Code's install"
h_assert_eq "install stable" "$(cat "$ST/repick" 2>/dev/null || :)" "and records it"
