# Manual checks

These checks don't run with the test suite. Run them by hand on Mac OS X 10.9.

## search-check.sh

Claude Code ships its own `rg`, `ugrep` and `bfs` inside its binary. It runs them by starting
itself again with `argv[0]` set to the tool's name. This check runs them the same way on the
patched binary, with avxemu linked, and compares them with the tools installed on the Mac:

- **rg:** 60 runs of `rg -l license /usr/share`. Each run must exit 0 or 1 with no signal, and
  list the same files as `/usr/local/bin/rg`. One `/usr/bin/grep -rl` run is compared too. Its
  extra files must be ones that rg skips by default: symlinks, hidden files, or binary files.
- **ugrep:** `ugrep -r -c --include='*.md' skill` over `~/.claude/plugins/cache`, file by file
  against `/usr/bin/grep -c`. The counts must match. ugrep may skip hidden directories and
  symlinks.
- **bfs:** `bfs TREE -type f` against `/usr/bin/find TREE -type f`, on both trees. Only hidden
  directories and symlinks may differ.
- **Speed:** each tool against `/usr/local/bin/rg`, `/opt/pkg/bin/ugrep` or `/opt/pkg/bin/bfs`,
  on both trees. Each search runs once to warm up, then 10 more times. The built-in tool's median
  must be within 2x of the installed tool's. The last timed run of each tool must also give
  output that isn't empty and agrees with the other tool's, or the timing doesn't count.

Every run uses `env -i HOME=OUTDIR/search-check.home PATH=/usr/bin:/bin` and is killed after 600 seconds.
`OUTDIR/search-check.home` gets a `Library/Caches` like a real account's, since avxemu keeps its load-time
analysis cache there and won't create that directory. The cache is emptied before each built-in
tool's timed series, so the cold run is a real first start. Timed output goes to a file, not
`/dev/null`: ugrep notices `/dev/null` and skips the search.

It writes `OUTDIR/report.md` and ends with one `search-check: TOOL PASS|FAIL` line per tool. It
exits 0 when all three pass.

OUTDIR must be empty or a directory from an earlier run, which the script marks with
`OUTDIR/search-check.outdir`. Anything else, it refuses to touch.

### Build the binary to check

Do this in a scratch directory, from this repo's root. Use the version that
`https://downloads.claude.ai/claude-code-releases/latest` names:

```sh
v=2.1.292
w=/tmp/search-check
mkdir -p "$w/drydock" "$w/recipe"
curl -fsSL "https://downloads.claude.ai/claude-code-releases/$v/darwin-x64/claude" -o "$w/claude-$v"
curl -fsSL "https://downloads.claude.ai/claude-code-releases/$v/manifest.json" \
  | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["platforms"]["darwin-x64"]["checksum"])'
shasum -a 256 "$w/claude-$v"
sh packaging/fetch-drydock.sh 0.1.0 "$w/drydock"
SHIPYARD_SCRIPTS=/usr/local/mavergreen/shipyard/share/cmake/MavericksShipyard/scripts \
  sh packaging/render-recipe.sh "$w/drydock/drydock-macho-rewrite" "$w/recipe"
"$w/drydock/drydock-macho-rewrite" "$w/claude-$v" "$w/claude-$v-patched" < "$w/recipe/recipe"
chmod +x "$w/claude-$v-patched"
```

The two checksums must match. Then make sure the patched binary starts with no `DYLD_*` set, and
that `libavxemu.dylib` loads right after it:

```sh
env -i HOME="$w/home" PATH=/usr/bin:/bin "$w/claude-$v-patched" --version
env -i HOME="$w/home" PATH=/usr/bin:/bin DYLD_PRINT_LIBRARIES=1 "$w/claude-$v-patched" --version 2>&1 | head -n 3
```

### Run it

```sh
sh tests/manual/search-check.sh "$w/claude-$v-patched" "$w/search"
```

It takes a few minutes.
