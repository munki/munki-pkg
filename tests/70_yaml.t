use strict; use warnings;
use Test::More;
use File::Temp ();
use File::Path ();

# Perl-only end-to-end test that a YAML build-info project builds correctly:
# exercises YAML auto-detection, YAML parsing, boolean coercion, and build.
my $PL = "./munkipkg";

my $dir = File::Temp::tempdir(CLEANUP => 1);
my $proj = "$dir/YamlProj";
File::Path::make_path("$proj/payload/Library/Preferences", "$proj/scripts");
open my $p, '>', "$proj/payload/Library/Preferences/com.example.plist"; print $p "x"; close $p;

open my $y, '>', "$proj/build-info.yaml";
print $y <<'YAML';
---
distribution_style: false
identifier: com.example.yamltest
install_location: /
name: YamlTest.pkg
ownership: recommended
postinstall_action: none
preserve_xattr: false
suppress_bundle_relocation: true
version: 2.0
YAML
close $y;

# No --yaml flag: build should auto-detect the build-info.yaml file.
my $rc = system("perl '$PL' --quiet '$proj' >/dev/null 2>&1");
is($rc >> 8, 0, "builds from a YAML build-info (auto-detected)");
my ($pkg) = glob("$proj/build/*.pkg");
ok($pkg && -f $pkg, "pkg produced: YamlTest.pkg");

my $x = File::Temp::tempdir(CLEANUP => 1) . "/x";
system("pkgutil --expand '$pkg' '$x' >/dev/null 2>&1");
ok(-f "$x/PackageInfo", "component pkg (distribution_style:false honored) has top-level PackageInfo");
my $pi = do { local $/; open my $f, '<', "$x/PackageInfo"; <$f> };
like($pi, qr/com\.example\.yamltest/, "identifier from YAML used");
like($pi, qr/version="2\.0"/, "version from YAML used");

done_testing;
