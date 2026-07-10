use strict; use warnings;
use Test::More;
use JSON::PP;
require './munkipkg';

no warnings 'once';
local %main::options = (quiet => 0, skip_signing => 0);

my $bi = {
    ownership => "recommended", identifier => "com.x", version => "1.0",
    pkginfo_path => "/tmp/PI", payload => "/tmp/pl", install_location => "/",
    component_plist => "/tmp/cp.plist", scripts => "/tmp/sc", build_dir => "/tmp/b",
    name => "X.pkg", compression => 'latest', 'min-os-version' => '11.0',
    'large-payload' => JSON::PP::true, distribution_style => JSON::PP::false,
    signing_info => {
        identity => "Dev ID", keychain => "/k.kc", timestamp => JSON::PP::true,
        additional_cert_names => ["Inter A", "Inter B"],
    },
};
my $cmd = main::build_pkg_cmd($bi);
my $s = join(" ", @$cmd);
like($s, qr{^/usr/bin/pkgbuild --ownership recommended --identifier com\.x --version 1\.0 --info /tmp/PI}, "leading args");
like($s, qr{--root /tmp/pl --install-location /}, "payload + install-location");
like($s, qr{--compression latest}, "compression");
like($s, qr{--component-plist /tmp/cp\.plist}, "component plist");
like($s, qr{--min-os-version 11\.0}, "min os");
like($s, qr{--large-payload}, "large payload flag");
like($s, qr{--scripts /tmp/sc}, "scripts");
like($s, qr{--sign Dev ID --keychain /k\.kc --cert Inter A --cert Inter B --timestamp}, "signing");
like($s, qr{/tmp/b/X\.pkg$}, "output path last");

# --nopayload path
my $np = main::build_pkg_cmd({ ownership=>"recommended", identifier=>"c", version=>"1",
    pkginfo_path=>"/PI", payload=>undef, distribution_style=>JSON::PP::false, name=>"N.pkg", build_dir=>"/b" });
like(join(" ",@$np), qr{--nopayload}, "nopayload when no payload");

# signing skipped when distribution_style true (dist pkg signs at productbuild)
my $ds = main::build_pkg_cmd({ ownership=>"recommended", identifier=>"c", version=>"1",
    pkginfo_path=>"/PI", payload=>"/pl", install_location=>"/", distribution_style=>JSON::PP::true,
    name=>"N.pkg", build_dir=>"/b", signing_info=>{identity=>"X"} });
unlike(join(" ",@$ds), qr{--sign}, "no signing in component cmd when distribution_style");

# --- distribution XML ---
my $x = main::distribution_xml({ name => "Foo.pkg", title => "My Title" });
like($x, qr{<title>My Title</title>}, "title element");
like($x, qr{hostArchitectures="arm64,x86_64"}, "host architectures");
like($x, qr{<pkg-ref id="default">Foo\.pkg</pkg-ref>}, "pkg-ref name");
unlike($x, qr/\n\z/, "no trailing newline (matches Python f-string)");
like(main::distribution_xml({ name => "Bar.pkg" }), qr{<title>Bar\.pkg</title>}, "title defaults to name");

# --- notarization auth options ---
{
    my @c; main::add_authentication_options(\@c,
        { notarization_info => { apple_id => 'a@b.com', team_id => 'T', password => 'p' } });
    is(join(" ", @c), "--apple-id a\@b.com --team-id T --password p", "apple-id auth args");
}
{
    my @c; main::add_authentication_options(\@c,
        { notarization_info => { keychain_profile => 'prof' } });
    is(join(" ", @c), "--keychain-profile prof", "keychain profile auth args");
}
{
    is(main::get_primary_bundle_id({ identifier => "com.a_b", notarization_info => {} }),
       "com.a-b", "underscore replaced in primary bundle id");
    is(main::get_primary_bundle_id({ identifier => "x", notarization_info => { primary_bundle_id => "my_id" } }),
       "my-id", "explicit primary_bundle_id underscore replaced");
}
{
    my $err = 0;
    eval { main::add_authentication_options([], { notarization_info => {} }); };
    like("$@", qr/must be specified in notarization_info/, "missing auth dies");
}

done_testing;
