# Copyright 2018 The Bazel Authors.
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

load(
    "@com_grail_rules_r//internal:shell.bzl",
    _sh_quote_args = "sh_quote_args",
)
load(
    "@com_grail_rules_r//R/internal:common.bzl",
    _build_path_export = "build_path_export",
    _env_vars = "env_vars",
    _executables = "executables",
    _flatten_pkg_deps_list = "flatten_pkg_deps_list",
    _library_deps = "library_deps",
    _makevars_files = "makevars_files",
    _package_dir = "package_dir",
    _tests_dir = "tests_dir",
)
load("@com_grail_rules_r//R:providers.bzl", "RLibrary", "RPackage")

# From the global R Makeconf.
_NATIVE_SOURCE_EXTS = [
    "c",
    "cc",
    "cpp",
    "h",
    "hpp",
    "m",
    "mm",
    "M",
    "f",
    "f95",
    "f90",
]

# From https://cran.r-project.org/doc/manuals/r-release/R-exts.html#DOCF13.
_R_SOURCE_EXTS = [
    "R",
    "S",
    "q",
    "r",
    "s",
]

_SOURCE_EXTS = _NATIVE_SOURCE_EXTS + _R_SOURCE_EXTS

def _package_name(ctx):
    # Package name from attribute with fallback to label name.

    pkg_name = ctx.attr.pkg_name
    if pkg_name == "":
        pkg_name = ctx.label.name
    return pkg_name

def _strip_path_prefixes(iterable, p1, p2):
    # Given an iterable of paths and two path prefixes, removes the prefixes and
    # filter empty paths.

    res = []
    for s in iterable:
        if not s or s == p1 or s == p2:
            res.append(".")
        elif s.startswith(p1 + "/"):
            res.append(s[(len(p1) + 1):])
        elif s.startswith(p2 + "/"):
            res.append(s[(len(p2) + 1):])
        else:
            res.append(s)
    return res

def _link_info(dep, root_path):
    # Returns libraries to link from a cc_dep, giving preference to PIC.

    linking_context = dep[CcInfo].linking_context
    libraries_to_link = linking_context.libraries_to_link
    user_link_flags = linking_context.user_link_flags
    libs = []
    c_so_files = []
    c_libs_flags = list(user_link_flags)
    c_libs_flags_short = list(user_link_flags)

    # https://github.com/bazelbuild/bazel/issues/8118
    # TODO: Simplify when we don't support bazel 0.26.
    if hasattr(linking_context.libraries_to_link, "to_list"):
        libraries_to_link = linking_context.libraries_to_link.to_list()
    else:
        libraries_to_link = linking_context.libraries_to_link

    for library_to_link in libraries_to_link:
        if library_to_link.pic_static_library != None:
            l = library_to_link.pic_static_library
        elif library_to_link.static_library != None:
            l = library_to_link.static_library
        elif library_to_link.interface_library != None:
            l = library_to_link.interface_library
        elif library_to_link.dynamic_library != None:
            l = library_to_link.dynamic_library
        else:
            fail("unreachable")

        libs.append(l)

        # dylib is not supported because macOS does not support $ORIGIN in rpath.
        if l.extension == "so":
            c_so_files.append(l)

            # We copy the file in srcs and set relative rpath for R CMD INSTALL.
            c_libs_flags.append(l.basename)

            # We use LD_LIBRARY_PATH for R CMD check.
            c_libs_flags_short.append(root_path + l.short_path)
            continue

        c_libs_flags.append(root_path + l.path)
        c_libs_flags_short.append(root_path + l.short_path)

    return struct(
        c_libs_flags = c_libs_flags,
        c_libs_flags_short = c_libs_flags_short,
        c_so_files = c_so_files,
        libs = libs,
    )

