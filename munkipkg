#!/usr/bin/env python
# encoding: utf-8
"""
munkipkg

A tool for making packages from projects that can be easily managed in a
version control system like git.

"""
# Copyright 2015-2022 Greg Neagle.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

from __future__ import absolute_import, print_function

import glob
import json
import optparse
import os
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from xml.dom import minidom
from xml.parsers.expat import ExpatError

try:
    import yaml
    YAML_INSTALLED = True
except ImportError:
    YAML_INSTALLED = False

from xml.dom import minidom
from xml.parsers.expat import ExpatError

VERSION = "1.0"
DITTO = "/usr/bin/ditto"
LSBOM = "/usr/bin/lsbom"
PKGBUILD = "/usr/bin/pkgbuild"
PKGUTIL = "/usr/sbin/pkgutil"
PRODUCTBUILD = "/usr/bin/productbuild"
XCRUN = "/usr/bin/xcrun"

GITIGNORE_DEFAULT = """# .DS_Store files!
.DS_Store

# our build directory
build/
"""

BUILD_INFO_FILE = "build-info"
REQUIREMENTS_PLIST = "product-requirements.plist"
BOM_TEXT_FILE = "Bom.txt"

STAPLE_TIMEOUT = 300
STAPLE_SLEEP = 5


class MunkiPkgError(Exception):
    '''Base Exception for errors in this domain'''
    pass


class BuildError(MunkiPkgError):
    '''Exception for build errors'''
    pass


class PkgImportError(MunkiPkgError):
    '''Exception for pkg import errors'''
    pass


def readPlistFromString(data):
    '''Wrapper for the differences between Python 2 and Python 3's plistlib'''
    try:
        return plistlib.loads(data)
    except AttributeError:
        # plistlib module doesn't have a load function (as in Python 2)
        return plistlib.readPlistFromString(data)


def readPlist(filepath):
    '''Wrapper for the differences between Python 2 and Python 3's plistlib'''
    try:
        with open(filepath, "rb") as fileobj:
            return plistlib.load(fileobj)
    except AttributeError:
        # plistlib module doesn't have a load function (as in Python 2)
        return plistlib.readPlist(filepath)


def writePlist(plist, filepath):
    '''Wrapper for the differences between Python 2 and Python 3's plistlib'''
    try:
        with open(filepath, "wb") as fileobj:
            plistlib.dump(plist, fileobj)
    except AttributeError:
        # plistlib module doesn't have a dump function (as in Python 2)
        plistlib.writePlist(plist, filepath)


def unlink_if_possible(pathname):
    '''Attempt to remove pathname but don't raise an execption if it fails'''
    try:
        os.unlink(pathname)
    except OSError as err:
        print("WARNING: could not remove %s: %s" % (pathname, err),
              file=sys.stderr)


def display(message, quiet=False, toolname=None):
    '''Print message to stdout unless quiet is True'''
    if not quiet:
        if not toolname:
            toolname = os.path.basename(sys.argv[0])
        print(("%s: %s" % (toolname, message)))


