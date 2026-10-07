#!/bin/sh
# Claude Code installer for macOS 10.9 Mavericks.
#
# Layout
#   /usr/local/bin/claude               wrapper         (sudo)
#   /usr/local/bin/rg                   ripgrep         (sudo, only if absent)
#   ~/.local/share/claude-mavericks/    dylibs + tools + computer-use MCP +
#                                       managed settings.json
#   ~/.local/bin/claude                 Anthropic's symlink
#   ~/.local/share/claude/versions/     Anthropic's binaries (patched in place
#                                       on first launch by the wrapper)
#
# curl -fsSL https://mavericksforever.com/claude/install.sh | sh
# curl -fsSL https://mavericksforever.com/claude/install.sh | sh -s -- --version 1.2.3
# Written by Claude. Human assistance provided by Wowfunhappy.

set -e

BASE_URL="${BASE_URL:-https://mavericksforever.com/claude}"
ANTHROPIC_BASE="${ANTHROPIC_BASE:-https://downloads.claude.ai/claude-code-releases}"
WRAPPER_PATH="${WRAPPER_PATH:-/usr/local/bin/claude}"
RG_PATH="${RG_PATH:-/usr/local/bin/rg}"
MF="${MF:-$HOME/.local/share/claude-mavericks}"
CU_DIR="$MF/computer-use"
ANTHROPIC_LINK="$HOME/.local/bin/claude"

die()  { echo "" >&2; echo "ERROR: $*" >&2; exit 1; }
note() { printf '[Claude Code Mavericks Installer] %s\n' "$*"; }
dl()   { curl -fL --progress-bar -o "$1" "$2" || die "download failed: $2"; }

# Optional version pin:
#   curl -fsSL .../install.sh | sh -s -- --version 1.2.3
#   curl -fsSL .../install.sh | CLAUDE_VERSION=1.2.3 sh
CLAUDE_VERSION="${CLAUDE_VERSION:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        --version=*) CLAUDE_VERSION="${1#--version=}" ;;
        --version|-v)
            [ $# -ge 2 ] || die "--version requires a version number"
            CLAUDE_VERSION="$2"; shift ;;
        -h|--help)
            echo "Usage: install.sh [--version <claude-code-version>]"; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

case "$(uname -s)" in Darwin) ;; *) die "only macOS is supported" ;; esac
case "$(uname -m)" in x86_64|amd64) ;; *) die "unsupported arch: $(uname -m)" ;; esac

# Require AVX. Claude Code's binary is built for Haswell (AVX2); on older CPUs
# the bundled emulator bridges AVX2 -> AVX1, but it cannot go below AVX.
case " $(sysctl -n machdep.cpu.features 2>/dev/null) " in
    *" AVX1.0 "*) ;;
    *) die "Your CPU has no AVX support. This machine is too old to run Claude Code." ;;
esac

note "Testing claude.ai connectivity..."
curl -fsS --head -o /dev/null --max-time 15 "$ANTHROPIC_BASE/latest" \
    || die "Could not connect to Anthropic. Is Aqua Proxy installed?"

### system step: install wrapper, plus rg if absent ###
TMP=$(mktemp -d -t claude-mf)
trap 'rm -rf "$TMP"' EXIT INT TERM

cat > "$TMP/claude" <<'WRAPPER_EOF'
#!/bin/sh
# Resolves the current user's Anthropic-managed install at ~/.local/bin/claude,
# patches the binary in place if it lacks the Mavericks dylib wrappers, and
# execs it with the computer-use MCP wired in.
set -e

MF=$HOME/.local/share/claude-mavericks
ANTHROPIC_LINK=$HOME/.local/bin/claude
INSTALLER_URL=https://mavericksforever.com/claude/install.sh

# How the binary gets patched, which flags the tools in $MF accept, and where the
# dylib aliases live all have to agree with each other. Rather than detect which
# of them a given install predates, stamp the whole tree and reinstall when the
# stamp isn't ours. Bump this whenever any of those three change; the installer
# reads the value back out of this wrapper, so it is the only place to edit it.
MF_GEN=3

# Use the ripgrep in /usr/local/bin, not the copy embedded in the binary.
export USE_BUILTIN_RIPGREP=0
export DISABLE_INSTALLATION_CHECKS=1
# Drops idle CPU from ~150% to <0.1%.
export JSC_numberOfGCMarkers=1

