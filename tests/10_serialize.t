use strict; use warnings;
use Test::More;
use JSON::PP;
require './munkipkg';

# --- plist: format assertions + round-trip fidelity (no external oracle) ---
my $tmp = "/tmp/mp_ser.$$.plist";
my $data = {
    identifier         => "com.example.foo",
    preserve_xattr     => JSON::PP::true,
    distribution_style => JSON::PP::false,
    version            => "1.0",
    answer             => 42,
    signing_info       => { identity => "Me", timestamp => JSON::PP::true },
    certs              => ["a", "b"],
};
main::writePlist($data, $tmp);
my $raw = do { local $/; open my $f, '<', $tmp; <$f> };

like($raw, qr{^<\?xml version="1\.0" encoding="UTF-8"\?>\n}, "XML declaration");
like($raw, qr{<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1\.0//EN"}, "plist DOCTYPE");
like($raw, qr{<key>preserve_xattr</key>\n\t<true/>}, "true boolean emitted as <true/>");
like($raw, qr{<key>distribution_style</key>\n\t<false/>}, "false boolean emitted as <false/>");
like($raw, qr{<key>answer</key>\n\t<integer>42</integer>}, "integer emitted as <integer>");
like($raw, qr{<key>version</key>\n\t<string>1\.0</string>}, "string '1.0' stays <string>");
# keys are sorted (answer < certs < distribution_style < identifier ...)
ok(index($raw, "<key>answer</key>") < index($raw, "<key>certs</key>"), "keys sorted");

# round-trip preserves data + types
my $back = main::readPlist($tmp);
is($back->{identifier}, "com.example.foo", "string round-trips");
ok(JSON::PP::is_bool($back->{preserve_xattr}) && $back->{preserve_xattr}, "true bool preserved");
ok(JSON::PP::is_bool($back->{distribution_style}) && !$back->{distribution_style}, "false bool preserved");
is($back->{answer}, 42, "integer round-trips");
is($back->{signing_info}{identity}, "Me", "nested dict");
is_deeply($back->{certs}, ["a", "b"], "array round-trips");

# top-level array plist (component.plist shape)
my $arr_tmp = "/tmp/mp_arr.$$.plist";
main::writePlist([ { BundleIsRelocatable => JSON::PP::true, RootRelativeBundlePath => "Foo.app" } ], $arr_tmp);
my $arr = main::readPlist($arr_tmp);
is(ref $arr, 'ARRAY', "top-level array read as arrayref");
ok(JSON::PP::is_bool($arr->[0]{BundleIsRelocatable}), "array-of-dict bool preserved");

# readPlistFromString
my $fromstr = main::readPlistFromString($raw);
is($fromstr->{identifier}, "com.example.foo", "readPlistFromString parses bytes");

unlink $tmp, $arr_tmp;

# --- JSON: exact expected output (Python json.dump indent=4, sorted keys) ---
my $js = main::json_encode_buildinfo({ b => "two", a => 1, flag => JSON::PP::true });
is($js, qq({\n    "a": 1,\n    "b": "two",\n    "flag": true\n}), "json output exact");
my $rt = main::json_decode($js);
is($rt->{b}, "two", "json round-trip string");
ok(JSON::PP::is_bool($rt->{flag}) && $rt->{flag}, "json round-trip bool");

# --- YAML: must be available on stock macOS, and booleans must be clean ---
{
    no warnings 'once';
    ok($main::YAML_INSTALLED, "YAML module detected (stock macOS)");
    my $y = main::yaml_dump({ name => "Foo", count => 3,
                              distribution_style => JSON::PP::false,
                              suppress_bundle_relocation => JSON::PP::true });
    like($y, qr/^distribution_style: false$/m, "bool dumped as bare 'false' (PyYAML-compatible)");
    like($y, qr/^suppress_bundle_relocation: true$/m, "bool dumped as bare 'true'");
    unlike($y, qr/perl\/scalar|JSON::PP::Boolean/, "no Perl object tags in YAML output");
    my $yl = main::yaml_load($y);
    is($yl->{name}, "Foo", "yaml round-trip string");
    is($yl->{count}, 3, "yaml round-trip number");
    # booleans come back as strings from YAML.pm; the build-info coercion fixes them
    my $bi = { distribution_style => "false", suppress_bundle_relocation => "true",
               preserve_xattr => "false" };
    main::_coerce_build_info_bools($bi);
    ok(JSON::PP::is_bool($bi->{distribution_style}) && !$bi->{distribution_style}, "coerced false");
    ok(JSON::PP::is_bool($bi->{suppress_bundle_relocation}) && $bi->{suppress_bundle_relocation}, "coerced true");
}

done_testing;
