# Build ingredients

Everything baked into what Claude Code for Mavericks ships, and how a change to it reaches a release.

This product is **its own upstream**: nothing external releases it.

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| our own source (own upstream) | `UPSTREAM_VERSION`: the date of the newest source a release carries, bumped by hand | ❌ untrackable: nothing external releases it | bumping it on `main` is the decision to release |
| MacOSX10.9 SDK, CMake modules, compat guard, packaging and signing scripts | `Mavergreen/shipyard@v1` | ✅ github-actions manager tracks the tag | `@v1` moves without the pin changing, so nothing repackages by itself |
| Sparkle, in the updater | shipyard's `fetch_sparkle_framework.sh`, pinned by hash there | ❌ untrackable here: shipyard owns that pin | follows shipyard |
| computer-use MCP server (`mcp_server.py`, `cu_actions.py`), vendored from Wowfunhappy | `tree/share/claude-code/computer-use/`, hashes in `PROVENANCE.md` | ❌ untrackable: vendored source with no release to watch | updated by hand from upstream until it becomes its own product |

Not ingredients: AVXEmu and the runtime are required at install time (`--requires`, runtime only),
not shipped in this package. Claude Code is fetched on the user's Mac, verified, and never shipped.

## Declared state

- upstream: UPSTREAM_VERSION

## Conformance deviations

- scheme: Claude Code for Mavericks is its own upstream (no one else's release to repackage), so it versions itself by date as YYYYMMDD.N with no -mavericks.N axis

## Upstream release notes

No upstream release notes: this repo is its own upstream; Claude Code's own notes are Anthropic's and are not tied to our releases.
