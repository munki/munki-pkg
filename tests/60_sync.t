use strict; use warnings;
use Test::More;
use File::Temp ();
use File::Find ();

# Perl-only test for --export-bom-info and --sync. No external oracle.
my $PL = "./munkipkg";

# munki_kickstart has a payload file we can perturb and re-sync.
my $dir = File::Temp::tempdir(CLEANUP => 1);
system("cp -R munki_kickstart '$dir/proj' && rm -rf '$dir/proj/build'");
my $proj = "$dir/proj";

# --export-bom-info builds the pkg and writes Bom.txt
my $rc = system("perl '$PL' --quiet --export-bom-info '$proj' >/dev/null 2>&1");
is($rc >> 8, 0, "--export-bom-info succeeds");
ok(-f "$proj/Bom.txt", "Bom.txt written");

# find a payload file to perturb
my @files;
File::Find::find(sub { push @files, $File::Find::name if -f }, "$proj/payload");
ok(@files > 0, "payload has at least one file");
my $target = $files[0];

# perturb its mode, then sync
chmod 0600, $target;
is((stat $target)[2] & 07777, 0600, "mode perturbed to 0600");
my $out = `perl '$PL' '$proj' --sync 2>&1`;
is($? >> 8, 0, "--sync exits 0");

# the perturbed file's mode should be corrected (payload files are 0644 here)
my $mode = (stat $target)[2] & 07777;
isnt($mode, 0600, "sync changed the perturbed mode back");
like($out, qr/munkipkg: Changing mode of .* to 0o\d+/, "sync reports the mode change in Python format");
like($out, qr/munkipkg: Sync successful\./, "sync reports success");

# a second sync should report no changes needed
my $out2 = `perl '$PL' '$proj' --sync 2>&1`;
like($out2, qr/munkipkg: Sync successful: no changes needed\./, "idempotent second sync");

done_testing;