def _cc_deps(ctx, instrumented):
    # Returns information for native code compilation.

    cc_deps = ctx.attr.cc_deps
    bin_dir = ctx.bin_dir.path
    gen_dir = ctx.genfiles_dir.path

    # Give absolute paths to R.
    root_path = "_EXEC_ROOT_"

    # bazel currently instruments all cc libraries if instrumentation is enabled.
    # TODO: Track this behavior and  when instrumentation filters work as
    # expected, change default to False, setting to True only if coverage is
    # enabled and any transitive dep is instrumented.
    instrumented_cc_deps = (cc_deps and ctx.configuration.coverage_enabled)

    # Keep the original order of linker flags, and do not remove duplicates.
    # https://stackoverflow.com/a/409470
    libs = []
    c_so_files = []
    c_libs_flags = []
    c_libs_flags_short = []
    for dep in cc_deps:
        link_info = _link_info(dep, root_path)
        libs.extend(link_info.libs)
        c_so_files.extend(link_info.c_so_files)
        c_libs_flags.extend(link_info.c_libs_flags)
        c_libs_flags_short.extend(link_info.c_libs_flags_short)

    hdrs_sets = [d[CcInfo].compilation_context.headers for d in cc_deps]
    defines = depset(transitive = [d[CcInfo].compilation_context.defines for d in cc_deps]).to_list()
    quote_includes = depset(transitive = [d[CcInfo].compilation_context.quote_includes for d in cc_deps]).to_list()
    system_includes = depset(transitive = [d[CcInfo].compilation_context.system_includes for d in cc_deps]).to_list()
    includes = depset(transitive = [d[CcInfo].compilation_context.includes for d in cc_deps]).to_list()

    c_cpp_flags = []
    c_cpp_flags_short = []
    for i in defines:
        c_cpp_flags += ["-D" + i]
        c_cpp_flags_short += ["-D" + i]
    for i in quote_includes:
        c_cpp_flags += ["-iquote " + root_path + i]
    for i in system_includes:
        c_cpp_flags += ["-isystem " + root_path + i]
    for i in includes:
        c_cpp_flags += ["-I " + root_path + i]

    for i in _strip_path_prefixes(quote_includes, bin_dir, gen_dir):
        c_cpp_flags_short += ["-iquote " + root_path + i]
    for i in _strip_path_prefixes(system_includes, bin_dir, gen_dir):
        c_cpp_flags_short += ["-isystem " + root_path + i]
    for i in _strip_path_prefixes(includes, bin_dir, gen_dir):
        c_cpp_flags_short += ["-I " + root_path + i]

    # Note that clang has multiple code coverage implementations. covr can only
    # use the gcc compatible implementation based on DebugInfo.  This might be
    # different from how your other C++ libraries are being instrumented if you
    # are using an LLVM toolchain. And so we ignore cc_deps when computing
    # coverage.
    # https://cran.r-project.org/web/packages/covr/vignettes/how_it_works.html
    # https://clang.llvm.org/docs/SourceBasedCodeCoverage.html
    if instrumented:
        c_cpp_flags += [
            "--coverage",
            # Ensure that, e.g., functions are not inlined (with optimization,
            # the inlined functions would not be "hit").
            "-O0",
        ]
        c_cpp_flags_short += ["--coverage"]

    if instrumented or instrumented_cc_deps:
        c_libs_flags += ["--coverage", "-O0"]
        c_libs_flags_short += ["--coverage", "-O0"]

    return struct(
        c_cpp_flags = c_cpp_flags,
        c_cpp_flags_short = c_cpp_flags_short,
        c_libs_flags = c_libs_flags,
        c_libs_flags_short = c_libs_flags_short,
        c_so_files = depset(c_so_files).to_list(),
        files = depset(libs, transitive = hdrs_sets).to_list(),
    )

def _remove_file(files, path_to_remove):
    # Removes a file from a given sequence.

    filtered_files = []
    for f in files:
        if f.path != path_to_remove:
            filtered_files.append(f)

    return filtered_files

