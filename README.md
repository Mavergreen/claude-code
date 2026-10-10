# Claude Code for Mavericks

Anthropic's `claude` for Mac OS X 10.9 Mavericks.

Well, actually, it's just a script named `claude` that does these things for you:

- Fetch upstream binary
- Modify to run under Mavericks
- Repeat on update

This is the successor to Wowfunhappy's Mavericks Forever installer, on which it is very heavily based.

## How to use

Your CPU must support AVX instructions (or newer), as found in the 2013 Mac Pro and most other Macs since 2011.
The installer will check.

```sh
curl -fsSL https://github.com/Mavergreen/claude-code/releases/latest/download/install.sh | sh
```

If you're upgrading from the Mavericks Forever installer:

- Quit every running `claude` first
- Note that `claude`'s location is no longer `/usr/local/bin`

## Go back to Mavericks Forever

This shouldn't be needed, but just in case:

```sh
sudo mavergreen uninstall claude-code
curl mavericksforever.com/claude/install.sh | sh
```

Each user can clean up their home directory:

```sh
rm -rf ~/Library/Caches/dev.mavergreen.claude-code ~/Library/Application\ Support/dev.mavergreen.claude-code
[ "$(readlink ~/.local/bin/claude)" = /usr/local/mavergreen/bin/claude ] && rm -f ~/.local/bin/claude
```
