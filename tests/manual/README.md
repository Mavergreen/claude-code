# Manual checks

These checks don't run with the test suite. Run them by hand on Mac OS X 10.9.

## search-check.sh

Claude Code ships its own `rg`, `ugrep` and `bfs` inside its binary. It runs them by starting
itself again with `argv[0]` set to the tool's name. This check runs them the same way on the
patched binary, with avxemu linked, and compares them with standalone tools:

- **rg:** 60 runs of `rg -l license /usr/share`. Each run must exit 0 or 1 with no signal, and
  list the same files as the standalone rg. One `/usr/bin/grep -rl` run is compared too, and must
  exit 0. Files only grep lists must be ones that rg skips by default: symlinks, hidden files, or
  binary files. rg must list no file that grep doesn't.
- **ugrep:** `ugrep -r -c --include='*.md' skill` over the plugins cache, file by file against
  `/usr/bin/grep -c`. Both must exit 0 and the counts must match. Files only grep counts may be
  under hidden directories or symlinks; ugrep must count no file that grep doesn't.
- **bfs:** `bfs TREE -type f` against `/usr/bin/find TREE -type f`, on both trees. Both must exit
  0. Files only find lists may be under hidden directories or symlinks; bfs must list no file that
  find doesn't.
- **Speed:** each tool against the standalone rg, ugrep or bfs, on both trees. Each search runs
  once to warm up, then 10 more times, and every run must exit 0. The built-in tool's median must
  be within 2x of the standalone tool's. The last timed run of each tool must also give output
  that isn't empty and agrees with the other tool's, or the timing doesn't count. For ugrep, files
  that only one side lists must be explained by hidden directories, symlinks or binary content,
  since the two ugreps may be different versions.

Every run uses `env -i HOME=OUTDIR/search-check.home PATH=/usr/bin:/bin
AVXEMU_CACHE_DIR=OUTDIR/search-check.home/Library/Caches/avxemu` and is killed after 600 seconds.
`OUTDIR/search-check.home` gets a `Library/Caches` like a real account's, and avxemu keeps its
load-time analysis cache in `AVXEMU_CACHE_DIR` there. The cache is emptied before each built-in
tool's timed series, so the cold run is a real first start. Timed output goes to a file, not
`/dev/null`: ugrep notices `/dev/null` and skips the search.

It writes `OUTDIR/report.md` and ends with one `search-check: TOOL PASS|FAIL` line per tool. It
exits 0 when all three pass, 1 when any fails, and 2 when it cannot run.

OUTDIR must be empty or a directory from an earlier run, which the script marks with
`OUTDIR/search-check.outdir`. Anything else, it refuses to touch.

### Prerequisites

- Standalone `rg` (ripgrep), `ugrep` and `bfs`. The script takes the first of each on `PATH`,
  else in `/opt/pkg/bin`, `/usr/local/bin` or `/opt/local/bin`. Set `SEARCH_CHECK_RG`,
  `SEARCH_CHECK_UGREP` or `SEARCH_CHECK_BFS` to a path to choose one. The takeover in release 1
  deletes `/usr/local/bin/rg` on a migrated Mac, so rg may need installing again.
- `otool`, from the Command Line Tools. The script refuses a binary that doesn't link
  `libavxemu.dylib`.
- A second tree to search. By default it is the live `~/.claude/plugins/cache`, which Claude Code
  can change during a run (a plugin update), and a change shows up as differences. For a tree
  that holds still, copy it and point `SEARCH_CHECK_CACHE` at the copy:
  once `$w` below is set, `cp -R ~/.claude/plugins/cache "$w/cache"; export SEARCH_CHECK_CACHE="$w/cache"`.
- `curl`, `shasum` and perl 5.16, which 10.9 has, for the steps below.

### Build the binary to check

Do this from this repo's root. `v` is the version that
`https://downloads.claude.ai/claude-code-releases/latest` names; set it to another to check that:

```sh
v="$(curl -fsSL https://downloads.claude.ai/claude-code-releases/latest)"
w="$(mktemp -d "${TMPDIR:-/tmp}/search-check.XXXXXX")"
mkdir -p "$w/drydock" "$w/recipe" "$w/home/Library/Caches"
curl -fsSL "https://downloads.claude.ai/claude-code-releases/$v/darwin-x64/claude" -o "$w/claude-$v"
want="$(curl -fsSL "https://downloads.claude.ai/claude-code-releases/$v/manifest.json" \
  | /usr/bin/perl -MJSON::PP -0777 -ne 'print decode_json($_)->{platforms}{"darwin-x64"}{checksum}')"
if [ -n "$want" ] && [ "$want" = "$(shasum -a 256 "$w/claude-$v" | cut -d' ' -f1)" ]; then echo "checksum ok"; else echo "checksum MISMATCH: stop here"; fi
sh packaging/fetch-drydock.sh 0.1.0 "$w/drydock"
SHIPYARD_SCRIPTS=/usr/local/mavergreen/shipyard/share/cmake/MavericksShipyard/scripts \
  sh packaging/render-recipe.sh "$w/drydock/drydock-macho-rewrite" "$w/recipe"
"$w/drydock/drydock-macho-rewrite" "$w/claude-$v" "$w/claude-$v-patched" < "$w/recipe/recipe"
chmod +x "$w/claude-$v-patched"
```

It must print `checksum ok`. Then make sure the patched binary starts with no `DYLD_*` set, and
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
