use strict; use warnings;
use Test::More;
use JSON::PP;
use File::Path ();
require './munkipkg';

# script_names
is_deeply([main::script_names('pre')],  ['preflight','preinstall','preupgrade'], "pre names");
is_deeply([main::script_names('post')], ['postflight','postinstall','postupgrade'], "post names");
is(scalar(() = main::script_names()), 6, "all names");

# convert_info_plist maps CFBundle* + restart action into build-info
my $pd = "/tmp/mp_bundle.$$"; mkdir $pd;
my $fake_pkg = "/tmp/mp_fakepkg.$$.pkg"; File::Path::make_path("$fake_pkg/Contents");
main::writePlist({
    CFBundleIdentifier => "com.x",
    CFBundleShortVersionString => "3.2",
    IFPkgFlagDefaultLocation => "/opt",
    IFPkgFlagRestartAction => "RequiredRestart",
}, "$fake_pkg/Contents/Info.plist");
{
    no warnings 'once';
    local %main::options = (quiet => 1, json => 0, yaml => 0);
    main::convert_info_plist($fake_pkg, $pd);
}
my $bi = main::readPlist("$pd/build-info.plist");
is($bi->{identifier}, "com.x", "identifier from Info.plist");
is($bi->{version}, "3.2", "short version preferred");
is($bi->{install_location}, "/opt", "install location");
is($bi->{postinstall_action}, "restart", "restart action mapped");

# logout mapping + CFBundleVersion fallback
my $pd2 = "/tmp/mp_bundle2.$$"; mkdir $pd2;
my $fake2 = "/tmp/mp_fakepkg2.$$.pkg"; File::Path::make_path("$fake2/Contents");
main::writePlist({
    CFBundleIdentifier => "com.y",
    CFBundleVersion => "9",
    IFPkgFlagRestartAction => "RequiredLogout",
}, "$fake2/Contents/Info.plist");
{
    no warnings 'once';
    local %main::options = (quiet => 1, json => 0, yaml => 0);
    main::convert_info_plist($fake2, $pd2);
}
my $bi2 = main::readPlist("$pd2/build-info.plist");
is($bi2->{version}, "9", "CFBundleVersion fallback");
is($bi2->{install_location}, "/", "default install location");
is($bi2->{postinstall_action}, "logout", "logout action mapped");

File::Path::remove_tree($pd, $pd2, $fake_pkg, $fake2);
done_testing;