# First-run / stale-install bootstrap for this user. CLAUDE_MF_BOOTSTRAP tells
# the installer not to touch the shared /usr/local/bin wrapper: this very wrapper
# is already running, so it's good enough, and a new (possibly non-admin) user
# shouldn't get a sudo prompt just to launch claude. Wrapper refreshes happen
# when an admin re-runs the installer directly.
if [ ! -d "$MF" ] || [ ! -e "$ANTHROPIC_LINK" ] \
   || [ "$(cat "$MF/.generation" 2>/dev/null)" != "$MF_GEN" ]; then
    echo "claude: setting up Claude Code for $USER..." >&2
    # Run from a file, not a pipe: `curl | sh` reports sh's status, so a failed
    # download would pass as a successful bootstrap.
    BOOT=$(mktemp -t claude-mf-boot) || { echo "claude: mktemp failed" >&2; exit 1; }
    curl -fsSL "$INSTALLER_URL" -o "$BOOT" \
        || { rm -f "$BOOT"; echo "claude: could not download the installer from $INSTALLER_URL" >&2; exit 1; }
    CLAUDE_MF_BOOTSTRAP=1 sh "$BOOT" >&2 \
        || { rm -f "$BOOT"; echo "claude: setup failed" >&2; exit 1; }
    rm -f "$BOOT"
    # A published installer older than this wrapper would leave the tree
    # unstamped and we would refetch it on every launch. Say so once instead.
    [ "$(cat "$MF/.generation" 2>/dev/null)" = "$MF_GEN" ] || {
        echo "claude: $INSTALLER_URL is older than this wrapper (needs generation $MF_GEN)." >&2
        exit 1
    }
fi

# The native binary is built for Haswell (AVX2+FMA+BMI). On older CPUs that lack
# AVX2 (pre-2013 Macs) those instructions fault; libavxemu.dylib installs a
# SIGILL handler that traps and emulates them. Loaded only when AVX2 is absent,
# so AVX2-capable Macs keep running natively at full speed. Decided after the
# bootstrap above so a freshly-downloaded dylib is picked up on first run.
if [ -f "$MF/libavxemu.dylib" ] && ! sysctl -n machdep.cpu.leaf7_features 2>/dev/null | grep -qiw AVX2; then
    export DYLD_INSERT_LIBRARIES="$MF/libavxemu.dylib${DYLD_INSERT_LIBRARIES:+:$DYLD_INSERT_LIBRARIES}"
fi