def _inst_files(inst_files_dict):
    # Lists all files needed to be copied into the inst directory.

    return depset(transitive = [t.files for (t, _) in inst_files_dict.items()])

def _inst_files_copy_map(ctx):
    # Returns a dictionary of destination paths to source paths for copying.

    pkg_src_dir = _package_dir(ctx)
    bin_dir = ctx.bin_dir.path
    gen_dir = ctx.genfiles_dir.path

    copy_map = dict()
    for (t, d) in ctx.attr.inst_files.items():
        file_paths = [f.path for f in t.files.to_list()]
        stripped_paths = _strip_path_prefixes(file_paths, bin_dir, gen_dir)
        copy_map.update({
            "%s/inst/%s/%s" % (pkg_src_dir, d, stripped_path): path
            for stripped_path, path in zip(stripped_paths, file_paths)
        })
    return copy_map

def _external_repo(ctx):
    # Returns True if this package is tagged as an external R package.
    return "external-r-repo" in ctx.attr.tags

def _build_impl(ctx):
    info = ctx.toolchains["@com_grail_rules_r//R:toolchain_type"].RInfo

    pkg_name = _package_name(ctx)
    pkg_src_dir = _package_dir(ctx)
    pkg_lib_dir = ctx.actions.declare_directory("lib")
    pkg_bin_archive = ctx.outputs.bin_archive
    pkg_src_archive = ctx.outputs.src_archive
    flock = ctx.attr._flock.files_to_run.executable

    # Instrumenting external R packages can be troublesome; e.g. RProtoBuf and testthat.
    external_repo = _external_repo(ctx)
    instrumented = (ctx.coverage_instrumented() and
                    not external_repo and
                    not "no-instrument" in ctx.attr.tags)

    pkg_deps = _flatten_pkg_deps_list(ctx.attr.deps)

    src_files_sans_tests = []
    test_files = []
    pkg_tests_dir = _tests_dir(pkg_src_dir)
    for src_file in ctx.files.srcs:
        if src_file.path.startswith(pkg_tests_dir):
            test_files.append(src_file)
        else:
            src_files_sans_tests.append(src_file)

    library_deps = _library_deps(pkg_deps)
    cc_deps = _cc_deps(ctx, instrumented)
    inst_files = _inst_files(ctx.attr.inst_files)
    inst_files_map = _inst_files_copy_map(ctx)
    transitive_tools = depset(
        _executables(ctx.attr.tools),
        transitive = [library_deps.transitive_tools],
    )
    build_tools = depset(
        _executables(ctx.attr.build_tools + info.tools),
        transitive = [transitive_tools],
    )
    stamp_files = [ctx.version_file]
    if ctx.attr.stamp:
        stamp_files.append(ctx.info_file)
    instrument_files = [ctx.file._instrument_R] if instrumented else []
    all_input_files = (library_deps.lib_dirs + src_files_sans_tests +
                       cc_deps.files + inst_files.to_list() +
                       build_tools.to_list() + info.files +
                       _makevars_files(info.makevars_site, ctx.file.makevars) +
                       stamp_files + instrument_files + [info.state])

    roclets_lib_dirs = []
    if ctx.attr.roclets:
        roclets_deps = _flatten_pkg_deps_list(ctx.attr.roclets_deps)
        roclets_lib_dirs = _library_deps(roclets_deps).lib_dirs
        all_input_files.extend(roclets_lib_dirs)

    if ctx.file.config_override:
        all_input_files += [ctx.file.config_override]
        orig_config = pkg_src_dir + "/configure"
        all_input_files = _remove_file(all_input_files, orig_config)

    install_args = list(ctx.attr.install_args)
    output_files = [pkg_lib_dir, pkg_bin_archive]
    pkg_gcno_dir = None

    if instrumented:
        # We need to keep the sources for code coverage to work.
        # NOTE: With these options, each installed object in package namespaces gets a
        # srcref attribute that has the source filenames as when installing the package.
        # For reproducible builds, these will be /tmp paths.
        install_args.extend(["--with-keep.source"])

        # We also need to collect the instrumented .gcno files from the package.
        pkg_gcno_dir = ctx.actions.declare_directory("src")
        output_files.append(pkg_gcno_dir)
    build_env = {
        "PKG_LIB_PATH": pkg_lib_dir.path,
        "PKG_SRC_DIR": pkg_src_dir,
        "PKG_NAME": pkg_name,
        "PKG_SRC_ARCHIVE": pkg_src_archive.path,
        "PKG_BIN_ARCHIVE": pkg_bin_archive.path,
        "R_MAKEVARS_SITE": info.makevars_site.path if info.makevars_site else "",
        "R_MAKEVARS_USER": ctx.file.makevars.path if ctx.file.makevars else "",
        "CONFIG_OVERRIDE": ctx.file.config_override.path if ctx.file.config_override else "",
        "ROCLETS": ", ".join(["'%s'" % r for r in ctx.attr.roclets]),
        "C_LIBS_FLAGS": " ".join(cc_deps.c_libs_flags),
        "C_CPP_FLAGS": " ".join(cc_deps.c_cpp_flags),
        "C_SO_FILES": _sh_quote_args([f.path for f in cc_deps.c_so_files]),
        "R_LIBS_DEPS": ":".join(["_EXEC_ROOT_" + d.path for d in library_deps.lib_dirs]),
        "R_LIBS_ROCLETS": ":".join(["_EXEC_ROOT_" + d.path for d in roclets_lib_dirs]),
        "BUILD_ARGS": _sh_quote_args(ctx.attr.build_args),
        "INSTALL_ARGS": _sh_quote_args(install_args),
        "EXPORT_ENV_VARS_CMD": "; ".join(_env_vars(info.env_vars) + _env_vars(ctx.attr.env_vars)),
        "INST_FILES_MAP": ",".join([dst + ":" + src for (dst, src) in inst_files_map.items()]),
        "BUILD_TOOLS_EXPORT_CMD": _build_path_export(build_tools),
        "METADATA_MAP": ",".join([key + ":" + value for (key, value) in ctx.attr.metadata.items()]),
        "STATUS_FILES": ",".join([f.path for f in stamp_files]),
        "FLOCK_PATH": flock.path,
        "INSTRUMENT_SCRIPT": ctx.file._instrument_R.path,
        "INSTRUMENTED": "true" if instrumented else "false",
        "BAZEL_R_DEBUG": "true" if "rlang-debug" in ctx.features else "false",
        "BAZEL_R_VERBOSE": "true" if "rlang-verbose" in ctx.features else "false",
        "R": " ".join(info.r),
        "RSCRIPT": " ".join(info.rscript),
        "REQUIRED_VERSION": info.version,
    }
    ctx.actions.run(
        outputs = output_files,
        inputs = all_input_files,
        tools = [flock],
        executable = ctx.executable._build_sh,
        env = build_env,
        mnemonic = "RBuild",
        use_default_shell_env = False,
        progress_message = "Building R package %s" % pkg_name,
    )

    # Lightweight action to build just the source archive.

    src_build_env = dict(build_env)
    src_build_env.update({"BUILD_SRC_ARCHIVE_ONLY": "true"})

    ctx.actions.run(
        outputs = [pkg_src_archive],
        inputs = all_input_files + test_files,
        tools = [flock],
        executable = ctx.executable._build_sh,
        env = src_build_env,
        mnemonic = "RSrcBuild",
        use_default_shell_env = False,
        progress_message = "Building R (source) package %s" % pkg_name,
    )

    return struct(
        instrumented_files = struct(
            # List the dependencies in which transitive instrumented files can be found.
            # NOTE: cc_deps and tools could be instrumented in a way that
            # is incompatible with covr, so we should not include them here.
            dependency_attributes = ["deps"],
            extensions = _SOURCE_EXTS,
            source_attributes = ["srcs"],
        ),
        providers = [
            DefaultInfo(
                files = depset(output_files),
                runfiles = ctx.runfiles([pkg_lib_dir], collect_default = True),
            ),
            RPackage(
                bin_archive = pkg_bin_archive,
                build_tools = build_tools,
                cc_deps = cc_deps,
                external_repo = external_repo,
                makevars = ctx.file.makevars,
                pkg_deps = pkg_deps,
                pkg_gcno_dir = pkg_gcno_dir,
                pkg_lib_dir = pkg_lib_dir,
                pkg_name = pkg_name,
                src_archive = pkg_src_archive,
                src_files = ctx.files.srcs,
                test_files = test_files,
                transitive_pkg_deps = library_deps.transitive_pkg_deps,
                transitive_tools = transitive_tools,
            ),
        ],
    )

