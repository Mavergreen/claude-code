#!/bin/sh
# platform: macOS-only -- runs Claude Code's built-in tools on Mac OS X 10.9
#   usage: sh tests/manual/search-check.sh PATCHED-CLAUDE OUTDIR
#          runs PATCHED-CLAUDE as rg, ugrep and bfs (argv[0] set to the tool's name), compares them
#          with standalone rg, ugrep and bfs, /usr/bin/grep and /usr/bin/find over /usr/share and the
#          plugins cache, writes OUTDIR/report.md, and prints "search-check: rg|ugrep|bfs PASS|FAIL" as
#          its last six lines, as "search-check: TOOL correctness|speed PASS|FAIL". Exit 0 when all
#          pass, 1 when any correctness check fails, 3 when all are correct but a built-in is over the
#          speed bar, 2 when it cannot run.
#          SEARCH_CHECK_RG, SEARCH_CHECK_UGREP and SEARCH_CHECK_BFS name the standalone tools; each
#          defaults to the first on PATH, else in /opt/pkg/bin, /usr/local/bin or /opt/local/bin, and
#          must not be PATCHED-CLAUDE itself (a link to it compares the built-in with itself).
#          SEARCH_CHECK_CACHE names the second tree; it defaults to ~/.claude/plugins/cache.
set -u
[ $# -eq 2 ] || { echo "usage: search-check.sh PATCHED-CLAUDE OUTDIR" >&2; exit 2; }
bin="$1"; out="$2"
case "$bin" in /*) ;; *) bin="$(pwd)/$bin" ;; esac
[ -f "$bin" ] && [ -x "$bin" ] || { echo "not an executable file: $bin" >&2; exit 2; }

ext_tool() {
  eval "_et=\${$1-}"
  if [ -z "$_et" ]; then
    _et="$(command -v "$2" 2>/dev/null)" || _et=""
    case "$_et" in /*) ;; *) _et="" ;; esac
    for _ed in /opt/pkg/bin /usr/local/bin /opt/local/bin; do
      [ -n "$_et" ] || [ ! -x "$_ed/$2" ] || _et="$_ed/$2"
    done
  fi
  [ -n "$_et" ] && [ -f "$_et" ] && [ -x "$_et" ] || { echo "no standalone $2 found: install it, or set $1 to its path" >&2; return 1; }
  printf '%s\n' "$_et"
}
EXT_RG="$(ext_tool SEARCH_CHECK_RG rg)" || exit 2
same_file() { /usr/bin/perl -MCwd=abs_path -e 'exit(abs_path($ARGV[0]) eq abs_path($ARGV[1]) ? 0 : 1)' "$1" "$2"; }
same_file "$EXT_RG" "$bin" && { echo "the standalone rg, $EXT_RG, is the binary under test: install ripgrep (pkgsrc's, say), or set SEARCH_CHECK_RG to it" >&2; exit 2; }
EXT_UGREP="$(ext_tool SEARCH_CHECK_UGREP ugrep)" || exit 2
EXT_BFS="$(ext_tool SEARCH_CHECK_BFS bfs)" || exit 2
SHARE=/usr/share
CACHE="${SEARCH_CHECK_CACHE:-$HOME/.claude/plugins/cache}"
SHARE_PAT=license
CACHE_PAT=skill
RG_RUNS=60
TIMED_RUNS=10
MAX_RATIO=2.0

for _t in /usr/bin/grep /usr/bin/find /usr/bin/perl /usr/bin/otool; do
  [ -x "$_t" ] || { echo "missing $_t" >&2; exit 2; }
done
/usr/bin/otool -L "$bin" | grep -q '/libavxemu\.dylib ' || { echo "$bin does not link libavxemu.dylib: give it the patched binary" >&2; exit 2; }
CACHE="$(CDPATH= cd "$CACHE" 2>/dev/null && pwd)" || { echo "no such directory: ${SEARCH_CHECK_CACHE:-$HOME/.claude/plugins/cache}" >&2; exit 2; }
mkdir -p "$out" || exit 2
out="$(cd "$out" && pwd -P)"
marker="$out/search-check.outdir"
if [ ! -f "$marker" ] && [ -n "$(ls -A "$out")" ]; then
  echo "refusing $out: not empty, and no $marker from an earlier run" >&2
  exit 2
fi
printf 'search-check.sh writes here\n' > "$marker" || exit 2
home="$out/search-check.home"
avxcache="$home/Library/Caches/avxemu"
work="$out/search-check.work"
rm -rf "$work" "$home"
mkdir -p "$home/Library/Caches" "$work" || exit 2
rows="$work/rows"
details="$work/details"
: > "$rows"
: > "$details"
rg_bad=0; ug_bad=0; bfs_bad=0; rg_slow=0; ug_slow=0; bfs_slow=0

say() { printf '%s\n' "$*"; }
row() { printf '| %s | %s | %s |\n' "$1" "$2" "$3" >> "$rows"; }
verdict() { if [ "$1" -eq 0 ]; then echo PASS; else echo FAIL; fi; }
csort() { LC_ALL=C sort -o "$1" "$1"; }
lines() { if [ -r "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
in_scratch() { env -i HOME="$home" PATH=/usr/bin:/bin AVXEMU_CACHE_DIR="$avxcache" "$@"; }

run() {
  _ro="$1"; _re="$2"; shift 2
  in_scratch /usr/bin/perl -e 'alarm 600; exec {$ARGV[0]} @ARGV[1..$#ARGV] or exit 127' "$@" > "$_ro" 2> "$_re"
}

status_text() {
  if [ "$1" -gt 128 ]; then printf 'status %s (signal %s)' "$1" "$(($1 - 128))"; else printf 'status %s' "$1"; fi
}

classify() {
  /usr/bin/perl -e '
    my ($root, $allowed) = @ARGV;
    my %ok = map { $_ => 1 } split /,/, $allowed;
    while (my $p = <STDIN>) {
      chomp $p;
      my $why = "";
      if (index($p, "$root/") == 0) {
        my $cur = $root;
        for my $c (grep { length } split m{/}, substr($p, length($root) + 1)) {
          $cur .= "/$c";
          if (-l $cur) { $why = "symlink"; last }
          if ($c =~ /^\./) { $why = "hidden"; last }
        }
      }
      if ($why eq "" && $ok{binary} && open(my $fh, "<", $p)) {
        binmode $fh;
        local $/;
        my $body = readline $fh;
        $why = "binary" if defined $body && index($body, "\0") >= 0;
      }
      $why = "unexplained" if $why eq "" || !$ok{$why};
      print "$why\t$p\n";
    }' "$1" "$2"
}

compare_lists() {
  _label="$1"; _root="$2"; _a="$3"; _an="$4"; _aok="$5"; _b="$6"; _bn="$7"; _bok="$8"
  _df="$work/diff-$(printf %s "$_label" | tr -c 'A-Za-z0-9' '-')"
  LC_ALL=C comm -23 "$_a" "$_b" | classify "$_root" "$_aok" | sed "s|^|only $_an	|" > "$_df"
  LC_ALL=C comm -13 "$_a" "$_b" | classify "$_root" "$_bok" | sed "s|^|only $_bn	|" >> "$_df"
  _n="$(lines "$_df")"
  _u="$(grep -c '	unexplained	' "$_df")"
  {
    printf '\n### %s: %s differences, %s unexplained\n\n' "$_label" "$_n" "$_u"
    if [ "$_n" -gt 0 ]; then
      printf 'By side and reason:\n\n```\n'
      cut -f1,2 "$_df" | sort | uniq -c
      printf '```\n\nEach difference (side, reason, path):\n\n```\n'
      cat "$_df"
      printf '```\n'
    fi
  } >> "$details"
  printf '%s differences (%s unexplained)' "$_n" "$_u"
  [ "$_u" -eq 0 ]
}

time_runs() {
  _tl="$1"; shift
  in_scratch /usr/bin/perl -MTime::HiRes=time -e '
    my $sink = shift;
    my $n = shift;
    for my $i (0 .. $n) {
      my $t = time;
      my $pid = fork;
      die "fork: $!\n" unless defined $pid;
      if ($pid == 0) {
        open STDOUT, ">", $sink or exit 126;
        open STDERR, ">", "/dev/null";
        alarm 600;
        exec {$ARGV[0]} @ARGV[1 .. $#ARGV];
        exit 127;
      }
      waitpid $pid, 0;
      printf "%.4f %d\n", time - $t, $?;
    }' "$work/time-$_tl.out" "$TIMED_RUNS" "$@" > "$work/time-$_tl"
}

time_summary() {
  /usr/bin/perl -e '
    my @l = map { [split] } grep { /\S/ } readline STDIN;
    my $bad = $ARGV[0] > @l ? $ARGV[0] - @l : 0;
    $bad += grep { $_->[1] != 0 } @l;
    my $cold = @l ? (shift @l)->[0] : 0;
    my @t = sort { $a <=> $b } map { $_->[0] } @l;
    my $m = !@t ? 0 : @t % 2 ? $t[$#t / 2] : ($t[@t / 2 - 1] + $t[@t / 2]) / 2;
    printf "%.4f %.4f %d\n", $cold, $m, $bad;' "$((TIMED_RUNS + 1))" < "$work/time-$1"
}

say "search-check: binary $bin"
{
  printf '# Built-in search check\n\n'
  printf -- '- Date: %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  printf -- '- Host: Mac OS X %s, %s\n' "$(sw_vers -productVersion 2>/dev/null)" "$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
  if sysctl -n machdep.cpu.leaf7_features 2>/dev/null | grep -qw AVX2; then printf -- '- AVX2: present\n'; else printf -- '- AVX2: absent\n'; fi
  printf -- '- Binary: `%s`, sha256 `%s`, `%s`\n' "$bin" "$(shasum -a 256 "$bin" | cut -d' ' -f1)" "$(in_scratch "$bin" --version 2>&1 | head -n 1)"
  printf -- '- Linked: %s\n' "$(otool -L "$bin" | sed -n '2,$p' | sed 's/^[[:space:]]*//; s/ (.*//' | tr '\n' ' ')"
  for _t in rg ugrep bfs; do
    run "$work/v" "$work/v.err" "$bin" "$_t" --version
    printf -- '- Built-in %s: %s\n' "$_t" "$(head -n 1 "$work/v")"
  done
  for _t in rg:"$EXT_RG" ugrep:"$EXT_UGREP" bfs:"$EXT_BFS"; do
    run "$work/v" "$work/v.err" "${_t#*:}" "${_t%%:*}" --version
    printf -- '- External `%s`: %s\n' "${_t#*:}" "$(head -n 1 "$work/v")"
  done
  printf -- '- Every run: `env -i HOME=%s PATH=/usr/bin:/bin AVXEMU_CACHE_DIR=%s`, under `alarm 600`\n' "$home" "$avxcache"
  printf -- "- The scratch HOME has Library/Caches, as an account does, and avxemu keeps its load-time analysis cache in AVXEMU_CACHE_DIR there. The cache is emptied before each timed series of a built-in tool, so its cold run starts without it\n"
  printf -- '- Patterns: `%s` over `%s`, `%s` over `%s`\n' "$SHARE_PAT" "$SHARE" "$CACHE_PAT" "$CACHE"
} > "$work/head"

say "search-check: rg correctness, $RG_RUNS runs over $SHARE"
run "$work/rg-ext" "$work/rg-ext.err" "$EXT_RG" rg -l "$SHARE_PAT" "$SHARE"; _st=$?
csort "$work/rg-ext"
if [ "$_st" -eq 0 ]; then
  row "external rg -l $SHARE_PAT $SHARE" ok "$(lines "$work/rg-ext") files"
else
  rg_bad=1
  row "external rg -l $SHARE_PAT $SHARE" FAIL "$(status_text "$_st")"
fi
run "$work/grep" "$work/grep.err" /usr/bin/grep grep -rl "$SHARE_PAT" "$SHARE"; _st=$?
csort "$work/grep"
row "/usr/bin/grep -rl $SHARE_PAT $SHARE" "$(if [ "$_st" -eq 0 ]; then echo ok; else echo FAIL; fi)" "$(lines "$work/grep") files, $(status_text "$_st")"
[ "$_st" -eq 0 ] || rg_bad=1

clean=0; same=0; i=1
: > "$work/rg-failures"
while [ "$i" -le "$RG_RUNS" ]; do
  run "$work/rg-run" "$work/rg-run.err" "$bin" rg -l "$SHARE_PAT" "$SHARE"; _st=$?
  csort "$work/rg-run"
  _ok=1
  if [ "$_st" -eq 0 ] || [ "$_st" -eq 1 ]; then clean=$((clean + 1)); else _ok=0; fi
  if cmp -s "$work/rg-run" "$work/rg-ext"; then same=$((same + 1)); else _ok=0; fi
  if [ "$_ok" -eq 0 ]; then
    cp "$work/rg-run" "$work/rg-run-$i"
    cp "$work/rg-run.err" "$work/rg-run-$i.err"
    printf 'run %s: %s, %s files, %s lines differ from external rg, stderr: %s\n' "$i" "$(status_text "$_st")" \
      "$(lines "$work/rg-run")" "$(LC_ALL=C comm -3 "$work/rg-run" "$work/rg-ext" | wc -l | tr -d ' ')" \
      "$(head -c 200 "$work/rg-run.err" | tr '\n' ' ')" >> "$work/rg-failures"
  fi
  i=$((i + 1))
done
if [ "$clean" -eq "$RG_RUNS" ] && [ "$same" -eq "$RG_RUNS" ]; then _r=PASS; else _r=FAIL; rg_bad=1; fi
row "built-in rg -l $SHARE_PAT $SHARE, $RG_RUNS runs" "$_r" "$clean/$RG_RUNS clean, $same/$RG_RUNS identical to external rg"
if [ -s "$work/rg-failures" ]; then
  { printf '\n### built-in rg runs that failed\n\n```\n'; cat "$work/rg-failures"; printf '```\n'; } >> "$details"
fi
if _d="$(compare_lists "rg vs grep" "$SHARE" "$work/rg-ext" rg "" "$work/grep" grep symlink,hidden,binary)"; then _r=PASS; else _r=FAIL; rg_bad=1; fi
row "rg -l against grep -rl" "$_r" "$_d"

say "search-check: ugrep correctness over $CACHE"
run "$work/ug" "$work/ug.err" "$bin" ugrep -r -c --include='*.md' "$CACHE_PAT" "$CACHE"; _ust=$?
run "$work/gc" "$work/gc.err" /usr/bin/find find "$CACHE" -name '*.md' -type f -exec /usr/bin/grep -H -c "$CACHE_PAT" {} ';'; _gst=$?
_sumok=1
: > "$work/ug-paths"; : > "$work/gc-paths"; : > "$work/ug-counts"
/usr/bin/perl -e '
  my ($u, $g, $w) = @ARGV;
  my (%u, %g);
  for ([$u, \%u], [$g, \%g]) {
    my ($f, $h) = @$_;
    open my $fh, "<", $f or die "$f: $!\n";
    while (my $l = readline $fh) { chomp $l; $l =~ /^(.*):(\d+)$/ or next; $h->{$1} = $2 }
  }
  open my $pu, ">", "$w/ug-paths" or die; open my $pg, ">", "$w/gc-paths" or die; open my $m, ">", "$w/ug-counts" or die;
  for (sort keys %u) { print $pu "$_\n"; print $m "$_: ugrep $u{$_}, grep $g{$_}\n" if exists $g{$_} && $g{$_} != $u{$_} }
  for (sort keys %g) { print $pg "$_\n" }
  printf "%d %d %d\n", scalar(keys %u), scalar(keys %g), scalar(grep { exists $g{$_} } keys %u);
' "$work/ug" "$work/gc" "$work" > "$work/ug-sum" 2>> "$work/ug.err" || _sumok=0
read -r _un _gn _both < "$work/ug-sum" || _sumok=0
: "${_un:=0}" "${_gn:=0}" "${_both:=0}"
csort "$work/ug-paths"; csort "$work/gc-paths"
_mis="$(lines "$work/ug-counts")"
if [ "$_sumok" -eq 1 ] && [ "$_ust" -eq 0 ] && [ "$_gst" -eq 0 ] && [ "$_mis" -eq 0 ] && [ "$_both" -gt 0 ]; then _r=PASS; else _r=FAIL; ug_bad=1; fi
row "built-in ugrep -r -c --include='*.md' $CACHE_PAT against grep -c per file" "$_r" "ugrep $(status_text "$_ust"), $_un files; grep $(status_text "$_gst"), $_gn files; $_both in both, $_mis with a different count"
if [ "$_mis" -gt 0 ]; then
  { printf '\n### ugrep counts that differ from grep\n\n```\n'; cat "$work/ug-counts"; printf '```\n'; } >> "$details"
fi
if _d="$(compare_lists "ugrep vs grep files" "$CACHE" "$work/ug-paths" ugrep "" "$work/gc-paths" grep hidden,symlink)"; then _r=PASS; else _r=FAIL; ug_bad=1; fi
row "ugrep files against grep files" "$_r" "$_d"

for _k in cache share; do
  if [ "$_k" = share ]; then _tree="$SHARE"; else _tree="$CACHE"; fi
  say "search-check: bfs correctness over $_tree"
  run "$work/bfs-$_k" "$work/bfs-$_k.err" "$bin" bfs "$_tree" -type f; _bst=$?
  run "$work/find-$_k" "$work/find-$_k.err" /usr/bin/find find "$_tree" -type f; _fst=$?
  csort "$work/bfs-$_k"; csort "$work/find-$_k"
  _d="$(compare_lists "bfs vs find, $_tree" "$_tree" "$work/bfs-$_k" bfs "" "$work/find-$_k" find hidden,symlink)"; _cst=$?
  if [ "$_bst" -eq 0 ] && [ "$_fst" -eq 0 ] && [ "$_cst" -eq 0 ]; then _r=PASS; else _r=FAIL; bfs_bad=1; fi
  row "built-in bfs $_tree -type f against find" "$_r" "bfs $(status_text "$_bst"), $(lines "$work/bfs-$_k") files; find $(status_text "$_fst"), $(lines "$work/find-$_k") files; $_d"
done

: > "$work/perf"
for _tool in rg ugrep bfs; do
  case "$_tool" in
    rg) _ext="$EXT_RG" ;;
    ugrep) _ext="$EXT_UGREP" ;;
    bfs) _ext="$EXT_BFS" ;;
  esac
  for _k in cache share; do
    if [ "$_k" = share ]; then _tree="$SHARE"; _p="$SHARE_PAT"; else _tree="$CACHE"; _p="$CACHE_PAT"; fi
    case "$_tool" in
      rg) set -- -l "$_p" "$_tree"; _q="rg -l $_p $_tree" ;;
      ugrep) set -- -r -l "$_p" "$_tree"; _q="ugrep -r -l $_p $_tree" ;;
      bfs) set -- "$_tree" -type f; _q="bfs $_tree -type f" ;;
    esac
    say "search-check: timing $_q"
    rm -rf "$avxcache"
    time_runs "$_tool-$_k-builtin" "$bin" "$_tool" "$@"
    time_runs "$_tool-$_k-external" "$_ext" "$_tool" "$@"
    read -r _bc _bm _bb <<EOF