# Resolve symlink to the actual versioned binary.
REAL=$(readlink "$ANTHROPIC_LINK" 2>/dev/null || echo "$ANTHROPIC_LINK")
case "$REAL" in /*) ;; *) REAL="$(dirname "$ANTHROPIC_LINK")/$REAL" ;; esac
[ -f "$REAL" ] || { echo "claude: $REAL does not exist." >&2; exit 1; }

# Patch in place if needed. Anthropic's auto-updater drops a fresh unpatched
# binary at ~/.local/share/claude/versions/<ver>; we re-check on every launch.
# The post-install validator inside the binary only stat-checks (size>0,
# S_IXUSR), so an in-place rewrite passes its checks.
#
# Newer Claude builds leave very little Mach-O header padding — 2.1.245 has 8
# bytes. Keep replacement install names short so change_dylib can rewrite
# LC_LOAD_DYLIB commands in place. -strip-lc drops LC_UUID and LC_CODE_SIGNATURE
# (40 bytes here, and the signature is void the moment the binary is rewritten),
# which reclaims padding without moving a single byte of file data. That is the
# whole budget, and it is enough: the rewritten 2.1.263 has 96 bytes to spare.
#
# The aliases sit in the parent of the versions directory. Claude Code's version
# housekeeping treats every entry inside versions/ as a version, gives it a lock
# file, and reaps the ones it holds no lock for, stranding the dependencies of a
# binary that is already running. "@loader_path/../S.dylib" is the same byte
# length as the in-directory spelling, so cmdsize is unchanged and no padding is
# consumed. libc++abi.1.dylib needs no alias: dyld resolves libc++'s own
# @loader_path through the symlink to its real directory.
REAL_DIR=$(dirname "$REAL")
ALIAS_DIR=$(dirname "$REAL_DIR")
ln -sf "$MF/libSystemWrapper.dylib" "$ALIAS_DIR/S.dylib" || { echo "claude: S alias failed" >&2; exit 1; }
ln -sf "$MF/libicucoreWrapper.dylib" "$ALIAS_DIR/I.dylib" || { echo "claude: I alias failed" >&2; exit 1; }
ln -sf "$MF/libc++.1.dylib" "$ALIAS_DIR/c++.1.dylib" || { echo "claude: c++ alias failed" >&2; exit 1; }

# The install names live in the load commands, within the first few KB, so cap
# the read at 1 MB — scanning all ~300 MB costs about 4s of every launch. Leave
# -a off: BSD grep's text mode stops each line at the load commands' NUL padding.
#
# Patching builds a copy and renames over the original: a session already
# running has the current inode mapped.
if ! head -c 1048576 "$REAL" 2>/dev/null | grep -qE '@loader_path/\.\./S\.dylib'; then
    echo "claude: patching $(basename "$REAL")..." >&2
    T="$REAL.mf-tmp.$$"
    trap 'rm -f "$T"' EXIT INT TERM
    "$MF/patch_macho"     "$REAL" "$T" >/dev/null || { echo "claude: patch_macho failed"     >&2; exit 1; }
    "$MF/add_version_min" "$T"         >/dev/null || { echo "claude: add_version_min failed" >&2; exit 1; }
    "$MF/change_dylib"    "$T" -strip-lc uuid -strip-lc codesig \
        -change "/usr/lib/libSystem.B.dylib"  "@loader_path/../S.dylib" \
        -change "/usr/lib/libicucore.A.dylib" "@loader_path/../I.dylib" \
        -change "/usr/lib/libc++.1.dylib"     "@loader_path/../c++.1.dylib" \
        >/dev/null || { echo "claude: change_dylib failed" >&2; exit 1; }
    chmod +x "$T"
    mv "$T" "$REAL"
    trap - EXIT INT TERM
fi

# Managed settings carry the computer-use MCP permission. Absolute paths are
# baked in at install time; the MCP loader doesn't expand env vars in JSON.
#
# Every injected flag uses --flag=value. --mcp-config <configs...> and
# --allowedTools <tools...> are declared variadic, so the space form consumes
# every following token up to the next one starting with "-" — and these are
# prepended, which puts them directly in front of whatever the user typed.
# `claude mcp list` then reports the subcommand as two missing config files.
# The =value form binds exactly one value whatever the declared arity, so it is
# correct here no matter which flag ends up last.
CU="$MF/computer-use"
if [ -f "$CU/mcp-config.json" ] && [ -x "$CU/mcp_server.py" ]; then
    set -- "--mcp-config=$CU/mcp-config.json" "$@"
fi
if [ -f "$MF/settings.json" ]; then
    set -- "--settings=$MF/settings.json" "$@"
fi

# Claude Code's shell snapshots shadow `find` and `grep` with the embedded
# bfs/ugrep unless the Grep or Glob tool is named on the command line. Those
# shims re-exec the CLI binary under a different argv[0], which fails here, so
# opt in: the system find/grep stay visible and Grep/Glob run in-process.
set -- --allowedTools=Grep "$@"

exec "$REAL" "$@"
WRAPPER_EOF

# Only touch the wrapper (and prompt for sudo) if it's missing or out of date.
# cmp -s is silent and returns non-zero when the files differ or the target is
# absent, so an unchanged wrapper skips sudo entirely on re-runs. During a
# wrapper-triggered bootstrap (CLAUDE_MF_BOOTSTRAP set) we skip the update
# altogether: the running wrapper already works, and a new/non-admin user
# launching claude shouldn't be prompted for a password to refresh it.
if [ -z "$CLAUDE_MF_BOOTSTRAP" ] && ! cmp -s "$TMP/claude" "$WRAPPER_PATH"; then
    note "Installing $WRAPPER_PATH... Please type in your password and press return."
    sudo mkdir -p "$(dirname "$WRAPPER_PATH")" || die "could not create $(dirname "$WRAPPER_PATH")"
    sudo install -m 755 "$TMP/claude" "$WRAPPER_PATH" || die "wrapper install failed"
fi

if ! command -v rg >/dev/null 2>&1 && [ ! -x "$RG_PATH" ]; then
    note "Downloading ripgrep 13.0.0..."
    dl "$TMP/rg" "$BASE_URL/rg"
    sudo mkdir -p "$(dirname "$RG_PATH")" || die "could not create $(dirname "$RG_PATH")"
    sudo install -m 755 "$TMP/rg" "$RG_PATH" || die "rg install failed"
fi

### per-user step ###
note "Populating $MF..."
mkdir -p "$MF" "$CU_DIR" "$HOME/.cache/claude-mavericks"

for tool in patch_macho change_dylib add_version_min; do
    note "Downloading $tool..."
    dl "$MF/$tool" "$BASE_URL/$tool"
    chmod +x "$MF/$tool"
done
for lib in libSystemWrapper.dylib libc++.1.dylib libc++abi.1.dylib libavxemu.dylib; do
    note "Downloading $lib..."
    dl "$MF/$lib" "$BASE_URL/$lib"
done
note "Downloading libicucoreWrapper.dylib.gz..."
dl "$MF/libicucoreWrapper.dylib.gz" "$BASE_URL/libicucoreWrapper.dylib.gz"
gunzip -f "$MF/libicucoreWrapper.dylib.gz" || die "gunzip libicucoreWrapper.dylib.gz failed"

for f in cu_actions.py mcp_server.py; do
    note "Downloading computer-use/$f..."
    dl "$CU_DIR/$f" "$BASE_URL/computer-use/$f"
done
chmod +x "$CU_DIR/mcp_server.py"

# Per-user mcp-config.json: HOME differs per user and JSON has no env-var
# expansion, so we bake the absolute path in here.
cat > "$CU_DIR/mcp-config.json" <<EOF
{
  "mcpServers": {
    "computer-use-mavericks": {
      "type": "stdio",
      "command": "$CU_DIR/mcp_server.py",
      "args": [],
      "env": {}
    }
  }
}
EOF

# Clear the hook path in case an earlier install left a file there.
rm -f "$MF/grep-fix.sh"

# Managed settings the wrapper always passes. Absolute path baked in (settings
# JSON has no env-var expansion), same approach as mcp-config.json above.
cat > "$MF/settings.json" <<EOF
{
  "permissions": { "allow": ["mcp__computer-use-mavericks"] }
}
EOF

### Install Claude Code from Anthropic's CDN.
#
# Always fetch fresh. The wrapper patches the Mach-O in place, so whatever sits
# in versions/ carries the fixups of whichever installer wrote it, and telling
# one vintage from another would mean teaching this script every scheme it has
# ever emitted. Downloading a pristine binary sidesteps that: the wrapper
# re-patches on the next launch, so a re-run always converges on the same state
# no matter what it started from. Costs a full download each run; worth it.
VER_DIR="$HOME/.local/share/claude/versions"
mkdir -p "$VER_DIR" "$(dirname "$ANTHROPIC_LINK")"
PLATFORM="darwin-x64"

if [ -n "$CLAUDE_VERSION" ]; then
    VERSION="$CLAUDE_VERSION"
    note "Pinning to Claude Code $VERSION..."
else
    note "Fetching latest Claude Code version..."
    VERSION=$(curl -fsSL "$ANTHROPIC_BASE/latest") || die "could not fetch latest version"
fi

BIN_PATH="$VER_DIR/$VERSION"

note "Fetching manifest for $VERSION..."
MANIFEST=$(curl -fsSL "$ANTHROPIC_BASE/$VERSION/manifest.json") \
    || die "manifest fetch failed — is $VERSION a real version?"
# Pure-shell extract: no jq on stock Mavericks. Mirrors Anthropic's bash
# fallback regex: find the darwin-x64 block, then its "checksum" hex.
CHECKSUM=$(printf '%s' "$MANIFEST" | tr -d '\n\r\t' \
    | grep -Eo "\"$PLATFORM\"[^}]*\"checksum\"[[:space:]]*:[[:space:]]*\"[a-f0-9]{64}\"" \
    | grep -Eo '[a-f0-9]{64}')
[ -n "$CHECKSUM" ] || die "could not find $PLATFORM checksum in manifest"

# Download beside the target and rename over it. A session may be running this
# exact file, and macOS refuses to open a running executable for writing.
note "Downloading claude $VERSION ($PLATFORM)..."
TMP_BIN="$BIN_PATH.dl.$$"
dl "$TMP_BIN" "$ANTHROPIC_BASE/$VERSION/$PLATFORM/claude"
ACTUAL=$(shasum -a 256 "$TMP_BIN" | cut -d' ' -f1)
[ "$ACTUAL" = "$CHECKSUM" ] || { rm -f "$TMP_BIN"; die "checksum mismatch (expected $CHECKSUM, got $ACTUAL)"; }
chmod +x "$TMP_BIN"
mv -f "$TMP_BIN" "$BIN_PATH"

ln -sf "$BIN_PATH" "$ANTHROPIC_LINK"

# Stamp last, so a run that dies partway leaves the tree unstamped and the
# wrapper tries again. Read from the generated wrapper rather than repeating the
# number here: one definition, no chance of the two drifting apart.
MF_GEN=$(sed -n 's/^MF_GEN=//p' "$TMP/claude" | head -1)
[ -n "$MF_GEN" ] || die "could not read MF_GEN from the generated wrapper"
echo "$MF_GEN" > "$MF/.generation"

echo ""
echo "✓ Installation complete!"
echo ""

### trigger first patch ###
"$WRAPPER_PATH" --version >/dev/null 2>&1 || true

### warn if ~/.local/bin shadows the wrapper ###
case ":$PATH:" in
    *":$HOME/.local/bin:"*":/usr/local/bin:"*)
        echo 'Warning: ~/.local/bin comes before /usr/local/bin in your PATH.'
        echo 'You will need to specify the full path /usr/local/bin/claude every time you run Claude.'
        echo "Alternatively, adjust your PATH so that /usr/local/bin comes first."
        ;;
esac
