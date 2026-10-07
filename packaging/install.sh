#!/bin/sh
# platform: macOS-only -- installs .pkg products with /usr/sbin/installer on Mac OS X 10.9
#   usage: curl -fsSL https://github.com/Mavergreen/claude-code/releases/latest/download/install.sh | sh
#          Installs or updates avxemu, recaulk, libcxx22, icu and Claude Code for Mavericks, in that
#          order, each from its repo's latest release. MAVERGREEN_RELEASES overrides the base URL that
#          holds <repo>/releases/latest/download/; MAVERGREEN_INSTALL_ROOT prefixes
#          /usr/local/mavergreen when reading what is already installed.

note() { printf 'Claude Code for Mavericks: %s\n' "$*"; }
die() { printf 'Claude Code for Mavericks: ERROR: %s\n' "$*" >&2; exit 1; }

main() {
  set -eu
  base="${MAVERGREEN_RELEASES:-https://github.com/Mavergreen}"
  root="${MAVERGREEN_INSTALL_ROOT-}"

  case "$(uname -s)" in Darwin) ;; *) die "only macOS is supported" ;; esac
  osver="$(sw_vers -productVersion 2>/dev/null || :)"
  case "$osver" in
    10.9.[5-9]|10.9.[1-9][0-9]*) ;;
    *) die "Mac OS X 10.9.5 is required; this Mac runs ${osver:-an unknown version}" ;;
  esac
  case "$(uname -m)" in x86_64|amd64) ;; *) die "unsupported arch: $(uname -m)" ;; esac
  cpu="$(PATH="$PATH:/usr/sbin" sysctl -n machdep.cpu.features 2>/dev/null || :)"
  case "$cpu" in
    *[![:space:]]*) ;;
    *) die "could not read this Mac's CPU features" ;;
  esac
  case " $cpu " in
    *" AVX1.0 "*) ;;
    *) die "Your CPU has no AVX support. This machine is too old to run Claude Code." ;;
  esac

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/mavergreen-install.XXXXXX")" || die "could not create a temporary directory"
  trap 'rm -rf "$tmp"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  plan=""
  for pair in avxemu:avxemu recaulk:recaulk libcxx22:clang-22 icu:icu claude-code:claude-code; do
    short="${pair%%:*}"; repo="${pair#*:}"
    url="$base/$repo/releases/latest/download"
    sums="$tmp/$repo.SHA256SUMS"
    curl -fsSL --proto-redir =https -o "$sums" "$url/SHA256SUMS" || die "$repo: could not fetch $url/SHA256SUMS"
    awk -v s="$short" '
      { n = $2; sub(/^\*/, "", n) }
      NF == 2 && $1 ~ /^[0-9a-f]+$/ && length($1) == 64 && n ~ ("^" s "-[0-9][0-9A-Za-z.+-]*\\.pkg$") { print $1, n }
    ' "$sums" > "$sums.match"
    count="$(wc -l < "$sums.match" | tr -d ' ')"
    [ "$count" -ne 0 ] || die "$repo: its latest release lists no $short-<version>.pkg in SHA256SUMS"
    [ "$count" -eq 1 ] || die "$repo: its latest release lists $count $short-<version>.pkg in SHA256SUMS, not one"
    read -r want asset < "$sums.match"
    ver="${asset#"$short"-}"; ver="${ver%.pkg}"
    plist="$root/usr/local/mavergreen/$short/mavergreen.plist"
    have=""
    if [ -f "$plist" ]; then
      have="$(/usr/libexec/PlistBuddy -c 'Print :version' "$plist" 2>/dev/null || :)"
    fi
    if [ "$have" = "$ver" ]; then
      note "$short $ver is already installed"
      continue
    fi
    note "downloading $asset"
    curl -fL --proto-redir =https --progress-bar -o "$tmp/$asset" "$url/$asset" || die "$repo: could not download $url/$asset"
    got="$(shasum -a 256 "$tmp/$asset" | cut -d' ' -f1)"
    [ -n "$got" ] && [ "$got" = "$want" ] || die "$asset does not match $url/SHA256SUMS (wanted $want, got ${got:-nothing})"
    plan="$plan $asset"
  done

  if [ -n "$plan" ]; then
    note "installing needs an administrator's password"
    sudo -v || die "could not get administrator rights"
    for asset in $plan; do
      note "installing $asset"
      sudo /usr/sbin/installer -pkg "$tmp/$asset" -target / || die "installer failed on $asset"
    done
  else
    note "everything is up to date"
  fi

  note "done. Open a new Terminal window, then run claude."
}

main "$@"
