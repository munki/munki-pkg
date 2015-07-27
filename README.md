#munkipkg

##Introduction

munkipkg is a simple tool for building packages in a consistent, repeatable manner from source files and scripts in a project directory.

Files, scripts, and metadata are stored in a way that is easy to track and manage using a version control system like git.

Another tool that solves a similar problem is Joe Block's The Luggage (https://github.com/unixorn/luggage). If you are happily using The Luggage, you can probably safely ignore this tool.


##Basic operation

munkipkg builds flat packages using Apple's pkgbuild and productbuild tools.

###Package project directories

munkipkg builds packages from a "package project directory". At its simplest, a package project directory is a directory containing a "payload" directory, which itself contains the files to be packaged. More typically, the directory also contains a "build-info.plist" file containing specific settings for the build. The package project directory may also contain a "scripts" directory containing any scripts (and, optionally, additional files used by the scripts) to be included in the package.


###Package project directory layout
```
project_dir/
    build-info.plist
    payload/
    scripts/
```

###Creating a new project

munkipkg can create an empty package project directory for you:

`munkipkg --create Foo`

...will create a package project directory named "Foo" in the current working directory, complete with a starter build-info.plist, empty payload and scripts directories, and a .gitignore file to cause git to ignore the build/ directory that is created when a project is built.

Once you have a project directory, you simply copy the files you wish to package into the payload directory, and add a preinstall and/or postinstall script to the scripts directory. You may also wish to edit the build-info.plist.


###Building a package

`munkipkg path/to/package_project_directory`

Causes munkipkg to build the package defined in package_project_directory. The built package is created in a build/ directory inside the project directory.


###build-info.plist

This is an XML-formatted plist (binary plists are not currently supported) that provides additional options for building the package. For a new project created with `munkipkg --create Foo`, the build-info.plist looks like this:

```
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
    <string>Foo.pkg</string>
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

###build-info.plist keys

**distribution_style**  
Boolean: true or false. Defaults to false. If present and true, package built will be a "distribution-style" package.

**identifier**  
String containing the package identifier. If this is missing, one is constructed using the name of the package project directory.

**install_location**  
String. Path to the intended install location of the payload on the target disk. Defaults to "/".

**name**  
String containing the package name. If this is missing, one is constructed using the name of the package project directory.

**ownership**  
String. One of "recommended", "preserve", or "preserve-other". Defaults to "recommended". See the man page for pkgbuild for a description of the ownership options.

**postinstall_action**  
String. One of "none", "logout", or "restart". Defaults to "none".

**suppress\_bundle\_relocation**  
Boolean: true or false. Defaults to true. If present and false, bundle relocation will be allowed, which causes the Installer to update bundles found in locations other than their default location. For deploying software in a managed environment, this is rarely what you want.

**version**  
A string representation of the version number. Defaults to "1.0".

**signing_info**  
Dictionary of signing options. See below.


### Package signing

You may sign packages as part of the build process by adding a signing\_info dictionary to the build\_info.plist.  
> (Note: as of 27 July 2015, package signing support is untested by the author. Please test and report your experiences!)

```
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

The only required key/value in the signing_info dictionary is 'identity'.

See the **SIGNED PACKAGES** section of the man page for `pkgbuild` or the **SIGNED PRODUCT ARCHIVES** section of the man page for `productbuild` for more information on the signing options.


###Scripts

munkipkg makes use of pkgbuild. Therefore the "main" scripts must be named either "preinstall" or "postinstall" (with no extensions) and must have their execute bit set. Other scripts can be called by the preinstall or postinstall scripts, but only those two scripts will be automatically called during package installation.


###Additional options

    --export-bom-info
    This option causes munkipkg to export bom info from the built package to a file named "Bom.txt" in the root of the package project directory. Since git does not normally track ownership, group, or mode of tracked files, and since the "ownership" option to pkgbuild can also result in different owner and group of files included in the package payload, exporting this info into a text file allows you to track this metadata in git (or other version control) as well.

    --quiet
    Causes munkipkg to suppress normal output messages. Errors will still be printed to stderr.

    --help, --version
    Prints help message and tool version, respectively


##git notes

git does not track empty directories. If you have an empty directory somewhere in your payload/ directory, putting that project in git and then replicating it somewhere else via `git clone` may lead to unexpected results, as your cloned repo will not have the empty directory.

You might be able to work around this issue by adding a file to the "empty" directory that git _will_ track, but that pkgbuild will ignore. pkgbuild by default ignores files that match any of these paths:

```
/.svn$
/CVS$
/.git$
/.hg$
/.DS_Store$
```

Since .DS_Store is in the default .gitignore file, and .git is looked for by git itself, placing an empty .svn or .hg file might be the best workaround for this issue. Git will track the file (and therefore record the directory), and pkgbuild will not include it in the built package.

> UPDATE 27 July 2015: this workaround, does not in fact, work. When pkgbuild prunes the files in the above exclude list, if the pruned file was the only file in the enclosing directory the directory is also pruned from the list (and any parent directories that are now themselves empty). More investigation must be done. For now: beware packages that create empty directories.