def run_subprocess(cmd):
    '''Runs cmd with Popen'''
    proc = subprocess.Popen(
        cmd,
        shell=False,
        universal_newlines=True,
        bufsize=1,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    proc_stdout, proc_stderr = proc.communicate()
    retcode = proc.returncode
    return (retcode, proc_stdout, proc_stderr)


def validate_build_info_keys(build_info, file_path):
    '''Validates the data read from build_info.(plist|json|yaml|yml)'''
    valid_values = {
        'ownership': ['recommended', 'preserve', 'preserve-other'],
        'postinstall_action': ['none', 'logout', 'restart'],
        'suppress_bundle_relocation': [True, False],
        'distribution_style': [True, False],
        'preserve_xattr': [True, False],
    }
    for key in valid_values:
        if key in build_info:
            if build_info[key] not in valid_values[key]:
                print("ERROR: %s key '%s' has illegal value: %s"
                      % (file_path, key, repr(build_info[key])),
                      file=sys.stderr)
                print('ERROR: Legal values are: %s' % valid_values[key],
                      file=sys.stderr)
                return False
    return True


def read_build_info(path):
    '''Reads and validates data in the build_info'''
    build_info = None
    exception_list = (ExpatError, ValueError)
    if YAML_INSTALLED:
        exception_list = (ExpatError, ValueError, yaml.scanner.ScannerError)
    try:
        if path.endswith('.json'):
            with open(path, 'r') as openfile:
                build_info = json.load(openfile)
        elif path.endswith(('.yaml', '.yml')):
            with open(path, 'r') as openfile:
                build_info = yaml.load(openfile, Loader=yaml.FullLoader)
        elif path.endswith('.plist'):
            build_info = readPlist(path)
    except exception_list as err:
        raise BuildError("%s is not a valid %s file: %s"
                         % (path, path.split('.')[-1], str(err)))
    validate_build_info_keys(build_info, path)
    if '${version}' in build_info['name']:
        build_info['name'] = build_info['name'].replace(
            '${version}',
            str(build_info['version'])
        )

    return build_info


def make_component_property_list(build_info, options):
    """Use pkgbuild --analyze to build a component property list; then
    turn off package relocation, Return path to the resulting plist."""
    component_plist = os.path.join(build_info['tmpdir'], 'component.plist')
    cmd = [PKGBUILD]
    if options.quiet:
        cmd.append('--quiet')
    cmd.extend(["--analyze", "--root", build_info['payload'], component_plist])
    try:
        returncode = subprocess.call(cmd)
    except OSError as err:
        raise BuildError(
            "pkgbuild execution failed with error code %d: %s"
            % (err.errno, err.strerror))
    if returncode:
        raise BuildError("pkgbuild failed with exit code %d" % returncode)
    try:
        plist = readPlist(component_plist)
    except ExpatError as err:
        raise BuildError("Couldn't read %s" % component_plist)
    # plist is an array of dicts, iterate through
    for bundle in plist:
        if bundle.get("BundleIsRelocatable"):
            bundle["BundleIsRelocatable"] = False
            display('Turning off bundle relocation for %s'
                    % bundle['RootRelativeBundlePath'], options.quiet)
    try:
        writePlist(plist, component_plist)
    except BaseException as err:
        raise BuildError("Couldn't write %s" % component_plist)
    return component_plist


def make_pkginfo(build_info, options):
    '''Creates a stub PackageInfo file for use with pkgbuild'''
    if build_info['postinstall_action'] != 'none' and not options.quiet:
        display("Setting postinstall-action to %s"
                % build_info['postinstall_action'], options.quiet)
    pkginfo_path = os.path.join(build_info['tmpdir'], 'PackageInfo')
    pkginfo_text = (
        '<?xml version="1.0" encoding="utf-8" standalone="no"?>'
        '<pkg-info postinstall-action="%s" preserve-xattr="%s"/>'
        % (build_info['postinstall_action'],
           str(build_info['preserve_xattr']).lower())
    )
    try:
        fileobj = open(pkginfo_path, mode='w')
        fileobj.write(pkginfo_text)
        fileobj.close()
        return pkginfo_path
    except (OSError, IOError) as err:
        raise BuildError('Couldn\'t create PackageInfo file: %s' % err)


def default_build_info(project_dir):
    '''Return dict with default build info values'''
    info = {}
    info['ownership'] = "recommended"
    info['suppress_bundle_relocation'] = True
    info['postinstall_action'] = 'none'
    info['preserve_xattr'] = False
    basename = os.path.basename(project_dir.rstrip('/')).replace(" ", "")
    info['name'] = basename + '-${version}.pkg'
    info['identifier'] = "com.github.munki.pkg." + basename
    info['install_location'] = '/'
    info['version'] = "1.0"
    info['distribution_style'] = False
    return info


def get_build_info(project_dir, options):
    '''Return dict with build info'''
    info = default_build_info(project_dir)
    info['project_dir'] = project_dir
    # override default values with values from BUILD_INFO_PLIST
    supported_keys = [
        'name',
        'identifier',
        'version',
        'ownership',
        'install_location',
        'postinstall_action',
        'preserve_xattr',
        'suppress_bundle_relocation',
        'distribution_style',
        'signing_info',
        'notarization_info',
    ]
    build_file = os.path.join(project_dir, BUILD_INFO_FILE)
    file_type = None
    if not options.yaml and not options.json:
        file_types = ['plist', 'json', 'yaml', 'yml']
        for ext in file_types:
            if os.path.exists(build_file + '.' + ext):
                if file_type is None:
                    file_type = ext
                else:
                    raise MunkiPkgError(
                        "ERROR: Multiple build-info files found!")
    else:
        file_type = (
            'yaml' if options.yaml else 'json' if options.json else 'plist')

    file_info = None
    if file_type and os.path.exists(build_file + '.' + file_type):
        file_info = read_build_info(build_file + '.' + file_type)

    if file_info:
        for key in supported_keys:
            if key in file_info:
                info[key] = file_info[key]
    else:
        raise MunkiPkgError('ERROR: No build-info file found!')

    return info


def non_recommended_permissions_in_bom(project_dir):
    '''Analyzes Bom.txt to determine if there are any items with owner/group
    other than 0/0, which implies we should handle ownership differently'''

    bom_list_file = os.path.join(project_dir, BOM_TEXT_FILE)
    if not os.path.exists(bom_list_file):
        return False
    try:
        with open(bom_list_file) as fileref:
            while True:
                item = fileref.readline()
                if not item:
                    break
                if item == '\n':
                    # shouldn't be any empty lines in Bom.txt, but...
                    continue
                parts = item.rstrip('\n').split('\t')
                user_group = parts[2]
                if user_group != '0/0':
                    return True
        return False
    except (OSError, ValueError) as err:
        print('ERROR: %s' % err, file=sys.stderr)
        return False


def sync_from_bom_info(project_dir, options):
    '''Uses Bom.txt to apply modes to files in payload dir and create any
    missing empty directories, since git does not track these.'''

    # possible to-do: preflight check: if there are files missing
    # (and not just directories), or there are extra files or directories,
    # bail without making any changes

    # possible to-do: a refinement of the above preflight check
    # -- also check file checksums

    bom_list_file = os.path.join(project_dir, BOM_TEXT_FILE)
    payload_dir = os.path.join(project_dir, 'payload')
    try:
        build_info = get_build_info(project_dir, options)
    except MunkiPkgError:
        build_info = default_build_info(project_dir)
    running_as_root = (os.geteuid() == 0)
    if not os.path.exists(bom_list_file):
        print((
            "ERROR: Can't sync with bom info: no %s found in project directory."
            % BOM_TEXT_FILE), file=sys.stderr)
        return -1
    if build_info['ownership'] != 'recommended' and not running_as_root:
        print((
            "\nWARNING: build-info ownership: %s might require using "
            "sudo to properly sync owner and group for payload files.\n"
            % build_info['ownership']), file=sys.stderr)

    returncode = 0
    changes_made = 0

    try:
        with open(bom_list_file) as fileref:
            while True:
                item = fileref.readline()
                if not item:
                    break
                if item == '\n':
                    # shouldn't be any empty lines in Bom.txt, but...
                    continue
                parts = item.rstrip('\n').split('\t')
                path = parts[0]
                if path.startswith('./'):
                    path = path[2:]
                full_mode = parts[1]
                user_group = parts[2].partition('/')
                desired_user = int(user_group[0])
                desired_group = int(user_group[2])
                desired_mode = int(full_mode[-4:], 8)
                payload_path = os.path.join(payload_dir, path)
                basename = os.path.basename(path)
                if basename.startswith('._'):
                    otherfile = os.path.join(
                        os.path.dirname(path), basename[2:])
                    print((
                        'WARNING: file %s contains extended attributes or a '
                        'resource fork for %s. git and pkgbuild may not '
                        'properly preserve extended attributes.'
                        % (path, otherfile)), file=sys.stderr)
                    continue
                if os.path.lexists(payload_path):
                    # file exists, check permission bits and adjust if needed
                    current_mode = stat.S_IMODE(os.lstat(payload_path).st_mode)
                    if current_mode != desired_mode:
                        display("Changing mode of %s to %s"
                                % (payload_path, oct(desired_mode)),
                                options.quiet)
                        os.lchmod(payload_path, desired_mode)
                        changes_made += 1
                elif full_mode.startswith('4'):
                    # file doesn't exist and it's a directory; re-create it
                    display("Creating %s with mode %s"
                            % (payload_path, oct(desired_mode)),
                            options.quiet)
                    os.mkdir(payload_path, desired_mode)
                    changes_made += 1
                    continue
                else:
                    # missing file. This is a problem.
                    print("ERROR: File %s is missing in payload"
                          % payload_path, file=sys.stderr)
                    returncode = -1
                    break
                if running_as_root:
                    # we can sync owner and group as well
                    current_user = os.lstat(payload_path).st_uid
                    current_group = os.lstat(payload_path).st_gid
                    if (current_user != desired_user or
                            current_group != desired_group):
                        display("Changing user/group of %s to %s/%s"
                                % (payload_path, desired_user, desired_group),
                                options.quiet)
                        os.lchown(payload_path, desired_user, desired_group)
                        changes_made += 1

    except (OSError, ValueError) as err:
        print('ERROR: %s' % err, file=sys.stderr)
        return -1

    if returncode == 0 and not options.quiet:
        if changes_made:
            display("Sync successful.")
        else:
            display("Sync successful: no changes needed.")
    return returncode


def add_project_subdirs(build_info):
    '''Adds and validates project subdirs to build_info'''
    # validate payload and scripts dirs
    project_dir = build_info['project_dir']
    payload_dir = os.path.join(project_dir, 'payload')
    scripts_dir = os.path.join(project_dir, 'scripts')
    if not os.path.isdir(payload_dir):
        payload_dir = None
    if not os.path.isdir(scripts_dir):
        scripts_dir = None
    elif os.listdir(scripts_dir) in [[], ['.DS_Store']]:
        # scripts dir is empty; don't include it as part of build
        scripts_dir = None
    if not payload_dir and not scripts_dir:
        raise BuildError(
            "%s does not contain a payload folder or a scripts folder."
            % project_dir)

    # make sure build directory exists
    build_dir = os.path.join(project_dir, 'build')
    if not os.path.exists(build_dir):
        os.mkdir(build_dir)
    elif not os.path.isdir(build_dir):
        raise BuildError("%s is not a directory." % build_dir)

    build_info['payload'] = payload_dir
    build_info['scripts'] = scripts_dir
    build_info['build_dir'] = build_dir
    build_info['tmpdir'] = tempfile.mkdtemp()


def write_build_info(build_info, project_dir, options):
    '''writes out our build-info file in preferred format'''
    try:
        if options.json:
            build_info_json = os.path.join(
                project_dir, "%s.json" % BUILD_INFO_FILE)
            with open(build_info_json, 'w') as json_file:
                json.dump(
                    build_info, json_file, ensure_ascii=True,
                    indent=4, separators=(',', ': '))
        elif options.yaml:
            build_info_yaml = os.path.join(
                project_dir, "%s.yaml" % BUILD_INFO_FILE)
            with open(build_info_yaml, 'w') as yaml_file:
                yaml_file.write(
                    yaml.dump(build_info, default_flow_style=False)
                )
        else:
            build_info_plist = os.path.join(
                project_dir, "%s.plist" % BUILD_INFO_FILE)
            writePlist(build_info, build_info_plist)
    except OSError as err:
        raise MunkiPkgError(err)


def create_default_gitignore(project_dir):
    '''Create default .gitignore file for new projects'''
    gitignore_file = os.path.join(project_dir, '.gitignore')
    fileobj = open(gitignore_file, "w")
    fileobj.write(GITIGNORE_DEFAULT)
    fileobj.close()


def create_template_project(project_dir, options):
    '''Create an empty pkg project directory with default settings'''
    if os.path.exists(project_dir):
        if not options.force:
            print((
                "ERROR: %s already exists! "
                "Use --force to convert it to a project directory."
                % project_dir), file=sys.stderr)
            return -1
    payload_dir = os.path.join(project_dir, 'payload')
    scripts_dir = os.path.join(project_dir, 'scripts')
    build_dir = os.path.join(project_dir, 'build')
    try:
        if not os.path.exists(project_dir):
            os.mkdir(project_dir)
        os.mkdir(payload_dir)
        os.mkdir(scripts_dir)
        os.mkdir(build_dir)
        build_info = default_build_info(project_dir)
        write_build_info(build_info, project_dir, options)
        create_default_gitignore(project_dir)
        display(
            "Created new package project at %s" % project_dir, options.quiet)
    except (OSError, MunkiPkgError) as err:
        print('ERROR: %s' % err, file=sys.stderr)
        return -1
    return 0


def export_bom(bomfile, project_dir):
    '''Exports bom to text format. Returns returncode from lsbom'''
    destination = os.path.join(project_dir, BOM_TEXT_FILE)
    try:
        with open(destination, mode='w') as fileobj:
            cmd = [LSBOM, bomfile]
            proc = subprocess.Popen(cmd, stdout=fileobj, stderr=subprocess.PIPE)
            _, stderr = proc.communicate()
            if proc.returncode:
                raise MunkiPkgError(stderr)
    except OSError as err:
        raise MunkiPkgError(err)


def export_bom_info(build_info, options):
    '''Extract the bom file from the built package and export its info to the
    project directory'''
    pkg_path = os.path.join(build_info['build_dir'], build_info['name'])
    cmd = [PKGUTIL, '--bom', pkg_path]
    display("Extracting bom file from %s" % pkg_path, options.quiet)
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (stdout, stderr) = proc.communicate()
    if proc.returncode:
        raise BuildError(stderr.strip())

    bomfile = stdout.strip()
    destination = os.path.join(build_info['project_dir'], BOM_TEXT_FILE)
    display("Exporting bom info to %s" % destination, options.quiet)
    export_bom(bomfile, build_info['project_dir'])
    unlink_if_possible(bomfile)


def add_signing_options_to_cmd(cmd, build_info, options):
    '''If build_info contains signing options, add them to the cmd'''
    if 'signing_info' in build_info:
        display("Adding package signing info to command", options.quiet)
        signing_info = build_info['signing_info']
        if 'identity' in signing_info:
            cmd.extend(['--sign', signing_info['identity']])
        else:
            raise BuildError('Missing identity in signing info!')
        if 'keychain' in signing_info:
            cmd.extend(['--keychain', signing_info['keychain']])
        if 'additional_cert_names' in signing_info:
            additional_cert_names = signing_info['additional_cert_names']
            # convert single string to list
            try:
                text_types = basestring # pylint: disable=basestring-builtin
            except NameError:
                text_types = str
            if isinstance(additional_cert_names, text_types):
                additional_cert_names = [additional_cert_names]
            for cert_name in additional_cert_names:
                cmd.extend(['--cert', cert_name])
        if 'timestamp' in signing_info:
            if signing_info['timestamp']:
                cmd.extend(['--timestamp'])
            else:
                cmd.extend(['--timestamp=none'])


def build_pkg(build_info, options):
    '''Use pkgbuild tool to build our package'''
    cmd = [PKGBUILD,
           '--ownership', build_info['ownership'],
           '--identifier', build_info['identifier'],
           '--version', str(build_info['version']),
           '--info', build_info['pkginfo_path']]
    if build_info['payload']:
        cmd.extend(['--root', build_info['payload']])
        if build_info.get('install_location'):
            cmd.extend(['--install-location', build_info['install_location']])
    else:
        cmd.extend(['--nopayload'])
    if build_info['component_plist']:
        cmd.extend(['--component-plist', build_info['component_plist']])
    if build_info['scripts']:
        cmd.extend(['--scripts', build_info['scripts']])
    if options.quiet:
        cmd.append('--quiet')
    if not build_info.get('distribution_style'):
        add_signing_options_to_cmd(cmd, build_info, options)
    cmd.append(os.path.join(build_info['build_dir'], build_info['name']))
    retcode = subprocess.call(cmd)
    if retcode:
        raise BuildError("Package creation failed.")


def build_distribution_pkg(build_info, options):
    '''Converts component pkg to dist pkg'''
    pkginputname = os.path.join(build_info['build_dir'], build_info['name'])
    distoutputname = os.path.join(
        build_info['build_dir'], 'Dist-' + build_info['name'])
    if os.path.exists(distoutputname):
        retcode = subprocess.call(["/bin/rm", "-rf", distoutputname])
        if retcode:
            raise BuildError(
                'Error removing existing %s: %s' % (distoutputname, retcode))

    cmd = [PRODUCTBUILD]
    if options.quiet:
        cmd.append('--quiet')
    add_signing_options_to_cmd(cmd, build_info, options)
    # if there is a PRE-INSTALL REQUIREMENTS PROPERTY LIST, use it
    requirements_plist = os.path.join(
        build_info['project_dir'], REQUIREMENTS_PLIST)
    if os.path.exists(requirements_plist):
        cmd.extend(['--product', requirements_plist])
    # if build_info contains a product id use that for product id, otherwise
    # use package identifier
    product_id = build_info.get('product id', build_info['identifier'])
    cmd.extend(['--identifier', product_id, '--version', str(build_info['version'])])
    # add the input and output package paths
    cmd.extend(['--package', pkginputname, distoutputname])

    retcode = subprocess.call(cmd)
    if retcode:
        raise BuildError("Distribution package creation failed.")
    try:
        display("Removing component package %s" % pkginputname, options.quiet)
        os.unlink(pkginputname)
        display("Renaming distribution package %s to %s"
                % (distoutputname, pkginputname), options.quiet)
        os.rename(distoutputname, pkginputname)
    except OSError as err:
        raise BuildError(err)


def get_primary_bundle_id(build_info):
    '''Gets primary bundle id for notarization'''
    primary_bundle_id = build_info['notarization_info'].get(
            'primary_bundle_id',
            build_info['identifier'],
    )

    # Apple notary service does not like underscores
    primary_bundle_id = primary_bundle_id.replace('_', '-')

    return primary_bundle_id


def add_authentication_options(cmd, build_info):
    '''Add --password or --apiKey + --apiIssuer options to the command'''
    if 'password' in build_info['notarization_info']:
        cmd.extend(
            ['--password', build_info['notarization_info']['password']]
        )
    elif (
          'api_key' in build_info['notarization_info'] and
          'api_issuer' in build_info['notarization_info']
    ):
        cmd.extend(
            [
                '--apiKey',
                build_info['notarization_info']['api_key'],
                '--apiIssuer',
                build_info['notarization_info']['api_issuer'],
            ]
        )
    else:
        raise MunkiPkgError(
            "password or api_key + api_issuer keys "
            "must be specified in notarization_info."
        )


def upload_to_notary(build_info, options):
    '''Use xcrun altool to upload the package to Apple notary service'''
    if 'username' not in build_info['notarization_info']:
        raise MunkiPkgError("notarization_info lacks username key.")

    display("Uploading package to Apple notary service", options.quiet)
    cmd = [
        XCRUN,
        'altool',
        '--notarize-app',
        '--primary-bundle-id',
        get_primary_bundle_id(build_info),
        '--username',
        build_info['notarization_info']['username'],
        '--output-format',
        'xml',
        '--file',
        os.path.join(build_info['build_dir'], build_info['name']),
    ]
    if 'asc_provider' in build_info['notarization_info']:
        cmd.extend(
            ['--asc-provider', build_info['notarization_info']['asc_provider']]
        )
    add_authentication_options(cmd, build_info)

    retcode, proc_stdout, proc_stderr = run_subprocess(cmd)
    if proc_stdout.startswith('Generated JWT'):
        proc_stdout = proc_stdout.split('\n',1)[1]
    try:
        output = readPlistFromString(proc_stdout.encode("UTF-8"))
    except ExpatError:
        print(proc_stderr, file=sys.stderr)
        raise MunkiPkgError("Notarization upload failed. Unable to run xcrun altool")

    if retcode:
        for product_error in output.get('product-errors', []):
            print(
                "altool: FAILURE " + product_error.get('message', 'UNKNOWN ERROR'),
                file=sys.stderr
            )
        raise MunkiPkgError("Notarization failed")

    try:
        request_uuid = output['notarization-upload']['RequestUUID']
        display("RequestUUID " + request_uuid, options.quiet, "altool")
        display("SUCCESS " + output['success-message'], options.quiet, "altool")
    except KeyError:
        raise MunkiPkgError("Unexpected output from altool")

    return request_uuid


def get_notarization_state(request_uuid, build_info, options):
    '''Checks for result of notarization process'''
    state = {}
    cmd = [
        XCRUN,
        'altool',
        '--notarization-info',
        request_uuid,
        '--username',
        build_info['notarization_info']['username'],
        '--output-format',
        'xml',
    ]
    add_authentication_options(cmd, build_info)

    retcode, proc_stdout, proc_stderr = run_subprocess(cmd)
    if proc_stdout.startswith('Generated JWT'):
        proc_stdout = proc_stdout.split('\n',1)[1]

    try:
        output = readPlistFromString(proc_stdout.encode("UTF-8"))
    except ExpatError:
        print(proc_stderr, file=sys.stderr)
        raise MunkiPkgError("Notarization check failed. Unable to run xcrun altool")
    if retcode or 'notarization-info' not in output:
        print("altool: " + output.get('success-message', 'Unexpected response'))
        print("altool: DEBUG output follows")
        print(output)
        state['status'] = 'Unknown'
    else:
        state['log_url'] = output['notarization-info'].get('LogFileURL', '')
        state['status'] = output['notarization-info'].get('Status', 'Unknown')
        state['code'] = output['notarization-info'].get('Status Code', None)
        state['message'] = output['notarization-info'].get('Status Message', '')
    return state


def notarization_done(state, sleep_time, options):
    '''Evaluates whether notarization is still in progress'''
    if state['status'] == 'success':
        display("Notarization successful. {}".format(state['message']), options.quiet)
        return True
    elif state['status'] in ['in progress', 'Unknown']:
        display(
            "Notarization state: {}. Trying again in {} seconds".format(
                state['status'],
                sleep_time,
            ),
            options.quiet,
        )
        return False
    else:
        display(
            "Notarization unsuccessful:\n"
            "\tStatus: {}\n"
            "\tStatus Code: {}\n"
            "\tStatus Message: {}\n"
            "\tLogFileURL: {}".format(
                state['status'], state['code'], state['message'], state['log_url']
            ),
            options.quiet,
        )
        raise MunkiPkgError("Notarization failed")


def wait_for_notarization(request_uuid, build_info, options):
    '''Checks notarization state until it is done or we exceed the timeout value'''
    display("Getting notarization state", options.quiet)
    timeout = build_info['notarization_info'].get('staple_timeout', STAPLE_TIMEOUT)
    counter = 0
    sleep_time = STAPLE_SLEEP

    while counter < timeout:
        time.sleep(sleep_time)
        counter += sleep_time
        sleep_time += STAPLE_SLEEP

        state = get_notarization_state(request_uuid, build_info, options)

        if notarization_done(state, sleep_time, options):
            return True

    print(
        "munkipkg: Timeout EXCEEDED when waiting for the notarization to complete. "
        "You can manually staple the package later if notarization is successful.",
        file=sys.stderr,
    )
    return False


def staple(build_info, options):
    '''Use xcrun staple to add a staple to our package'''
    display("Stapling package", options.quiet)
    cmd = [
        XCRUN,
        'stapler',
        'staple',
        os.path.join(build_info['build_dir'], build_info['name']),
    ]
    retcode, proc_stdout, proc_stderr = run_subprocess(cmd)

    if retcode:
        print("stapler: FAILURE " + proc_stderr, file=sys.stderr)
        raise MunkiPkgError("Stapling failed")
    else:
        display("The staple and validate action worked!", options.quiet)


def build(project_dir, options):
    '''Build our package'''

    build_info = {}
    try:
        try:
            build_info = get_build_info(project_dir, options)
        except MunkiPkgError as err:
            print(str(err), file=sys.stderr)
            exit(-1)

        if build_info['ownership'] in ['preserve', 'preserve-other']:
            if os.geteuid() != 0:
                print("\nWARNING: build-info ownership: %s might require "
                      "using sudo to build this package.\n"
                      % build_info['ownership'], file=sys.stderr)

        add_project_subdirs(build_info)

        build_info['component_plist'] = None
        # analyze root and turn off bundle relocation
        if build_info['payload'] and build_info['suppress_bundle_relocation']:
            build_info['component_plist'] = make_component_property_list(
                build_info, options)

        # make a stub PkgInfo file
        build_info['pkginfo_path'] = make_pkginfo(build_info, options)

        # remove any pre-existing pkg at the outputname path
        outputname = os.path.join(build_info['build_dir'], build_info['name'])
        if os.path.exists(outputname):
            retcode = subprocess.call(["/bin/rm", "-rf", outputname])
            if retcode:
                raise BuildError("Could not remove existing %s" % outputname)

        if build_info['scripts']:
            # remove .DS_Store file from the scripts folder
            if os.path.exists(os.path.join(build_info['scripts'], ".DS_Store")):
                display("Removing .DS_Store file from the scripts folder",
                        options.quiet)
                os.remove(os.path.join(build_info['scripts'], ".DS_Store"))

            # make scripts executable
            for pkgscript in ("preinstall", "postinstall"):
                scriptpath = os.path.join(build_info['scripts'], pkgscript)
                if (os.path.exists(scriptpath) and
                        (os.stat(scriptpath).st_mode & 0o500) != 0o500):
                    display("Making %s script executable" % pkgscript,
                            options.quiet)
                    os.chmod(scriptpath, 0o755)

        # build the pkg
        build_pkg(build_info, options)

        # export bom info if requested
        if options.export_bom_info:
            export_bom_info(build_info, options)

        # convert pkg to distribution-style if requested
        if build_info['distribution_style']:
            build_distribution_pkg(build_info, options)

        # notarize the pkg
        if 'notarization_info' in build_info and not options.skip_notarization:
            try:
                request_uuid = upload_to_notary(build_info, options)
                if not options.skip_stapling and wait_for_notarization(
                    request_uuid, build_info, options
                ):
                    staple(build_info, options)
            except MunkiPkgError as err:
                print("ERROR: %s" % err, file=sys.stderr)
                return -1

        # cleanup temp dir
        _ = subprocess.call(["/bin/rm", "-rf", build_info['tmpdir']])
        return 0

    except BuildError as err:
        print('ERROR: %s' % err, file=sys.stderr)
        if build_info.get('tmpdir'):
            # cleanup temp dir
            _ = subprocess.call(["/bin/rm", "-rf", build_info['tmpdir']])
        return -1


def get_pkginfo_attr(pkginfo_dom, attribute_name):
    """Returns value for attribute_name from PackageInfo dom"""
    pkgrefs = pkginfo_dom.getElementsByTagName('pkg-info')
    if pkgrefs:
        for ref in pkgrefs:
            keys = list(ref.attributes.keys())
            if attribute_name in keys:
                return ref.attributes[attribute_name].value.encode('UTF-8')
    return None


def expand_payload(project_dir):
    '''expand Payload if present'''
    payload_file = os.path.join(project_dir, 'Payload')
    payload_archive = os.path.join(project_dir, 'Payload.cpio.gz')
    payload_dir = os.path.join(project_dir, 'payload')
    if os.path.exists(payload_file):
        try:
            os.rename(payload_file, payload_archive)
            os.mkdir(payload_dir)
        except OSError as err:
            raise PkgImportError(err)
        cmd = [DITTO, '-x', payload_archive, payload_dir]
        retcode = subprocess.call(cmd)
        if retcode:
            raise PkgImportError("Ditto failed to expand Payload")
        unlink_if_possible(payload_archive)


def convert_packageinfo(pkg_path, project_dir, options):
    '''parse PackageInfo file and create build-info file'''
    package_info_file = os.path.join(project_dir, 'PackageInfo')

    pkginfo = minidom.parse(package_info_file)
    build_info = {}

    build_info['identifier'] = get_pkginfo_attr(pkginfo, 'identifier') or ''
    build_info['version'] = get_pkginfo_attr(pkginfo, 'version') or '1.0'
    build_info['install_location'] = get_pkginfo_attr(
        pkginfo, 'install-location') or '/'
    build_info['postinstall_action'] = get_pkginfo_attr(
        pkginfo, 'postinstall-action') or 'none'
    build_info['preserve_xattr'] = get_pkginfo_attr(
        pkginfo, 'preserve-xattr') == "true"
    build_info['name'] = os.path.basename(pkg_path)
    if non_recommended_permissions_in_bom(project_dir):
        build_info['ownership'] = 'preserve'

    distribution_file = os.path.join(project_dir, 'Distribution')
    build_info['distribution_style'] = os.path.exists(distribution_file)

    write_build_info(build_info, project_dir, options)
    unlink_if_possible(package_info_file)


def convert_info_plist(pkg_path, project_dir, options):
    '''Read bundle pkg Info.plist and create build-info file'''
    info_plist = os.path.join(pkg_path, 'Contents/Info.plist')
    info = readPlist(info_plist)
    build_info = {}

    build_info['identifier'] = info.get('CFBundleIdentifier', '')
    build_info['version'] = (info.get('CFBundleShortVersionString') or
                             info.get('CFBundleVersion') or '1.0')
    build_info['install_location'] = info.get('IFPkgFlagDefaultLocation') or '/'
    build_info['postinstall_action'] = 'none'
    if (info.get('IFPkgFlagRestartAction') in
            ['RequireRestart', 'RecommendRestart']):
        build_info['postinstall_action'] = 'restart'
    if (info.get('IFPkgFlagRestartAction') in
            ['RequireLogout', 'RecommendLogout']):
        build_info['postinstall_action'] = 'logout'
    build_info['name'] = os.path.basename(pkg_path)
    if non_recommended_permissions_in_bom(project_dir):
        build_info['ownership'] = 'preserve'
    write_build_info(build_info, project_dir, options)


def handle_distribution_pkg(project_dir):
    '''If the expanded pkg is a distribution pkg, handle this case'''
    distribution_file = os.path.join(project_dir, 'Distribution')
    if os.path.exists(distribution_file):
        # we have a Distribution-style pkg here
        # look for a _single_ *.pkg dir
        pkgs_pattern = os.path.join(project_dir, '*.pkg')
        pkgs = glob.glob(pkgs_pattern)
        if len(pkgs) != 1:
            raise PkgImportError(
                "Distribution packages to be imported must contain exactly "
                "one component package! Found: %s" % pkgs)
        # move items of interest
        pkg = pkgs[0]
        for item in ['Bom', 'PackageInfo', 'Payload', 'Scripts']:
            source_path = os.path.join(pkg, item)
            if os.path.exists(source_path):
                dest_path = os.path.join(project_dir, item)
                try:
                    os.rename(source_path, dest_path)
                except OSError as err:
                    raise PkgImportError(err)
        try:
            os.rmdir(pkg)
        except OSError:
            # we don't really care
            pass


def script_names(kind='all'):
    '''Return a list of known script names for bundle-style packages.
    If kind is 'pre' or 'post', return just the pre or post names'''
    pre_script_names = ['preflight', 'preinstall', 'preupgrade']
    post_script_names = ['postflight', 'postinstall', 'postupgrade']
    if kind == 'pre':
        return pre_script_names
    if kind == 'post':
        return post_script_names
    return pre_script_names + post_script_names


def copy_bundle_pkg_scripts(pkg_path, project_dir, options):
    '''Copies scripts and other items to project scripts directory'''
    # if any of the known script names are in the Resources folder,
    # copy things that aren't *.lproj and package_version from
    # Resources to project_dir/scripts

    resources_dir = os.path.join(pkg_path, 'Contents/Resources')
    resources_items = os.listdir(resources_dir)

    # does resources_dir contain any of the known script_names?
    if set(resources_items).intersection(set(script_names())):
        scripts_dir = os.path.join(project_dir, 'scripts')
        os.mkdir(scripts_dir)
        for item in resources_items:
            if item.endswith('.lproj') or item == "package_version":
                # we don't need to copy these to scripts dir
                continue
            source_item = os.path.join(resources_dir, item)
            dest_item = os.path.join(scripts_dir, item)
            if os.path.isdir(source_item):
                shutil.copytree(source_item, dest_item)
            else:
                shutil.copy2(source_item, dest_item)

        # rename pre- and post- scripts or print a warning
        for kind in ['pre', 'post']:
            found_scripts = [item for item in os.listdir(scripts_dir)
                             if item in script_names(kind)]
            supported_name = kind + 'install'
            if len(found_scripts) == 1 and found_scripts[0] != supported_name:
                # rename it
                current_script_path = os.path.join(
                    scripts_dir, found_scripts[0])
                new_script_path = os.path.join(scripts_dir, supported_name)
                display('Renaming %s script to %s'
                        % (found_scripts[0], supported_name), options.quiet)
                os.rename(current_script_path, new_script_path)
            elif len(found_scripts) > 1:
                print("WARNING: Multiple %sXXXXXX scripts found. "
                      "Flat packages support only '%sinstall'." % (kind, kind),
                      file=sys.stderr)


def import_bundle_pkg(pkg_path, project_dir, options):
    '''Imports a bundle-style package'''
    try:
        dist_files = glob.glob(os.path.join(pkg_path, 'Contents/*.dist'))
        if dist_files:
            raise PkgImportError(
                "Bundle-style distribution packages are not supported for "
                'import. Consider importing the included sub-package(s).')

        # create the project dir
        os.mkdir(project_dir)

        # export Bom.txt
        bomfile = os.path.join(pkg_path, 'Contents/Archive.bom')
        export_bom(bomfile, project_dir)

        # export Archive as payload
        archive = os.path.join(pkg_path, 'Contents/Archive.pax.gz')
        payload_dir = os.path.join(project_dir, 'payload')
        try:
            os.mkdir(payload_dir)
        except OSError as err:
            raise PkgImportError(err)
        cmd = [DITTO, '-x', archive, payload_dir]
        retcode = subprocess.call(cmd)
        if retcode:
            raise PkgImportError("Ditto failed to expand Payload")

        copy_bundle_pkg_scripts(pkg_path, project_dir, options)
        convert_info_plist(pkg_path, project_dir, options)
        if (non_recommended_permissions_in_bom(project_dir) and
                os.geteuid() != 0):
            print(
                '\nWARNING: package contains non-default owner/group on some '
                'files. build-info ownership has been set to "preserve". '
                '\nCheck the bom for accuracy.'
                '\nRun munkipkg --sync with sudo to apply the correct owner '
                'and group to payload files.\n', file=sys.stderr
            )
        sync_from_bom_info(project_dir, options)
        create_default_gitignore(project_dir)
        display("Created new package project at %s"
                % project_dir, options.quiet)
        return 0
    except (MunkiPkgError, OSError) as err:
        print('ERROR: %s' % err, file=sys.stderr)
        return -1


def import_flat_pkg(pkg_path, project_dir, options):
    '''Imports a flat package'''
    try:
        # expand flat pkg into project dir
        cmd = [PKGUTIL, '--expand', pkg_path, project_dir]
        retcode = subprocess.call(cmd)
        if retcode:
            raise PkgImportError("Could not expand package.")

        handle_distribution_pkg(project_dir)

        # export Bom.txt
        bomfile = os.path.join(project_dir, 'Bom')
        export_bom(bomfile, project_dir)
        unlink_if_possible(bomfile)

        # rename Scripts directory
        uppercase_scripts_dir = os.path.join(project_dir, 'Scripts')
        lowercase_scripts_dir = os.path.join(project_dir, 'scripts')
        if os.path.exists(uppercase_scripts_dir):
            os.rename(uppercase_scripts_dir, lowercase_scripts_dir)

        expand_payload(project_dir)
        convert_packageinfo(pkg_path, project_dir, options)
        if (non_recommended_permissions_in_bom(project_dir) and
                os.geteuid() != 0):
            print(
                '\nWARNING: package contains non-default owner/group on some '
                'files. build-info ownership has been set to "preserve". '
                '\nCheck the bom for accuracy.'
                '\nRun munkipkg --sync with sudo to apply the correct owner '
                'and group to payload files.\n', file=sys.stderr
            )
        sync_from_bom_info(project_dir, options)
        create_default_gitignore(project_dir)
        display("Created new package project at %s"
                % project_dir, options.quiet)
        return 0
    except (MunkiPkgError, OSError) as err:
        print('ERROR: %s' % err, file=sys.stderr)
        return -1


def import_pkg(pkg_path, project_dir, options):
    '''Imports an existing pkg into a project directory. Returns a
    boolean to indicate success or failure.'''
    if os.path.exists(project_dir):
        print("ERROR: Directory %s already exists." % project_dir,
              file=sys.stderr)
        return False

    if os.path.isdir(pkg_path):
        return import_bundle_pkg(pkg_path, project_dir, options)
    return import_flat_pkg(pkg_path, project_dir, options)


def valid_project_dir(project_dir):
    '''validate project dir. Returns a boolean'''
    if not os.path.exists(project_dir):
        print(("ERROR: %s: Project not found." % project_dir), file=sys.stderr)
        return False
    elif not os.path.isdir(project_dir):
        print(("ERROR: %s is not a directory." % project_dir), file=sys.stderr)
        return False
    return True


def main():
    '''Main'''
    usage = """usage: %prog [options] pkg_project_directory
       A tool for building a package from the contents of a
       pkg_project_directory."""
    parser = optparse.OptionParser(usage=usage, version=VERSION)
    parser.add_option('--create', action='store_true',
                      help='Creates a new empty project with default settings '
                           'at given path.')
    parser.add_option('--import', dest='import_pkg', metavar='PKG',
                      help='Imports an existing package PKG as a package '
                      'project, creating pkg_project_directory.')
    parser.add_option('--json', action='store_true',
                      help='Create build-info file in JSON format. '
                           'Useful only with --create and --import options.')
    parser.add_option('--yaml', action='store_true',
                      help='Create build-info file in YAML format. '
                           'Useful only with --create and --import options.')
    parser.add_option('--export-bom-info', action='store_true',
                      help='Extracts the Bill-Of-Materials file from the '
                           'output package and exports it as Bom.txt under the '
                           'pkg_project_folder. Useful for tracking owner, '
                           'group and mode of the payload in git.')
    parser.add_option('--sync', action='store_true',
                      help='Use Bom.txt to set modes of files in payload '
                           'directory and create missing empty directories. '
                           'Useful after a git clone or pull. No build is '
                           'performed.')
    parser.add_option('--quiet', action='store_true',
                      help='Inhibits status messages on stdout. '
                           'Any error messages are still sent to stderr.')
    parser.add_option('-f', '--force', action='store_true',
                      help='Forces creation of project directory if it already '
                           'exists. ')
    parser.add_option('--skip-notarization', action='store_true',
                      help='Skips whole notarization process when '
                           'notarization is specified in build-info')
    parser.add_option('--skip-stapling', action='store_true',
                      help='Skips only stapling part of notarization process '
                           'when notarization is specified in build-info')
    options, arguments = parser.parse_args()

    if not arguments:
        parser.print_usage()
        sys.exit(0)

    if len(arguments) > 1:
        print("ERROR: Only a single package project can be built at a time!",
              file=sys.stderr)
        sys.exit(-1)

    if options.json and options.yaml:
        print("ERROR: Only a single build-info file can be built at a time!",
              file=sys.stderr)
        sys.exit(-1)

    if options.yaml and not YAML_INSTALLED:
        print(
            "ERROR: PyYAML missing. Please run 'sudo easy_install pip' "
            "followed by 'sudo pip install -r requirements.txt'",
            file=sys.stderr
        )
        sys.exit(-1)

    if options.create:
        result = create_template_project(arguments[0], options)
        sys.exit(result)

    if options.import_pkg:
        result = import_pkg(options.import_pkg, arguments[0], options)
        sys.exit(result)

    # options past here require a valid project_dir
    if not valid_project_dir(arguments[0]):
        sys.exit(-1)

    if options.sync:
        result = sync_from_bom_info(arguments[0], options)
    else:
        result = build(arguments[0], options)
    sys.exit(result)

if __name__ == '__main__':
    main()