def _build_binary_pkg_impl(ctx):
    info = ctx.toolchains["@com_grail_rules_r//R:toolchain_type"].RInfo

    pkg_name = _package_name(ctx)
    pkg_lib_dir = ctx.actions.declare_directory("lib")
    pkg_bin_archive = ctx.file.src
    pkg_deps = _flatten_pkg_deps_list(ctx.attr.deps)
    library_deps = _library_deps(pkg_deps)
    transitive_tools = depset(
        _executables(ctx.attr.tools),
        transitive = [library_deps.transitive_tools],
    )

    build_env = {
        "PKG_LIB_PATH": pkg_lib_dir.path,
        "PKG_NAME": pkg_name,
        "PKG_BIN_ARCHIVE": pkg_bin_archive.path,
        "R_LIBS_DEPS": ":".join(["_EXEC_ROOT_" + d.path for d in library_deps.lib_dirs]),
        "INSTALL_ARGS": _sh_quote_args(ctx.attr.install_args),
        "EXPORT_ENV_VARS_CMD": "; ".join(_env_vars(ctx.attr.env_vars)),
        "BAZEL_R_DEBUG": "true" if "rlang-debug" in ctx.features else "false",
        "BAZEL_R_VERBOSE": "true" if "rlang-verbose" in ctx.features else "false",
        "R": " ".join(info.r),
        "RSCRIPT": " ".join(info.rscript),
    }
    ctx.actions.run(
        outputs = [pkg_lib_dir],
        inputs = [pkg_bin_archive, info.state],
        executable = ctx.executable._build_binary_sh,
        env = build_env,
        mnemonic = "RBuildBinary",
        use_default_shell_env = False,
        progress_message = "Extracting R binary package %s" % pkg_name,
    )

    return [
        DefaultInfo(
            files = depset([pkg_lib_dir]),
            runfiles = ctx.runfiles([pkg_lib_dir], collect_default = True),
        ),
        RPackage(
            bin_archive = pkg_bin_archive,
            build_tools = None,
            cc_deps = None,
            external_repo = _external_repo(ctx),
            makevars = None,
            pkg_deps = pkg_deps,
            pkg_gcno_dir = None,
            pkg_lib_dir = pkg_lib_dir,
            pkg_name = pkg_name,
            src_archive = None,
            src_files = None,
            transitive_pkg_deps = library_deps.transitive_pkg_deps,
            transitive_tools = transitive_tools,
        ),
    ]

