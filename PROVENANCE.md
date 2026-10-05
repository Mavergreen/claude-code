# Provenance

Claude Code for Mavericks replaces Wowfunhappy's Mavericks Forever installer and wrapper
(`https://mavericksforever.com/claude/install.sh`, `MF_GEN=3`).

The computer-use component is Wowfunhappy's (CC0). It is vendored under
`share/claude-code/computer-use/`; it was downloaded on 2026-10-05 from
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
