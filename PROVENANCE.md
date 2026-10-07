# Provenance

Claude Code for Mavericks grew out of Wowfunhappy's Mavericks Forever
(`https://mavericksforever.com/claude/`, `MF_GEN=3`), with his blessing. His work is CC0.

| From Mavericks Forever | Where it is now | How it changed |
|---|---|---|
| `install.sh`, and the `/usr/local/bin/claude` wrapper it writes | this repo: `packaging/install.sh` and `tree/bin/claude` | rewritten; his is committed verbatim first (author Wowfunhappy), then replaced. His refusal messages are kept word for word, and the launcher keeps the wrapper's injected options, config-file shapes, `JSC_numberOfGCMarkers` and `DISABLE_INSTALLATION_CHECKS`. It sets neither `USE_BUILTIN_RIPGREP=0` nor `DYLD_INSERT_LIBRARIES` (avxemu is linked instead), and adds a `CLAUDE_ENV_FILE` of shell guards |
| computer-use MCP server (`mcp_server.py`, `cu_actions.py`) | this repo: `tree/share/claude-code/computer-use/` | one host-declaration line per file (below) |
| `patch_macho`, `add_version_min`, `change_dylib`, and the patch they apply to Claude Code | `drydock-macho-rewrite` (Mavergreen/drydock), driven by `packaging/recipe.in` | reproduced, then extended: the patch also links avxemu as the first library it loads and grows the header by a page to fit it. On Claude Code 2.1.292, against his output, the other libraries' ordinals move up by one (binds renumbered to match), the image base moves one page lower, and 463 base-relative bytes are re-based; every other byte of code and data matches, and the linker tables keep their sizes |
| `libavxemu.dylib` | Mavergreen/avxemu | his project, now maintained there |
| `libSystemWrapper.dylib`, `libc++.1.dylib`, `libc++abi.1.dylib`, `libicucoreWrapper.dylib` | Mavergreen/recaulk (with his shims' function bodies verbatim), Mavergreen/clang-22's libcxx22, Mavergreen/icu | rebuilt from source; each repo's own provenance has the details |

## install.sh

Downloaded on 2026-10-07 from `https://mavericksforever.com/claude/install.sh`, SHA-256
`5d9f01badd7d9d93c29814fc43c2ceff6ca2921724c8db7be08def944a2c95f2`. Its header reads "Written by
Claude. Human assistance provided by Wowfunhappy."

## computer-use

Vendored under `share/claude-code/computer-use/`; downloaded on 2026-10-05 from
`https://mavericksforever.com/claude/computer-use/`.

| File | Upstream SHA-256 | SHA-256 as committed |
|---|---|---|
| `mcp_server.py` | `99e8ceba1893b7e97de736495f10a015ae60a5902c48451c5ba2d4c78341c568` | `5ed243ed2c3d560c392e1249e2ce6822907048bd0fcffbeda9ea66f155c66b6d` |
| `cu_actions.py` | `6e313099e7a463f1aa859e642259f2c870065e85780c6cb92ea899bf7ee82c54` | `45f26a59690d3c7b13c6b256330af8cb0b7e112669bb4a88da4599f4f72084eb` |

Exactly one line was added to each file, immediately after the `# -*- coding: utf-8 -*-` line:
`# platform: macOS-only -- uses the system Python 2.7 and PyObjC that Mac OS X 10.9 ships`.
Nothing else differs from upstream.

`share/claude-code/mcp-config.json` and `settings.json` have the shape Mavericks Forever's installer writes
per user, with the server's path fixed at `/usr/local/mavergreen/claude-code/share/claude-code/computer-use/mcp_server.py`.
