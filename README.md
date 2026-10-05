# Claude Code for Mavericks

**This README has not been read or edited by a human yet.** Until it has, this project cannot cut its first release.

Claude Code for Mavericks runs Anthropic's Claude Code on Mac OS X 10.9, including on Macs without AVX2. It installs a launcher, the Mavericks fixes and the tool that applies them. Claude Code itself is never part of the package: the launcher downloads it from Anthropic on your Mac, checks it against Anthropic's published checksum, and patches a copy there.

Two more pieces come as separate packages, installed first: avxemu, which emulates AVX2 on Macs that lack it, and the runtime, which supplies the system libraries Claude Code needs that 10.9 lacks. The Claude Code for Mavericks installer refuses to run without them, and says where to get whichever is missing.

This project is not affiliated with, endorsed by, or sponsored by Anthropic. Claude and Claude Code are trademarks of Anthropic.

## Installing

1. Install avxemu.
2. Install the runtime.
3. Install Claude Code for Mavericks.

Then open a new Terminal window, so that your shell finds the new `claude`, and run `claude`. The first run downloads Claude Code, which takes a minute.

If you used Mavericks Forever, the installer removes its `/usr/local/bin/claude`. Anything you pointed at `/usr/local/bin/claude` (an editor, a script, an alias) should point at `/usr/local/mavergreen/bin/claude` instead.

## Pinning a version

Claude Code keeps itself up to date, and the launcher runs the newest version it has downloaded. To stay on the version you are running, set `DISABLE_AUTOUPDATER=1`, either in your environment or under `"env"` in `~/.claude/settings.json`:

```json
{ "env": { "DISABLE_AUTOUPDATER": "1" } }
```

To move to a particular version, run `claude install <version>`; the launcher switches to it at the next launch. Versions before 2.1.207 cannot run under the launcher.

## Going back to Mavericks Forever

Uninstall Claude Code for Mavericks first (`sudo mavergreen uninstall claude-code`), then rerun https://mavericksforever.com/claude/install.sh.

Uninstalling leaves a few things in each user's home: patched copies of Claude Code in `~/Library/Caches/dev.mavergreen.claude-code`, the launcher's records in `~/Library/Application Support/dev.mavergreen.claude-code`, and `~/.local/bin/claude`, when it is the link to the launcher (it now points at nothing). To remove them, each user runs:

```sh
rm -rf ~/Library/Caches/dev.mavergreen.claude-code ~/Library/Application\ Support/dev.mavergreen.claude-code
[ "$(readlink ~/.local/bin/claude)" = /usr/local/mavergreen/bin/claude ] && rm -f ~/.local/bin/claude
```