_COMMON_ATTRS = {
    "pkg_name": attr.string(
        doc = "Name of the package if different from the target name",
    ),
    "deps": attr.label_list(
        providers = [
            [RPackage],
            [RLibrary],
        ],
        doc = "R package dependencies of type r_pkg or r_library",
    ),
    "tools": attr.label_list(
        allow_files = True,
        doc = "Executables that code in this package will try to find in the system",
    ),
    "install_args": attr.string_list(
        doc = "Additional arguments to supply to R CMD INSTALL",
    ),
    "env_vars": attr.string_dict(
        doc = "Extra environment variables to define for building the package",
    ),
}

_PKG_ATTRS = dict(_COMMON_ATTRS)

_PKG_ATTRS.update({
    "srcs": attr.label_list(
        allow_files = True,
        mandatory = True,
        doc = "Source files to be included for building the package",
    ),
    "cc_deps": attr.label_list(
        doc = "cc_library dependencies for this package",
    ),
    "build_args": attr.string_list(
        default = [
            "--no-build-vignettes",
            "--no-manual",
        ],
        doc = "Additional arguments to supply to R CMD build",
    ),
    "config_override": attr.label(
        allow_single_file = True,
        doc = "Replace the package configure script with this file",
    ),
    "roclets": attr.string_list(
        doc = ("roclets to run before installing the package. If this is non-empty, " +
               "then you must specify roclets_deps as the R package you want to " +
               "use for running roclets. The runtime code will check if devtools " +
               "is available and use `devtools::document`, failing which, it will " +
               "check if roxygen2 is available and use `roxygen2::roxygenize`"),
    ),
    "roclets_deps": attr.label_list(
        providers = [
            [RPackage],
            [RLibrary],
        ],
        doc = "roxygen2 or devtools dependency for running roclets",
    ),
    "makevars": attr.label(
        allow_single_file = True,
        doc = "Additional Makevars file supplied as R_MAKEVARS_USER",
    ),
    "inst_files": attr.label_keyed_string_dict(
        allow_files = True,
        cfg = "target",
        doc = "Files to be bundled with the package through the inst directory. " +
              "The values of the dictionary will specify the package relative " +
              "destination path. For example, '' will bundle the files to the top level " +
              "directory, and 'mydir' will bundle all files into a directory mydir.",
    ),
    "build_tools": attr.label_list(
        allow_files = True,
        doc = "Executables that package build and load will try to find in the system",
    ),
    "metadata": attr.string_dict(
        doc = ("Metadata key-value pairs to add to the DESCRIPTION file before building. " +
               "Build status variables can be substituted when enclosed within `{}`"),
    ),
    "stamp": attr.bool(
        default = False,
        doc = ("Include the stable status file when substituting values in the metadata. " +
               "The volatile status file is always included."),
    ),
    "_build_sh": attr.label(
        allow_single_file = True,
        default = "@com_grail_rules_r//R/scripts:build.sh",
        executable = True,
        cfg = "host",
    ),
    "_flock": attr.label(
        default = "@com_grail_rules_r//R/scripts:flock",
        executable = True,
        cfg = "host",
    ),
    "_instrument_R": attr.label(
        allow_single_file = True,
        default = "@com_grail_rules_r//R/scripts:instrument.R",
    ),
})

_BINARY_PKG_ATTRS = dict(_COMMON_ATTRS)

_BINARY_PKG_ATTRS.update({
    "src": attr.label(
        allow_single_file = True,
        mandatory = True,
        doc = "Binary archive of the package",
    ),
    "_build_binary_sh": attr.label(
        allow_single_file = True,
        default = "@com_grail_rules_r//R/scripts:build_binary.sh",
        executable = True,
        cfg = "host",
    ),
})

r_pkg = rule(
    attrs = _PKG_ATTRS,
    doc = ("Rule to install the package and its transitive dependencies " +
           "in the Bazel sandbox."),
    outputs = {
        "bin_archive": "%{name}.bin.tar.gz",
        "src_archive": "%{name}.tar.gz",
    },
    toolchains = ["@com_grail_rules_r//R:toolchain_type"],
    implementation = _build_impl,
)

r_binary_pkg = rule(
    attrs = _BINARY_PKG_ATTRS,
    doc = ("Rule to install the package and its transitive dependencies in " +
           "the Bazel sandbox from a binary archive."),
    toolchains = ["@com_grail_rules_r//R:toolchain_type"],
    implementation = _build_binary_pkg_impl,
)
