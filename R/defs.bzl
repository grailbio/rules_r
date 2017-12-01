# Copyright 2017 GRAIL, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""R package build, test and install Bazel rules.

r_pkg will build the package and its dependencies and install them in
Bazel's sandbox.

r_unit_test will install all the dependencies of the package in Bazel's
sandbox and generate a script to run the test scripts from the package.

r_pkg_test will install all the dependencies of the package in Bazel's
sandbox and generate a script to run R CMD CHECK on the package.

r_library will generate binary archives for the package and its
dependencies (as a side effect of installing them to Bazel's sandbox),
install all the binary archives into a folder, and make available the
folder as a single tar. The target can also be executed using bazel run.
See usage by running with -h flag.
"""

_R = "R --vanilla --slave "

_Rscript = "Rscript --vanilla "

# Provider with following fields:
# "pkg_name": "Name of the package",
# "lib_loc": "Directory where this package is installed",
# "lib_files": "All installed files in this package",
# "src_files": "All source files in this package",
# "bin_archive": "Binary archive of this package",
# "pkg_deps": "Direct dependencies of this package",
# "transitive_pkg_deps": "depset of all dependencies of this target"
RPackage = provider(doc = "Build information about an R package dependency")

def _package_name(ctx):
    # Package name from attribute with fallback to label name.

    pkg_name = ctx.attr.pkg_name
    if pkg_name == "":
        pkg_name = ctx.label.name
    return pkg_name

def _target_dir(ctx):
    # Relative path to target directory.

    workspace_root = ctx.label.workspace_root
    if workspace_root != "" and ctx.label.package != "":
        workspace_root += "/"
    target_dir = workspace_root + ctx.label.package
    return target_dir

def _package_source_dir(target_dir, pkg_name):
    # Relative path to R package source.

    return target_dir

def _package_files(ctx):
    # Returns files that are installed as an R package.

    pkg_name = _package_name(ctx)
    target_dir = _target_dir(ctx)
    pkg_src_dir = _package_source_dir(target_dir, pkg_name)

    has_R_code = False
    has_sysdata = False
    has_native_code = False
    has_data_files = False
    inst_files = []
    for src_file in ctx.files.srcs:
        if src_file.path == (pkg_src_dir + "/R/sysdata.rda"):
            has_sysdata = True
        elif src_file.path.startswith(pkg_src_dir + "/R/"):
            has_R_code = True
        elif src_file.path.startswith(pkg_src_dir + "/src/"):
            has_native_code = True
        elif src_file.path.startswith(pkg_src_dir + "/data/"):
            has_data_files = True
        elif src_file.path.startswith(pkg_src_dir + "/inst/"):
            inst_files += [src_file]

    pkg_files = [
        ctx.actions.declare_file("lib/{0}/DESCRIPTION".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/NAMESPACE".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/Meta/hsearch.rds".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/Meta/links.rds".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/Meta/nsInfo.rds".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/Meta/package.rds".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/Meta/Rd.rds".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/help/AnIndex".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/help/aliases.rds".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/help/{0}.rdb".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/help/{0}.rdx".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/help/paths.rds".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/html/00Index.html".format(pkg_name)),
        ctx.actions.declare_file("lib/{0}/html/R.css".format(pkg_name)),
    ]

    if has_R_code:
        pkg_files += [
            ctx.actions.declare_file("lib/{0}/R/{0}".format(pkg_name)),
            ctx.actions.declare_file("lib/{0}/R/{0}.rdb".format(pkg_name)),
            ctx.actions.declare_file("lib/{0}/R/{0}.rdx".format(pkg_name)),
        ]

    if has_sysdata:
       pkg_files += [
           ctx.actions.declare_file("lib/{0}/R/sysdata.rdb".format(pkg_name)),
           ctx.actions.declare_file("lib/{0}/R/sysdata.rdx".format(pkg_name)),
       ]

    if has_native_code:
        shlib_name = ctx.attr.shlib_name
        if shlib_name == "":
            shlib_name = pkg_name
        pkg_files += [ctx.actions.declare_file("lib/{0}/libs/{1}.so"
                                               .format(pkg_name, shlib_name))]

    if has_data_files and ctx.attr.lazy_data:
        pkg_files += [
            ctx.actions.declare_file("lib/{0}/data/Rdata.rdb".format(pkg_name)),
            ctx.actions.declare_file("lib/{0}/data/Rdata.rds".format(pkg_name)),
            ctx.actions.declare_file("lib/{0}/data/Rdata.rdx".format(pkg_name)),
        ]

    for inst_file in inst_files:
        pkg_files += [ctx.actions.declare_file(
            "lib/{0}/{1}".format(
                pkg_name,
                inst_file.path[len(pkg_src_dir + "/inst/"):]))]

    for post_install_file in ctx.attr.post_install_files:
        pkg_files += [(ctx.actions.declare_file("lib/{0}/{1}"
                                                .format(pkg_name, post_install_file)))]

    return pkg_files

def _library_deps(target_deps, path_prefix=""):
    # Returns information about all dependencies of this package.

    # Transitive closure of all package dependencies.
    transitive_pkg_deps = depset()
    for target_dep in target_deps:
        transitive_pkg_deps += (target_dep[RPackage].transitive_pkg_deps +
                                depset([target_dep[RPackage]]))

    # Colon-separated search path to individual package libraries.
    lib_search_path = []

    # Files in the aggregated library of all dependency packages.
    lib_files = []

    # Binary archives of all dependency packages.
    bin_archives = []

    # R 3.3 has a bug in which some relative paths are not recognized in
    # R_LIBS_USER when running R CMD INSTALL (works fine for other
    # uses).  We work around this bug by creating a single directory
    # with symlinks to all deps.  Without this bug, lib_search_path can
    # be used directly.  This bug is fixed in R 3.4.
    symlink_deps_command = "mkdir -p ${{R_LIBS_USER}}\n"

    for pkg_dep in transitive_pkg_deps:
        dep_lib_loc = path_prefix + pkg_dep.lib_loc
        lib_search_path += [dep_lib_loc]
        lib_files += pkg_dep.lib_files
        bin_archives += [pkg_dep.bin_archive]
        symlink_deps_command += "ln -s $(pwd)/%s/%s ${{R_LIBS_USER}}/\n" % (dep_lib_loc,
                                                                            pkg_dep.pkg_name)

    return {
        "transitive_pkg_deps": transitive_pkg_deps,
        "lib_search_path": lib_search_path,
        "lib_files": lib_files,
        "bin_archives": bin_archives,
        "symlinked_library_command": symlink_deps_command,
    }

def _cc_deps(cc_deps, pkg_src_dir):
    # Returns a subscript to execute and additional input files.

    # Relative path of root from package's native code directory.
    levels = pkg_src_dir.count("/") + 2
    root_path = "/".join([".."] * levels) + "/"

    files = depset()
    c_libs_flags = depset()
    cpp_flags = depset()
    for d in cc_deps:
        files += (d.cc.libs.to_list()
                  + d.cc.transitive_headers.to_list())

        c_libs_flags += d.cc.link_flags
        for l in d.cc.libs:
            c_libs_flags += [root_path + l.path]

        cpp_flags += d.cc.defines
        for i in d.cc.quote_include_directories:
            cpp_flags += ["-iquote " + root_path + i]
        for i in d.cc.system_include_directories:
            cpp_flags += ["-isystem " + root_path + i]

    script = ""
    if cc_deps:
        script = "\n".join([
            # The original Makevars file will be read-only.
            "TMP_MAKEVARS=$(mktemp)",
            "cp ${{R_MAKEVARS_USER}} ${{TMP_MAKEVARS}}",
            "export R_MAKEVARS_USER=${{TMP_MAKEVARS}}",
            "",
            "LIBS_LINE='PKG_LIBS += %s\\n'" % " ".join(c_libs_flags.to_list()),
            "CPPFLAGS_LINE='PKG_CPPFLAGS += %s\\n'" % " ".join(cpp_flags.to_list()),
            "echo -e ${{LIBS_LINE}} >> ${{R_MAKEVARS_USER}}",
            "echo -e ${{CPPFLAGS_LINE}} >> ${{R_MAKEVARS_USER}}",
        ])

    return {
        "files": files,
        "script": script,
    }

def _remove_file(files, path_to_remove):
    # Removes a file from a depset of a list, and returns the new depset.

    new_depset = depset()
    for f in files:
        if f.path != path_to_remove:
            new_depset += [f]

    return new_depset

def _env_vars(env_vars):
    # Array of commands to export environment variables.

    return ["export %s=%s" % (name, value) for name, value in env_vars.items()]

def _build_impl(ctx):
    # Implementation for the r_pkg rule.

    pkg_name = _package_name(ctx)
    target_dir = _target_dir(ctx)
    pkg_src_dir = _package_source_dir(target_dir, pkg_name)
    pkg_lib_dir = "{0}/lib".format(target_dir)
    pkg_lib_path = "{0}/{1}".format(ctx.bin_dir.path, pkg_lib_dir)
    pkg_bin_archive = ctx.actions.declare_file(ctx.label.name + ".bin.tar.gz")
    package_files = _package_files(ctx)
    output_files = package_files + [pkg_bin_archive]

    library_deps = _library_deps(ctx.attr.deps, path_prefix=(ctx.bin_dir.path + "/"))
    cc_deps = _cc_deps(ctx.attr.cc_deps, pkg_src_dir)
    all_input_files = (library_deps["lib_files"] + ctx.files.srcs
                       + cc_deps["files"].to_list()
                       + [ctx.file.makevars_darwin, ctx.file.makevars_linux])

    config_override_cmd = ""
    if ctx.file.config_override != None:
        all_input_files += [ctx.file.config_override]
        orig_config = pkg_src_dir + "/configure"
        all_input_files = _remove_file(all_input_files, orig_config)
        config_override_cmd = " ".join(
            ["cp", ctx.file.config_override.path, orig_config])

    command = ("\n".join([
        "set -euo pipefail",
        "",
        "PWD=$(pwd)",
        "mkdir -p {0}",
        "if [[ $(uname) == \"Darwin\" ]]; then export R_MAKEVARS_USER=${{PWD}}/{4};",
        "else export R_MAKEVARS_USER=${{PWD}}/{5}; fi",
        "",
        cc_deps["script"],
        "%s" % config_override_cmd,
        "",
        "export PATH",  # PATH needs to be exported to R.
        "",
        "export R_LIBS_USER=$(mktemp -d)",
        library_deps["symlinked_library_command"],
        "",
        "set +e",
        "OUT=$(%s CMD INSTALL {6} --build --library={0} {1} 2>&1 )" % _R,
        "if (( $? )); then",
        "  echo \"${{OUT}}\"",
        "  rm -rf ${{R_LIBS_USER}}",
        "  exit 1",
        "fi",
        "set -e",
        "",
        "mv {2}*gz {3}",  # .tgz on macOS and .tar.gz on Linux.
        "rm -rf ${{R_LIBS_USER}}",
    ]).format(pkg_lib_path, pkg_src_dir, pkg_name, pkg_bin_archive.path,
              ctx.file.makevars_darwin.path, ctx.file.makevars_linux.path,
              ctx.attr.install_args))
    ctx.actions.run_shell(outputs=output_files, inputs=all_input_files, command=command,
                          env=ctx.attr.env_vars, mnemonic="RBuild",
                          progress_message="Building R package %s" % pkg_name)

    return [DefaultInfo(files=depset(output_files)),
            RPackage(pkg_name=pkg_name,
                     lib_loc=pkg_lib_dir,
                     lib_files=package_files,
                     src_files=ctx.files.srcs,
                     bin_archive=pkg_bin_archive,
                     pkg_deps=ctx.attr.deps,
                     transitive_pkg_deps=library_deps["transitive_pkg_deps"])]

r_pkg = rule(
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            mandatory = True,
            doc = "Source files to be included for building the package",
        ),
        "pkg_name": attr.string(
            doc = "Name of the package if different from the target name",
        ),
        "deps": attr.label_list(
            providers = [RPackage],
            doc = "R package dependencies of type r_pkg",
        ),
        "cc_deps": attr.label_list(
            doc = "cc_library dependencies for this package",
        ),
        "install_args": attr.string(
            doc = "Additional arguments to supply to R CMD INSTALL",
        ),
        "config_override": attr.label(
            allow_single_file = True,
            doc = "Replace the package configure script with this file",
        ),
        "makevars_darwin": attr.label(
            allow_single_file = True,
            default = "@com_grail_rules_r//R:Makevars.darwin.generated",
            doc = "Makevars file to use for macOS overrides",
        ),
        "makevars_linux": attr.label(
            allow_single_file = True,
            default = "@com_grail_rules_r//R:Makevars.linux",
            doc = "Makevars file to use for Linux overrides",
        ),
        "shlib_name": attr.string(
            doc = "Shared library name, if different from package name",
        ),
        "lazy_data": attr.bool(
            default = False,
            doc = "Set to True if the package uses the LazyData feature",
        ),
        "post_install_files": attr.string_list(
            doc = "Extra files that the install process generates",
        ),
        "env_vars": attr.string_dict(
            doc = "Extra environment variables to define for building the package",
        ),
    },
    doc = ("Rule to install the package and its transitive dependencies" +
           "in the Bazel sandbox."),
    implementation = _build_impl,
)

def _test_impl(ctx):
    library_deps = _library_deps([ctx.attr.pkg] + ctx.attr.suggested_deps)

    pkg_name = ctx.attr.pkg[RPackage].pkg_name
    pkg_tests_dir = _package_source_dir(_target_dir(ctx), pkg_name) + "/tests"
    test_files = []
    for src_file in ctx.attr.pkg[RPackage].src_files:
        if src_file.path.startswith(pkg_tests_dir):
            test_files += [src_file]

    script = "\n".join([
        "#!/bin/bash",
        "set -euo pipefail",
        "test -d {0}",
        "",
    ] + _env_vars(ctx.attr.env_vars) + [
        "",
        "if ! compgen -G '{0}/*.R' >/dev/null; then", 
        "  echo 'No test files found.'",
        "  exit 1",
        "fi",
        "",
        "export R_LIBS_USER=$(mktemp -d)",
        library_deps["symlinked_library_command"],
        "",
        "if [[ ${{TEST_TMPDIR:-}} ]]; then",
        "  readonly IS_TEST_SANDBOX=1",
        "else",
        "  readonly IS_TEST_SANDBOX=0",
        "fi",
        "(( IS_TEST_SANDBOX )) || TEST_TMPDIR=$(mktemp -d)",
        "",
        "# Copy the tests to a writable directory.",
        "cp -LR {0}/* ${{TEST_TMPDIR}}",
        "pushd ${{TEST_TMPDIR}} >/dev/null",
        "",
        "cleanup() {{",
        "  popd >/dev/null",
        "  (( IS_TEST_SANDBOX )) || rm -rf ${{TEST_TMPDIR}}",
        "  rm -rf ${{R_LIBS_USER}}",
        "}}",
        "",
        "for SCRIPT in *.R; do",
        "  if ! " + _Rscript + "${{SCRIPT}}; then",
        "    cleanup",
        "    exit 1",
        "  fi",
        "done",
        "",
        "cleanup",
    ]).format(pkg_tests_dir)

    ctx.actions.write(
        output=ctx.outputs.executable,
        content=script)

    runfiles = ctx.runfiles(files=library_deps["lib_files"] + test_files)
    return [DefaultInfo(runfiles=runfiles)]

r_unit_test = rule(
    attrs = {
        "pkg": attr.label(
            mandatory = True,
            providers = [RPackage],
            doc = "R package (of type r_pkg) to test",
        ),
        "suggested_deps": attr.label_list(
            providers = [RPackage],
            doc = "R package dependencies of type r_pkg",
        ),
        "env_vars": attr.string_dict(
            doc = "Extra environment variables to define before running the test",
        ),
    },
    doc = ("Rule to keep all deps in the sandbox, and run the test " +
           "scripts of the specified package. The package itself must " +
           "be one of the deps."),
    test = True,
    implementation = _test_impl,
)

def _check_impl(ctx):
    library_deps = _library_deps(ctx.attr.pkg[RPackage].pkg_deps + ctx.attr.suggested_deps)
    all_input_files = library_deps["lib_files"] + ctx.attr.pkg[RPackage].src_files

    # Bundle the package as a runfile for the test.
    pkg_name = ctx.attr.pkg[RPackage].pkg_name
    target_dir = _target_dir(ctx)
    pkg_src_dir = _package_source_dir(target_dir, pkg_name)
    pkg_src_archive = ctx.actions.declare_file(pkg_name + ".tar.gz")
    command = "\n".join([
        "OUT=$(%s CMD build {0} {1} 2>&1 )  && mv {2}*.tar.gz {3}" % _R,
        "if (( $? )); then",
        "  echo \"${{OUT}}\"",
        "  exit 1",
        "fi",
        ]).format(ctx.attr.build_args, pkg_src_dir, pkg_name,
                  pkg_src_archive.path)
    ctx.actions.run_shell(
        outputs=[pkg_src_archive], inputs=all_input_files,
        command=command, mnemonic="RBuildSource",
        progress_message="Building R (source) package %s" % pkg_name)

    script = "\n".join([
        "#!/bin/bash",
        "set -euxo pipefail",
        "test -e {0}",
        "",
    ] + _env_vars(ctx.attr.env_vars) + [
        "",
        "export R_LIBS_USER=$(mktemp -d)",
        library_deps["symlinked_library_command"],
        _R + "CMD check {1} {0}",
        "rm -rf ${{R_LIBS_USER}}",
        ""
    ]).format(pkg_src_archive.short_path, ctx.attr.check_args)

    ctx.actions.write(
        output=ctx.outputs.executable,
        content=script)

    runfiles = ctx.runfiles(
        files=[pkg_src_archive] + library_deps["lib_files"])
    return [DefaultInfo(runfiles=runfiles)]

r_pkg_test = rule(
    attrs = {
        "pkg": attr.label(
            mandatory = True,
            providers = [RPackage],
            doc = "R package (of type r_pkg) to test",
        ),
        "suggested_deps": attr.label_list(
            providers = [RPackage],
            doc = "R package dependencies of type r_pkg",
        ),
        "build_args": attr.string(
            default = "--no-build-vignettes --no-manual",
            doc = "Additional arguments to supply to R CMD build",
        ),
        "check_args": attr.string(
            default = "--no-build-vignettes --no-manual",
            doc = "Additional arguments to supply to R CMD check",
        ),
        "env_vars": attr.string_dict(
            doc = "Extra environment variables to define before running the test",
        ),
    },
    doc = ("Rule to keep all deps of the package in the sandbox, build " +
           "a source archive of this package, and run R CMD check on " +
           "the package source archive in the sandbox."),
    test = True,
    implementation = _check_impl,
)

def _library_tar_impl(ctx):
    library_deps = _library_deps(ctx.attr.pkgs, path_prefix=(ctx.bin_dir.path + "/"))
    command = "\n".join([
        "#!/bin/bash",
        "set -euo pipefail",
        "",
        "R_LIBS_USER=$(mktemp -d)",
        library_deps["symlinked_library_command"],
        "",
        "TAR_TRANSFORM_OPT=\"--transform s|\.|%s|\"" % ctx.attr.tar_dir,
        "if [[ $(uname -s) == \"Darwin\" ]]; then",
        "  TAR_TRANSFORM_OPT=\"-s |\.|%s|\"" % ctx.attr.tar_dir,
        "fi",
        "",
        "tar -c -h -C ${{R_LIBS_USER}} -f %s ${{TAR_TRANSFORM_OPT}} ." % ctx.outputs.tar.path,
        "rm -rf ${{R_LIBS_USER}}"
    ]).format()  # symlinked_library_command assumed formatted string.
    ctx.actions.run_shell(outputs=[ctx.outputs.tar], inputs=library_deps["lib_files"],
                          command=command)
    return

def _library_impl(ctx):
    _library_tar_impl(ctx)

    library_deps = _library_deps(ctx.attr.pkgs)
    script = "\n".join([
        "#!/bin/bash",
        "set -euo pipefail",
        "",
        "args=`getopt l:s: $*`",
        "if [ $? != 0 ]; then",
        "  echo 'Usage: bazel run target_label -- [-l library_path] [-s repo_root]'",
        "  echo '  -l  library_path is the directory where R packages will be installed'",
        "  echo '  -s  if specified, will only install symlinks pointing into repo_root/bazel-bin'",
        "  exit 2",
        "fi",
        "set -- $args",
        "",
        "LIBRARY_PATH=%s" % ctx.attr.library_path,
        "SOFT_INSTALL=0",
        "for i; do",
        "  case $i",
        "  in",
        "    -l)",
        "       LIBRARY_PATH=${2}; shift;",
        "       shift;;",
        "    -s)",
        "       SOFT_INSTALL=1; BIN_DIR=${2}/bazel-bin; shift;",
        "       shift;;",
        "  esac",
        "done",
        "",
        "DEFAULT_R_LIBRARY=$(%s -e 'cat(.libPaths()[1])')" % _R,
        "LIBRARY_PATH=${LIBRARY_PATH:=${DEFAULT_R_LIBRARY}}",
        "mkdir -p ${LIBRARY_PATH}",
        "",
        "BAZEL_LIB_DIRS=(",
    ] + library_deps["lib_search_path"] + [
        ")",
        "if (( ${SOFT_INSTALL} )); then",
        "  echo \"Installing package symlinks from ${BIN_DIR} to ${LIBRARY_PATH}\"",
        "  CMD=\"ln -s -f\"",
        "else",
        "  echo \"Copying installed packages to ${LIBRARY_PATH}\"",
        "  BIN_DIR=\".\"",
        "  CMD=\"cp -R -L -f\"",
        "fi",
        "for LIB_DIR in ${BAZEL_LIB_DIRS[*]}; do",
        "  for PKG in ${BIN_DIR}/${LIB_DIR}/*; do",
        "    ${CMD} ${PKG} \"${LIBRARY_PATH}\"",
        "  done",
        "done",
    ])
    ctx.actions.write(
        output=ctx.outputs.executable,
        content=script)

    runfiles = ctx.runfiles(files=library_deps["lib_files"])
    return [DefaultInfo(runfiles=runfiles, files=depset([ctx.outputs.executable]))]

r_library = rule(
    attrs = {
        "pkgs": attr.label_list(
            providers = [RPackage],
            mandatory = True,
            doc = "Package (and dependencies) to install",
        ),
        "library_path": attr.string(
            default = "",
            doc = ("If different from system default, default library " +
                   "location for installation. For runtime overrides, " +
                   "use bazel run [target] -- -l [path]"),
        ),
        "tar_dir": attr.string(
            default = ".",
            doc = ("Subdirectory within the tarball where all the " +
                   "packages are installed"),
        ),
    },
    doc = ("Rule to install the given package and all dependencies to " +
           "a user provided or system default R library site."),
    executable = True,
    outputs = {
        "tar": "%{name}.tar",
    },
    implementation = _library_impl,
)

def r_package(pkg_name, pkg_srcs, pkg_deps, pkg_suggested_deps=[]):
    """Convenience macro to generate the r_pkg and r_library targets."""

    r_pkg(
        name = pkg_name,
        srcs = pkg_srcs,
        deps = pkg_deps,
    )

    r_library(
        name = "library",
        pkgs = [":" + pkg_name],
        tags = ["manual"],
    )

def r_package_with_test(pkg_name, pkg_srcs, pkg_deps, pkg_suggested_deps=[], test_timeout="short"):
    """Convenience macro to generate the r_pkg, r_unit_test, r_pkg_test, and r_library targets."""

    r_pkg(
        name = pkg_name,
        srcs = pkg_srcs,
        deps = pkg_deps,
    )

    r_library(
        name = "library",
        pkgs = [pkg_name],
        tags = ["manual"],
    )

    r_unit_test(
        name = "test",
        timeout = test_timeout,
        pkg = pkg_name,
        suggested_deps = pkg_suggested_deps,
    )

    r_pkg_test(
        name = "check",
        timeout = test_timeout,
        pkg = pkg_name,
        suggested_deps = pkg_suggested_deps,
    )
