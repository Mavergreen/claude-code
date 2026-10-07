# Claude Code for Mavericks

**This README has not been read or edited by a human yet.** Until it has, this project cannot cut its first release.

Claude Code for Mavericks runs Anthropic's Claude Code on Mac OS X 10.9, including on Macs without AVX2. It installs a launcher, the Mavericks fixes and the tool that applies them. Claude Code itself is never part of the package: the launcher downloads it from Anthropic on your Mac, checks it against Anthropic's published checksum, and patches a copy there.

Four more pieces come as separate packages, installed first: avxemu, which emulates AVX2 on Macs that lack it, and three runtime products (recaulk, libcxx22 and icu), which supply the system libraries Claude Code needs that 10.9 lacks. The Claude Code for Mavericks installer refuses to run without them, and says where to get whichever is missing.

This project is not affiliated with, endorsed by, or sponsored by Anthropic. Claude and Claude Code are trademarks of Anthropic.

## Installing

In Terminal, run:

```sh
curl -fsSL https://github.com/Mavergreen/claude-code/releases/latest/download/install.sh | sh
```

It reads each of the five packages' latest release checksums, downloads only the packages you do not already have at that version, checks each download against those checksums, and installs them, asking once for an administrator's password. Run it again at any time to update them all.

To install by hand instead, download each package from its latest release and install them in this order:

1. avxemu, from https://github.com/Mavergreen/avxemu/releases/latest
2. recaulk, from https://github.com/Mavergreen/recaulk/releases/latest
3. libcxx22, from https://github.com/Mavergreen/clang-22/releases/latest
4. icu, from https://github.com/Mavergreen/icu/releases/latest
5. Claude Code for Mavericks, from https://github.com/Mavergreen/claude-code/releases/latest

Either way, then open a new Terminal window, so that your shell finds the new `claude`, and run `claude`. The first run downloads Claude Code, which takes a minute.

If you used Mavericks Forever, the Claude Code for Mavericks package removes its `/usr/local/bin/claude`. Anything you pointed at `/usr/local/bin/claude` (an editor, a script, an alias) should point at `/usr/local/mavergreen/bin/claude` instead.

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
