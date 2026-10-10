# platform: macOS-only -- canonical paths for the readlink and realpath shims, in Mac OS X 10.9's perl 5.16
#   canonical(PATH, MODE, FOLLOW) returns PATH made absolute, without . or .., and with symlinks followed
#   if FOLLOW, or (undef, why) on failure. MODE is GNU's: 'e' every component must exist, 'f' every one
#   but the last, 'm' none.
use strict;
use warnings;
use Cwd ();

sub canonical {
    my ($path, $mode, $follow) = @_;
    my @todo = grep { length } split m{/}, $path;
    my @done = $path =~ m{^/} ? () : grep { length } split m{/}, Cwd::getcwd();
    my $links = 0;
    while (@todo) {
        my $c = shift @todo;
        next if $c eq '.';
        if ($c eq '..') { pop @done; next }
        my $p = join '/', '', @done, $c;
        if ($follow && -l $p) {
            return (undef, 'Too many levels of symbolic links') if ++$links > 40;
            my $t = readlink $p;
            @done = () if $t =~ m{^/};
            unshift @todo, grep { length } split m{/}, $t;
        } elsif (-e $p) {
            return (undef, 'Not a directory') if @todo && !-d $p && $mode ne 'm';
            push @done, $c;
        } elsif ($mode eq 'e' || ($mode eq 'f' && @todo)) {
            return (undef, 'No such file or directory');
        } else {
            push @done, $c;
        }
    }
    return join('/', '', @done) || '/';
}

1;