$(time_summary "$_tool-$_k-builtin")
EOF
    read -r _ec _em _eb <<EOF
$(time_summary "$_tool-$_k-external")
EOF
    _bo="$work/time-$_tool-$_k-builtin.out"; _eo="$work/time-$_tool-$_k-external.out"
    if [ "$_tool" = ugrep ]; then csort "$_bo"; csort "$_eo"; fi
    _bl="$(lines "$_bo")"; _el="$(lines "$_eo")"
    _out="$_bl and $_el lines"
    if [ "$_bl" -eq 0 ] || [ "$_el" -eq 0 ]; then
      _out="$_out, empty"; _bb=$((_bb + 1))
    elif [ "$_tool" = ugrep ]; then
      if ! cmp -s "$_bo" "$_eo" && ! _d="$(compare_lists "ugrep timing output, $_tree" "$_tree" "$_bo" built-in hidden,symlink,binary "$_eo" external hidden,symlink,binary)"; then
        _out="$_out, different files: $_d"; _bb=$((_bb + 1))
      fi
    elif [ "$_bl" -ne "$_el" ]; then
      _out="$_out, different"; _bb=$((_bb + 1))
    fi
    read -r _ratio _slow <<EOF
$(/usr/bin/perl -e 'my $r = $ARGV[1] > 0 ? $ARGV[0] / $ARGV[1] : 999; printf "%.2f %d\n", $r, $r <= $ARGV[2] ? 0 : 1' "$_bm" "$_em" "$MAX_RATIO")
EOF
    _r=PASS
    if [ "$_bb" -ne 0 ] || [ "$_eb" -ne 0 ]; then
      _r=FAIL
      case "$_tool" in rg) rg_bad=1 ;; ugrep) ug_bad=1 ;; bfs) bfs_bad=1 ;; esac
    fi
    if [ "$_slow" -ne 0 ]; then
      if [ "$_r" = PASS ]; then _r=SLOW; else _r="FAIL, SLOW"; fi
      case "$_tool" in rg) rg_slow=1 ;; ugrep) ug_slow=1 ;; bfs) bfs_slow=1 ;; esac
    fi
    printf '| `%s` | %s | %s | %s | %s | %s | %s | %s | %s |\n' "$_q" "$_bc" "$_bm" "$_ec" "$_em" "$_ratio" "$_out" "$((_bb + _eb))" "$_r" >> "$work/perf"
  done
