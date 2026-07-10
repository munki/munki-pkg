use strict; use warnings;
use Test::More;

# Perl-only CLI behaviour tests. No external oracle.
my $PL = "./munkipkg";

sub run {
    my (@args) = @_;
    my $out = "/tmp/o.$$"; my $err = "/tmp/e.$$";
    system("perl '$PL' " . join(" ", @args) . " >$out 2>$err");
    my $r = $? >> 8;
    local $/;
    open my $fo, '<', $out; my $o = <$fo>; close $fo;
    open my $fe, '<', $err; my $e = <$fe>; close $fe;
    unlink $out, $err;
    return ($o // '', $e // '', $r);
}

my $USAGE = "Usage: munkipkg [options] pkg_project_directory\n"
          . "       A tool for building a package from the contents of a\n"
          . "       pkg_project_directory.\n";

# no args: usage to stdout + blank line, exit 0
my ($o, $e, $r) = run();
is($r, 0, "no args exits 0");
is($o, $USAGE . "\n", "no args prints usage");

# --version
($o, $e, $r) = run('--version');
is($r, 0, "--version exits 0");
is($o, "1.0\n", "--version prints 1.0");

# --help: usage header + options block
($o, $e, $r) = run('--help');
is($r, 0, "--help exits 0");
like($o, qr/^Usage: munkipkg \[options\] pkg_project_directory\n/, "help starts with usage");
like($o, qr/\nOptions:\n/, "help has Options section");
like($o, qr/  --create /, "help lists --create");
like($o, qr/  --import=PKG /, "help lists --import");
like($o, qr/  --skip-stapling /, "help lists --skip-stapling");

# too many args
($o, $e, $r) = run('a', 'b');
is($r, 255, ">1 arg exits 255");
is($e, "ERROR: Only a single package project can be built at a time!\n", "multi-arg error");

# json + yaml conflict
($o, $e, $r) = run('--json', '--yaml', 'x');
is($r, 255, "json+yaml exits 255");
is($e, "ERROR: Only a single build-info file can be built at a time!\n", "conflict error");

done_testing;
