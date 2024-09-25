# munkipkg

## Introduction

munkipkg is a tool for building packages in a consistent, repeatable manner from source files and scripts in a project directory.

While you can use munkipkg to generate packages for use with Munki (https://www.munki.org/munki/), the packages munkipkg builds are just normal Apple installer packages usable anywhere you can use Apple installer packages.

Files, scripts, and metadata are stored in a way that is easy to track and manage using a version control system like git.

**autopkg** (https://github.com/autopkg/autopkg) is another tool that has some overlap here. It's definitely possible to use autopkg to build packages from files and scripts on your local disk. See https://managingosx.wordpress.com/2015/07/30/using-autopkg-for-general-purpose-packaging/ and https://github.com/gregneagle/autopkg-packaging-demo for examples on how to do this.

So why consider using munkipkg? It's simple and self-contained, with no external dependencies. It can use JSON or YAML for its build settings file/data, instead of Makefile syntax or XML plists. It does not install a root-level system daemon as does autopkg. It can easily build distribution-style packages and can sign them. Finally, munkipkg can import existing packages.

## macOS and Python notes

munkipkg requires Python. It also uses several command-line tools available on macOS. There is no support for running these on Windows or Linux.

In macOS 12.3, Apple removed the Python 2.7 install. Out-of-the-box, there is no Python installed. You'll need to provide your own Python3 to use munkipkg.

Some options for providing an appropriate Python:

1) If you also use Munki, use Munki's bundled Python. You could make a symlink at /usr/local/bin/python3 pointing to `/usr/local/munki/munki-python` (this assumes `/usr/local/bin` is in your `PATH`, which it is by default. You could create symlink in any writable directory in your `PATH` if it differs)
2) Install Python from https://www.python.org. You might still need to create a symlink somewhere so that `/usr/bin/env python3` executes the Python you installed.
3) Install Apple's Python 3 by running `/usr/bin/python3` and accepting the prompt to install Python (if Xcode or the Xcode Command Line Tools are not already present).
4) There are other ways to install Python, including Homebrew (https://brew.sh), macadmins-python (https://github.com/macadmins/python), relocatable-python tool (https://github.com/gregneagle/relocatable-python), etc.

If you don't want to create a symlink or alter your PATH so that `/usr/bin/env python3` executes an appropriate Python for munkipkg, you can just call munkipkg _from_ the Python of your choice, eg: `/path/to/your/python3 /path/to/munkipkg [options]`

## Basic operation

munkipkg builds flat packages using Apple's `pkgbuild` and `productbuild` tools.

### Package project directories

munkipkg builds packages from a "package project directory". At its simplest, a package project directory is a directory containing a "payload" directory, which itself contains the files to be packaged. More typically, the directory also contains a "build-info.plist" file containing specific settings for the build. The package project directory may also contain a "scripts" directory containing any scripts (and, optionally, additional files used by the scripts) to be included in the package.

### Package project directory layout
```
project_dir/
    build-info.plist
    payload/
    scripts/
```

### Creating a new project

munkipkg can create an empty package project directory for you:

`munkipkg --create Foo`

...will create a new package project directory named "Foo" in the current working directory, complete with a starter build-info.plist, empty payload and scripts directories, and a .gitignore file to cause git to ignore the build/ directory that is created when a project is built.

Once you have a project directory, you simply copy the files you wish to package into the payload directory, and add a preinstall and/or postinstall script to the scripts directory. You may also wish to edit the build-info.plist.

### Importing an existing package

Another way to create a package project is to import an existing package:

`munkipkg --import /path/to/foo.pkg Foo`

...will create a new package project directory named "Foo" in the current working directory, with payload, scripts and build-info extracted from foo.pkg.
Complex or non-standard packages may not be extracted with 100% fidelity, and not all package formats are supported. Specifically, metapackages are not supported, and distribution packages containing multiple sub-packages are not supported. In these cases, consider importing the individual sub-packages.

### Building a package

This is the central task of munkipkg.

`munkipkg path/to/package_project_directory`

Causes munkipkg to build the package defined in package_project_directory. The built package is created in a build/ directory inside the project directory.

### build-info

Build options are stored in a file at the root of the package project. XML plist and JSON formats are supported. YAML is supported if you also install the Python PyYAML module. A build-info file is not strictly required, and a build will use default values if this file is missing.

XML plist is the default and preferred format. It can represent all the needed macOS data structures. JSON and YAML are also supported, but there is no guarantee that these formats will support future features of munkipkg. (Translation: use XML plist format unless it really, really bothers you; in that case use JSON or YAML but don't come crying to me if you can't use shiny new features with your JSON or YAML files. And please don't ask for help _formatting_ your JSON or YAML!)

#### build-info.plist

This must be in XML (text) format. Binary plists and "old-style-ASCII"-formatted plists are not supported. For a new project created with `munkipkg --create Foo`, the build-info.plist looks like this:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>distribution_style</key>
    <false/>
    <key>identifier</key>
    <string>com.github.munki.pkg.Foo</string>
    <key>install_location</key>
    <string>/</string>
    <key>name</key>
    <string>Foo-${version}.pkg</string>
    <key>ownership</key>
    <string>recommended</string>
    <key>postinstall_action</key>
    <string>none</string>
    <key>suppress_bundle_relocation</key>
    <true/>
    <key>version</key>
    <string>1.0</string>
</dict>
</plist>
```

#### build-info.json

Alternately, you may specify build-info in JSON format. A new project created with `munkipkg --create --json Foo` would have this build-info.json file:

```json
{
    "postinstall_action": "none",
    "suppress_bundle_relocation": true,
    "name": "Foo-${version}.pkg",
    "distribution_style": false,
    "preserve_xattr": false,
    "install_location": "/",
    "version": "1.0",
    "ownership": "recommended",
    "identifier": "com.github.munki.pkg.Foo"
}
```

If both build-info.plist and build-info.json are present, the plist file will be used; the json file will be ignored.

#### build-info.yaml

As a third alternative, you may specify build-info in YAML format, if you've installed the Python YAML module (PyYAML). A new project created with `munkipkg --create --yaml Foo` would have this build-info.yaml file:

```yaml
distribution_style: false
identifier: com.github.munki.pkg.Foo
install_location: /
name: Foo-${version}.pkg
ownership: recommended
postinstall_action: none
preserve_xattr: false
suppress_bundle_relocation: true
version: '1.0'
```

If both build-info.plist and build-info.yaml are present, the plist file will be used; the yaml file will be ignored.

##### JSON and YAML formatting note

Note in the JSON and YAML examples that the version "number" is wrapped in quotes. This is important -- XML plists have explicit type tags and the correct type for a version "number" is `string`. JSON and YAML infer a value's type based on formatting. Without quotes wrapping the value, `1.0` would be interpreted as a floating point number, and not a string, potentially causing an error at build time. This issue might affect future build-info keys supported by `munkipkg`, so take care.

#### build-info keys

**distribution_style**  
Boolean: true or false. Defaults to false. If present and true, package built will be a "distribution-style" package.

**identifier**  
String containing the package identifier. If this is missing, one is constructed using the name of the package project directory.

**install_location**  
String. Path to the intended install location of the payload on the target disk. Defaults to "/".

**name**  
String containing the package name. If this is missing, one is constructed using the name of the package project directory.

By default, the package name is suffixed with the version number using `${version}`. This suffix can be removed if desired, or it can be specified manually.

JSON Example:

```json
"name": "munki_kickstart-${version}.pkg"
"name": "munki_kickstart.pkg"
"name": "munki_kickstart-1.0.pkg"
```

**ownership**  
String. One of "recommended", "preserve", or "preserve-other". Defaults to "recommended". See the man page for `pkgbuild` for a description of the ownership options.

**postinstall_action**  
String. One of "none", "logout", or "restart". Defaults to "none".

**preserve_xattr**  
Boolean: true or false. Defaults to false. Setting this to true would preserve extended attributes, like codesigned flat files (e.g. script files), amongst other xattr's such as the apple quarantine warning (com.apple.quarantine).

**product id**  
Optional. String. Sets the value of the "product id" attribute in a distribution-style package's Distribution file. If this is not defined, the value for `identifier` (the package identifier) will be used instead.

**suppress\_bundle\_relocation**  
Boolean: true or false. Defaults to true. If present and false, bundle relocation will be allowed, which causes the Installer to update bundles found in locations other than their default location. For deploying software in a managed environment, this is rarely what you want.

**version**  
A string representation of the version number. Defaults to "1.0".

The value of this key is referenced in the default package name using `${version}`. (See the **name** key details above.)

**signing_info**  
Dictionary of signing options. See below.

**notarization_info**  
Dictionary of notarization options. See below.

#### build-info keys supported by macOS 12+

**compression**  
String. One of "latest" or "legacy". When creating pkg files on macOS 12 or higher, using "latest" in conjunction with a `min-os-version` of `10.10` (or higher) will result in increased compression of pkg content.

**min-os-version**  
String. Numeric representation of the target OS's MAJOR.MINOR versions. Eg "10.5", "10.10", "12.0", etc

### Build directory

`munkipkg` creates its packages inside the build directory. A build directory is created within the project directory if one doesn't exist at build time.

### Scripts directory

The scripts folder contains scripts to be included as part of the package.

munkipkg makes use of `pkgbuild`. Therefore the "main" scripts must be named either "preinstall" or "postinstall" (with no extensions) and must have their execute bit set. Other scripts can be called by the preinstall or postinstall scripts, but only those two scripts will be automatically called during package installation.

### Payload directory

The payload folder contains the files to be installed. These files must have the intended directory structure. Files at the top-level of the payload folder will be installed at the root of the target volume. If you wanted to install files 'foo' and 'bar' in /usr/local/bin of the target volume, your payload folder would look like this:

```
payload/
    usr/
        local/
            bin/
                foo
                bar
```

### Payload-free packages

You can use this tool to build payload-free packages in two variants.

If there is no payload folder at all, `pkgbuild` is called with the `--nopayload` option. The resulting package will not leave a receipt when installed.

If the payload folder exists, but is empty, you'll get a "pseudo-payload-free" package. No files will be installed, but a receipt will be left. This is often the more useful option if you need to track if the package has been installed on machines you manage.

### Package signing

You may sign packages as part of the build process by adding a signing\_info dictionary to the build\_info.plist:

```xml
    <key>signing_info</key>
    <dict>
        <key>identity</key>
        <string>Signing Identity Common Name</string>
        <key>keychain</key>
        <string>/path/to/SpecialKeychain</string>
        <key>additional_cert_names</key>
        <array>
            <string>Intermediate CA Common Name 1</string>
            <string>Intermediate CA Common Name 2</string>
        </array>
        <key>timestamp</key>
        <true/>
    </dict>
```

or, in JSON format in a build-info.json file:

```json
    "signing_info": {
        "identity": "Signing Identity Common Name",
        "keychain": "/path/to/SpecialKeychain",
        "additional_cert_names": ["Intermediate CA Common Name 1",
                                  "Intermediate CA Common Name 2"],
        "timestamp": true,
    }
```

The only required key/value in the signing_info dictionary is 'identity'.

See the **SIGNED PACKAGES** section of the man page for `pkgbuild` or the **SIGNED PRODUCT ARCHIVES** section of the man page for `productbuild` for more information on the signing options.


### Package notarization

**Important notes**:

- Please read the [Customizing the Notarization Workflow](https://developer.apple.com/documentation/security/notarizing_your_app_before_distribution/customizing_the_notarization_workflow) web page before you start notarizing your packages.
- Xcode 13 (or newer) is **required**.  If you have more than one version of Xcode installed on your Mac, be sure to use the xcode-select utility to choose the appropriate version: `sudo xcode-select -s /path/to/Xcode13.app`.
- Unproxied network access to the Apple infrastructure (Usually `17.0.0.0/8` network) is required.
- Notarization tool tries to notarize not only the package but also the package payload. All code in the payload (including but not limited to app bundles, frameworks, kernel extensions) needs to be properly signed with the hardened runtime restrictions in order to be notarized. Please read Apple Developer documentation for more information.

You may notarize **SIGNED PACKAGES** as part of the build process by adding a `notarization_info` dictionary to the build\_info.plist:

```xml
    <key>notarization_info</key>
    <dict>
        <key>apple_id</key>
        <string>john.appleseed@apple.com</string>
        <key>password</key>
        <string>@keychain:AC_PASSWORD</string>
        <key>team_id</key>
        <string>ABCDEF12345</string>
        <key>asc_provider</key>
        <string>JohnAppleseed1XXXXXX8</string>
        <key>staple_timeout</key>
        <integer>600</integer>
    </dict>
```

or, in JSON format in a build-info.json file:

```json
    "notarization_info": {
        "username": "john.appleseed@apple.com",
        "password": "@keychain:AC_PASSWORD",
        "asc_provider": "JohnAppleseed1XXXXXX8",
        "stapler_timeout": 600
    }
```

Keys/values of the `notarization_info` dictionary:

| Key               | Type    | Required | Description |
| ----------------- | ------- | -------- | ----------- |
| apple_id          | String  | (see authentication) | Login email address of your developer Apple ID |
| team_id           | String  | (see authentication) | The team identifier for the Developer Team, usually 10 alphanumeric characters |
| password          | String  | (see authentication) | 2FA app specific password. |
| keychain_profile  | String  | (see authentication) | App Store Connect API key issuer ID. |
| asc_provider      | String  | No       | Only needed when a user account is associated with multiple providers |
| primary_bundle_id | String  | No       | Defaults to `identifier`. Whether specified or not underscore characters are always automatically converted to hyphens since Apple notary service does not like underscores |
| staple_timeout    | Integer | No       | See paragraph bellow |

**Authentication**  

To notarize the package you have to use Apple ID with access to App Store Connect. There are two possible authentication methods: App-specific password and keychain profile. Either `apple_id`+`team_id`+`password` or `keychain_profile` keys(s) **must** be specified in the `notarization_info` dictionary. If you specify both `password` based takes precedence.

**Using the password**  

For information about the password and saving it to the login keychain see the web page [Customizing the Notarization Workflow](https://developer.apple.com/documentation/security/notarizing_your_app_before_distribution/customizing_the_notarization_workflow).

If you configure `munkipkg` to use the password from the login keychain user is going to be prompted to allow access to the password. You can authorize this once clicking *Allow* or permanently clicking *Always Allow*.

**How to Setup Your Keychain for Notarization with `notarytool`**

Dependency: `notarytool` is bundled with Xcode, so you need to have the latest version of Xcode installed and the command line tools.

Run: 
`/Applications/Xcode.app/Contents/Developer/usr/bin/notarytool store-credentials` 

It will ask you for a profile name, use: `notarization_credentials` as that is what all our pkginfo files will have as the `keychain_profile` key in the munkipkg project json file, as such:

Skip the next question about App Store API.

1. It will move to ask you for a Developer Apple ID email
2. The password here is a unique app-specific password created in appleid.apple.com from the same Developer ID account.
3. Enter your Team ID from the developer certificate.

All your munkipkg json project files will need that notarization info added as such:

```json
{
    "postinstall_action": "none",
    "suppress_bundle_relocation": true,
    "name": "PackageName.pkg",
    "distribution_style": true,
    "install_location": "/path/to/payload/location/",
    "version": "14.0",
    "ownership": "recommended",
    "identifier": "com.domain.PackageName",
    "signing_info": {
        "identity": "Developer ID Installer: Company Name (Team ID)",
        "keychain": "/path/to/certificate/signing.keychain",
        "timestamp": true
    },
    "notarization_info": {
        "keychain_profile": "notarization_credentials"
    }
}
```

`munkipkg` will now call the `keychain_profile` from the json to run as the credentials for the notarization.

**Creating the API key**  

1. Log into [App Store Connect](https://appstoreconnect.apple.com) using developer Apple ID with access to API keys.
2. Go to Users and Access -> Keys.
3. Click + button to create a new key.
4. Name the key and select proper access - Developer.
5. Download the API key and save it to one of the following directories `./private_keys`, `~/private_keys`, `~/.private_keys`. Filename format is `AuthKey_<api_key>.p8`. Use `<api_key>` part when configuring `api_key` option.
6. Note the *Issuer ID* at the top of the web page. It must be provided using `api_issuer` option.

**About stapling**  

`munkipkg` basically does following:

1. Uploads the package to Apple notary service using `xcrun notarytool submit --output-format plist build/munki_kickstart.pkg --apple-id "john.appleseed@apple.com" --team-id ABCDEF12345 --password "@keychain:AC_PASSWORD"`
2. Checks periodically state of notarization process using `xcrun notarytool info <UUID> --output-format plist --apple-id "john.appleseed@apple.com" --team-id ABCDEF12345 --password "@keychain:AC_PASSWORD"`
3. If notarization was successful `munkipkg` staples the package using `xcrun stapler staple munki_kickstart.pkg`

There is a time delay between successful upload of a signed package to the notary service and notarization result from the service.
`munkipkg` checks multiple times if notarization process is done. There is sleep period between each try. Sleep period starts at 5 seconds and increases by increments of 5 (5s, 10s, 10s, etc.).
With `staple_timeout` parameter you can specify timeout in seconds (**default: 300 seconds**) after which `munkipkg` gives up.

### Additional options

`--create`  
Creates a new empty template package project. See [**Creating a new project**](#creating-a-new-project).

`--import`  
`munkipkg --import /path/to/flat.pkg /path/to/project_dir`

This option will import an existing package and convert it into a package project. project_dir must not exist; it will be created. build-info will be in plist format, add the --json option to output in JSON format instead. (IE: `munkipkg --json --import /path/to/flat.pkg /path/to/project_dir`) Not all package formats are supported.

`--export-bom-info`  
This option causes munkipkg to export bom info from the built package to a file named "Bom.txt" in the root of the package project directory. Since git does not normally track ownership, group, or mode of tracked files, and since the "ownership" option to `pkgbuild` can also result in different owner and group of files included in the package payload, exporting this info into a text file allows you to track this metadata in git (or other version control) as well.

`--skip-notarization`  
Use this option to skip the whole notarization process when notarization is specified in the build-info.

`--skip-stapling`  
Use this option to skip only the stapling part of the notarization process when notarization is specified in the build-info.

`--sync`  
This option causes munkipkg to read the Bom.txt file, and use its information to create any missing empty directories and to set the permissions on files and directories. See [**Important git notes**](#important-git-notes) below.

`--quiet`  
Causes munkipkg to suppress normal output messages. Errors will still be printed to stderr.

`--help`, `--version`  
Prints help message and tool version, respectively.

## Important git notes

Git was designed to track source code. Its focus is tracking changes in the contents of files. It's not a perfect fit for tracking the parts making up a package. Specifically, git doesn't track owner or group of files or directories, and does not track any mode bits except for the execute bit for the owner. Git also does not track empty directories.

This could be a problem if you want to store package project directories in git and `git clone` them; the clone operation will fail to replicate empty directories in the package project and will fail to set the correct mode for files and directories. (Owner and group are less of an issue if you use ownership=recommended for your `pkgbuild` options.)

The solution to this problem is the Bom.txt file, which lists all the files and directories in the package, along with their mode, owner and group.

This file (Bom.txt) can be tracked by git.

You can create this file when building package by adding the `--export-bom-info` option. After the package is built, the Bom is extracted and `lsbom` is used to read its contents, which are written to "Bom.txt" at the root of the package project directory.

A recommended workflow would be to build a project with `--export-bom-info` and add the Bom.txt file to the next git commit in order to preserve the data that git does not normally track.

After doing a `git clone` or `git pull` operation, you can then use `munkipkg --sync project_name` to cause munkipkg to read the Bom.txt file and use the info within to create any missing directories and to set file and directory modes to those recorded in the bom.

This workflow is not ideal, as it requires you to remember two new manual steps (`munkipkg --export` before doing a git commit and `munkipkg --sync` after doing a `git clone` or `git pull`) but is necessary to preserve data that git otherwise ignores.
