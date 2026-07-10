use strict; use warnings;
use Test::More;
use File::Temp ();
use File::Path ();

# Perl-only end-to-end build test: build the in-repo sample projects with the
# tool and validate the resulting package with pkgutil/lsbom (no Python).
my $PL = "./munkipkg";
my $repo = ".";

sub build_project {
    my ($name) = @_;
    my $dir = File::Temp::tempdir(CLEANUP => 1);
    system("cp -R '$repo/$name' '$dir/proj' && rm -rf '$dir/proj/build'");
    my $rc = system("perl '$PL' --quiet '$dir/proj' >/dev/null 2>&1");
    return ($rc >> 8, "$dir/proj");
}

sub expand {
    my ($pkg) = @_;
    my $out = File::Temp::tempdir(CLEANUP => 1) . "/x";
    system("pkgutil --expand '$pkg' '$out' >/dev/null 2>&1");
    return $out;
}

# Component package: TurnOffBluetooth (scripts-only, distribution_style false)
{
    my ($rc, $proj) = build_project("TurnOffBluetooth");
    is($rc, 0, "TurnOffBluetooth builds");
    my ($pkg) = glob("$proj/build/*.pkg");
    ok($pkg && -f $pkg, "component pkg produced");
    my $x = expand($pkg);
    ok(-f "$x/PackageInfo", "component pkg has top-level PackageInfo");
    my $pi = do { local $/; open my $f, '<', "$x/PackageInfo"; <$f> };
    like($pi, qr/com\.github\.munki\.pkg\.TurnOffBluetooth/, "PackageInfo has identifier");
}

# Distribution package: SuppressSetupAssistant (distribution_style true, has title)
{
    my ($rc, $proj) = build_project("SuppressSetupAssistant");
    is($rc, 0, "SuppressSetupAssistant builds");
    my ($pkg) = glob("$proj/build/*.pkg");
    ok($pkg && -f $pkg, "distribution pkg produced");
    my $x = expand($pkg);
    ok(-f "$x/Distribution", "distribution pkg has Distribution file");
    my $dist = do { local $/; open my $f, '<', "$x/Distribution"; <$f> };
    like($dist, qr/<title>/, "Distribution has a title");
    my ($nested) = glob("$x/*.pkg");
    ok($nested && -d $nested, "distribution pkg wraps a component pkg");
    ok(-f "$nested/PackageInfo", "nested component has PackageInfo");
}

done_testing;
