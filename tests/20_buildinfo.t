use strict; use warnings;
use Test::More;
use JSON::PP;
require './munkipkg';

# default_build_info parity vs Python default_build_info
my $dir = "/tmp/mp_proj.$$/Foo Bar";
my $info = main::default_build_info($dir);
is($info->{name}, 'FooBar-${version}.pkg', "name basename strips spaces");
is($info->{identifier}, "com.github.munki.pkg.FooBar", "identifier");
is($info->{ownership}, "recommended", "default ownership");
is($info->{install_location}, "/", "default install_location");
is($info->{version}, "1.0", "default version");
ok(JSON::PP::is_bool($info->{suppress_bundle_relocation}) && $info->{suppress_bundle_relocation}, "suppress default true");
ok(JSON::PP::is_bool($info->{distribution_style}) && !$info->{distribution_style}, "dist default false");
ok(JSON::PP::is_bool($info->{preserve_xattr}) && !$info->{preserve_xattr}, "preserve_xattr default false");

# validate_build_info_keys
is(main::validate_build_info_keys({ compression => "nope" }, "x.plist"), 0, "bad compression rejected");
is(main::validate_build_info_keys({ compression => "latest" }, "x.plist"), 1, "good compression ok");
is(main::validate_build_info_keys({ ownership => "preserve" }, "x.plist"), 1, "good ownership ok");
is(main::validate_build_info_keys({ preserve_xattr => "yes" }, "x.plist"), 0, "non-bool preserve_xattr rejected");
is(main::validate_build_info_keys({ preserve_xattr => JSON::PP::true }, "x.plist"), 1, "bool preserve_xattr ok");

# ${version} substitution (via the finalize seam)
my $sub = { name => 'App-${version}.pkg', version => '2.5', title => 'App ${version}' };
main::_finalize_build_info($sub);
is($sub->{name}, "App-2.5.pkg", "version subst in name");
is($sub->{title}, "App 2.5", "version subst in title");

# get_build_info / write_build_info round-trip through a real project dir (plist)
my $pd = "/tmp/mp_gbi.$$";
mkdir $pd;
{
    no warnings 'once';
    local %main::options = (json=>0, yaml=>0);
    my $bi = main::default_build_info($pd);
    main::write_build_info($bi, $pd);
    ok(-e "$pd/build-info.plist", "write_build_info wrote plist");
    my $got = main::get_build_info($pd);
    is($got->{identifier}, $bi->{identifier}, "get_build_info reads identifier");
    ok(JSON::PP::is_bool($got->{distribution_style}), "get_build_info preserves bool");
}

# --- display / run_subprocess helpers ---
{
    my $out = '';
    open my $cap, '>', \$out; my $old = select $cap;
    main::display("hello", 0, "munkipkg");
    select $old; close $cap;
    is($out, "munkipkg: hello\n", "display prints toolname: message");
}
{
    my $out = '';
    open my $cap, '>', \$out; my $old = select $cap;
    main::display("hi", 1, "munkipkg");
    select $old; close $cap;
    is($out, "", "display quiet suppresses");
}
{
    my ($rc, $so, $se) = main::run_subprocess(['/bin/echo', 'a b']);
    is($rc, 0, "echo rc 0");
    is($so, "a b\n", "stdout captured without shell splitting");
    ($rc, $so, $se) = main::run_subprocess(['/bin/sh', '-c', 'exit 3']);
    is($rc, 3, "nonzero rc captured");
}

done_testing;