done

{
  cat "$work/head"
  printf '\n## Results\n\n'
  printf -- '- rg: correctness %s, speed %s\n- ugrep: correctness %s, speed %s\n- bfs: correctness %s, speed %s\n' \
    "$(verdict $rg_bad)" "$(verdict $rg_slow)" "$(verdict $ug_bad)" "$(verdict $ug_slow)" "$(verdict $bfs_bad)" "$(verdict $bfs_slow)"
  printf '\n## Correctness\n\n| check | result | numbers |\n|---|---|---|\n'
  cat "$rows"
  printf '\n## Performance\n\nEach search runs once as a warm-up (reported as cold), then %s timed runs (median); seconds, wall clock, perl Time::HiRes. A row is SLOW, a speed failure, when built-in median / external median > %s (the ratio shown is rounded); it is FAIL, a correctness failure, when a run exited non-zero or its output disagreed. The last run of each series must leave non-empty output that agrees with the other tool: the same number of lines for rg and bfs, and for ugrep the same files, or files that only hidden directories, symlinks or binary content explain (ugrep versions differ). A mismatch counts as a failed run.\n\n' "$TIMED_RUNS" "$MAX_RATIO"
  printf '| search | built-in cold | built-in median | external cold | external median | ratio | last output (built-in and external) | failed runs | result |\n|---|---|---|---|---|---|---|---|---|\n'
  cat "$work/perf"
  printf '\n## Differences\n'
  if [ -s "$details" ]; then cat "$details"; else printf '\nNone.\n'; fi
} > "$out/report.md"

say "search-check: report $out/report.md"
for _t in rg:$rg_bad:$rg_slow ugrep:$ug_bad:$ug_slow bfs:$bfs_bad:$bfs_slow; do
  _n="${_t%%:*}"; _f="${_t#*:}"
  say "search-check: $_n correctness $(verdict "${_f%:*}")"
  say "search-check: $_n speed $(verdict "${_f#*:}")"
done
[ $((rg_bad + ug_bad + bfs_bad)) -eq 0 ] || exit 1
[ $((rg_slow + ug_slow + bfs_slow)) -eq 0 ] || exit 3
