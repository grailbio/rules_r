R Rules for Bazel [![Tests](https://github.com/grailbio/rules_r/actions/workflows/tests.yml/badge.svg)](https://github.com/grailbio/rules_r/actions/workflows/tests.yml)
=================

#### General Information
- [Overview](#overview)
- [Getting Started](#getting-started)
- [Configuration](#configuration)
- [External Packages](#external-packages)
- [Examples](#examples)
- [Contributing](#contributing)
- [Known Issues](#known-issues)

#### Rules
- [r_pkg](#r_pkg)
- [r_library](#r_library)
- [r_unit_test](#r_unit_test)
- [r_pkg_test](#r_pkg_test)
- [r_binary](#r_binary)
- [r_test](#r_test)
- [r_toolchain](#r_toolchain)

#### Repository Rules
- [r_repository](#r_repository)
- [r_repository_list](#r_repository_list)
- [r_rules_dependencies](#r_rules_dependencies)
- [r_coverage_dependencies](#r_coverage_dependencies)
- [r_register_toolchains](#r_register_toolchains)

#### Container Rules
- [r_library_image](R/container/README.md#r_library_image)
- [r_binary_image](R/container/README.md#r_binary_image)

<a name="overview"></a>
## Overview

These rules are used for building [R][r] packages with Bazel. Although R has an
excellent package management system, there is no continuous build and
integration system for entire R package repositories. An advantage of using
Bazel, over a custom solution of tracking the package dependency graph and
triggering builds accordingly on each commit, is that R packages can be built
and tested as part of one build system in multi-language monorepos.

These rules are mature for production use. We use these rules internally at
GRAIL to build 400+ R packages from CRAN and Bioconductor.

<a name="getting-started"></a>
## Getting started

The following assumes that you are familiar with how to use Bazel in general.

To begin, you can add the following or equivalent to your WORKSPACE file:

```python
# Change master to the git tag you want.
http_archive(
    name = "com_grail_rules_r",
    strip_prefix = "rules_r-master",
    urls = ["https://github.com/grailbio/rules_r/archive/master.tar.gz"],
)

load("@com_grail_rules_r//R:dependencies.bzl", "r_register_toolchains", "r_rules_dependencies")

r_rules_dependencies()

r_register_toolchains()
```

You can load the rules in your BUILD file like so:
```python
load("@com_grail_rules_r//R:defs.bzl",
     "r_pkg", "r_library", "r_unit_test", "r_pkg_test")
```

There are also convenience macros available which create multiple implicit
targets:
```python
load("@com_grail_rules_r//R:defs.bzl", "r_package")
```
and
```python
load("@com_grail_rules_r//R:defs.bzl", "r_package_with_test")
```

<a name="configuration"></a>
## Configuration

The following software must be installed on your system:

    1. bazel (v3.0.0 or above)
    2. R (3.4.3 or above; should be locatable using the `PATH` environment variable)

**NOTE**: After re-installing or upgrading R, please reset the registered
toolchain with `bazel sync --configure` to rebuild your packages with the new
installation.

For each package, you can also specify a different Makevars file that can be
used to have finer control over native code compilation. For macOS, the
[Makevars][Makevars] file used as default helps find `gfortran`. The site-wide
Makevars files are configured by default in the toolchains.

For _macOS_, this setup will help you cover the requirements for a large number
of packages:
```
brew install gcc pkg-config icu4c openssl
```

For _Ubuntu_, this (or equivalent for other Unix systems) helps:
```
apt-get install pkgconf libssl-dev libxml2-dev libcurl4-openssl-dev
```

#### Note

For no interference from other packages during the build (possibly other
versions installed manually by the user), it is recommended that packages other
than those with recommended priority be installed in the directory pointed to
by `R_LIBS_USER`. The Bazel build process will then be able to hide all the
other packages from R by setting a different value for `R_LIBS_USER`.

When moving to Bazel for installing R packages on your system, we recommend
cleaning up existing machines:
```
sudo Rscript \
  -e 'options("repos"="https://cloud.r-project.org")' \
  -e 'lib <- c(.Library, .Library.site)' \
  -e 'non_base_pkgs <- installed.packages(lib.loc=lib, priority=c("recommended", "NA"))[, "Package"]' \
  -e 'remove.packages(non_base_pkgs, lib=lib)'

# If not set up already, create the directory for R_LIBS_USER.
Rscript \
  -e 'dir.create(Sys.getenv("R_LIBS_USER"), recursive=TRUE, showWarnings=FALSE)'
```

For more details on how R searches different paths for packages, see
[libPaths][libPaths].

<a name="external-packages"></a>
## External packages

To depend on external packages from CRAN and other remote repos, you can define the
packages as a CSV with three columns -- Package, Version, and sha256. Then use
[r_repository_list](#r_repository_list) rule to define R repositories for each
package. For packages not in a CRAN like repo (e.g. github), you can use
[r_repository](#r_repository) rule directly. For packages on your local system
but outside your main repository, you will have to use `local_repository` with
a saved BUILD file. Same for VCS repositories.

```
load("@com_grail_rules_r//R:repositories.bzl", "r_repository", "r_repository_list")

# R packages with non-standard sources.
r_repository(
    name = "R_plotly",
    sha256 = "24c848fa2cbb6aed6a59fa94f8c9b917de5b777d14919268e88bff6c4562ed29",
    strip_prefix = "plotly-a60510e4bbce5c6bed34ef6439d7a48cb54cad0a",
    urls = [
        "https://github.com/ropensci/plotly/archive/a60510e4bbce5c6bed34ef6439d7a48cb54cad0a.tar.gz",
    ],
)

# R packages with standard sources.
# See below for an example of how to generate the CSV package_list.
r_repository_list(
    name = "r_repositories_bzl",
    build_file_overrides = "@myrepo//third-party/R:build_file_overrides.csv",
    package_list = "@myrepo//third-party/R:packages.csv",
    remote_repos = {
        "BioCsoft": "https://bioconductor.org/packages/3.11/bioc",
        "BioCann": "https://bioconductor.org/packages/3.11/data/annotation",
        "BioCexp": "https://bioconductor.org/packages/3.11/data/experiment",
        "CRAN": "https://cloud.r-project.org",
    },
)

load("@r_repositories_bzl//:r_repositories.bzl", "r_repositories")

r_repositories()
```

The list of all external R packages configured this way can be obtained from
your shell with
```
$ bazel query 'filter(":R_", //external:*)'
```

**NOTE**: Periods ('.') in the package names are replaced with underscores
('_') because bazel does not allow periods in repository names.

To generate and maintain a CSV file containing all your external dependencies
for use with `r_repository_list`, you can use the functions in the script
`repo_management.R`.

For example:
```bash
script="/path/to/rules_r/scripts/repo_management.R"
package_list_csv="/path/to/output/csv/file"
packages="comma-separated list of packages you want to add to the local cache"
bioc_version="bioc_version to use, e.g. 3.11"

# This will be the cache directory for a local copy of all the packages.
# The output CSV will always reflect the state of this directory.
local_r_repo="${HOME}/.cache/grail-r-repo"

Rscript - <<EOF
source('${script}')
pkgs <- strsplit('${packages}', ',')[[1]]
# Set ForceDownload to TRUE when switching R or Bioc versions.
# options("ForceDownload" = TRUE)
# Keep in sync with r_repository_list in WORKSPACE.
options(repos = c(
    BioCsoft = "https://bioconductor.org/packages/${bioc_version}/bioc",
    BioCann = "https://bioconductor.org/packages/${bioc_version}/data/annotation",
    BioCexp = "https://bioconductor.org/packages/${bioc_version}/data/experiment",
    CRAN = "https://cloud.r-project.org")
)
addPackagesToRepo(pkgs, repo_dir = '${local_r_repo}')
packageList('${local_r_repo}', '${package_list_csv}')
EOF
```

<a name="examples"></a>
## Examples

Some examples are available in the tests directory of this repo.
- See [tests/exampleA][exampleA] for a barebones R package.
- See [tests/exampleB][exampleB] for a barebones R package that depends on another package.
- See [tests/exampleC][exampleC] for an R package that depends on external R packages.

Also see [Razel scripts][scripts] that provide utility functions to generate `BUILD` files
and `WORKSPACE` rules.

<a name="contributing"></a>
## Contributing

Contributions are most welcome. Please submit a pull request giving the owners
of this github repo access to your branch for minor style related edits, etc. We recommend
opening an issue first to discuss the nature of your change before beginning work on it.

<a name="known-issues"></a>
## Known Issues

Please check open issues at the github repo.


# Rules

<a name="r_pkg"></a>
## r_pkg

```python
r_pkg(srcs, pkg_name, deps, cc_deps, build_args, install_args, config_override,
      roclets, roclets_deps, makevars, env_vars, inst_files, tools, build_tools,
      metadata, stamp)
```

Rule to install the package and its transitive dependencies in the Bazel
sandbox, so it can be depended upon by other package builds.

The builds produced from this rule are tested to be byte-for-byte reproducible
with the same R installation.

<table class="table table-condensed table-bordered table-params">
  <colgroup>
    <col class="col-param" />
    <col class="param-description" />
  </colgroup>
  <thead>
    <tr>
      <th colspan="2">Implicit output targets</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code><i>name</i>.bin.tar.gz</code></td>
      <td>
        Binary archive of the package.
      </td>
    </tr>
    <tr>
      <td><code><i>name</i>.tar.gz</code></td>
      <td>
        Source archive of the package.
      </td>
    </tr>
    <tr>
      <td><code><i>name</i>.so</code></td>
      <td>
        Shared archive of package native code; empty file if package does not
        have native code.
      </td>
    </tr>
  </tbody>
</table>

<table class="table table-condensed table-bordered table-params">
  <colgroup>
    <col class="col-param" />
    <col class="param-description" />
  </colgroup>
  <thead>
    <tr>
      <th colspan="2">Attributes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>srcs</code></td>
      <td>
        <p><code>List of files, required</code></p>
        <p>Source files to be included for building the package.</p>
      </td>
    </tr>
    <tr>
      <td><code>pkg_name</code></td>
      <td>
        <p><code>String; optional</code></p>
        <p>Name of the package if different from the target name.</p>
      </td>
    </tr>
    <tr>
      <td><code>deps</code></td>
      <td>
        <p><code>List of labels; optional</code></p>
        <p>R package dependencies of type `r_pkg`.</p>
      </td>
    </tr>
    <tr>
      <td><code>cc_deps</code></td>
      <td>
        <p><code>List of labels; optional</code></p>
        <p>cc_library dependencies for this package.</p>
      </td>
    </tr>
    <tr>
      <td><code>build_args</code></td>
      <td>
        <p><code>List of strings; default ["--no-build-vignettes", "--no-manual"]</code></p>
        <p>Additional arguments to supply to R CMD build. Note that building
           vignettes is disabled by default to not require Tex installation for
           users. In order to build vignettes, override this attribute, and ensure
           that the relevant binaries are available in your system default
           PATH (usually /usr/bin and /usr/local/bin)</p>
      </td>
    </tr>
    <tr>
      <td><code>install_args</code></td>
      <td>
        <p><code>List of strings; optional</code></p>
        <p>Additional arguments to supply to R CMD INSTALL.</p>
      </td>
    </tr>
    <tr>
      <td><code>config_override</code></td>
      <td>
        <p><code>File; optional</code></p>
        <p>Replace the package configure script with this file.</p>
      </td>
    </tr>
    <tr>
      <td><code>roclets</code></td>
      <td>
        <p><code>List of strings; optional</code></p>
        <p>roclets to run before installing the package. If this is non-empty,
           then you must specify roclets_deps as the R package you want to
           use for running roclets. The runtime code will check if devtools
           is available and use `devtools::document`, failing which, it will
           check if roxygen2 is available and use `roxygen2::roxygenize`.</p>
      </td>
    </tr>
    <tr>
      <td><code>roclets_deps</code></td>
      <td>
        <p><code>List of labels; optional</code></p>
        <p>roxygen2 or devtools dependency for running roclets.</p>
      </td>
    </tr>
    <tr>
      <td><code>makevars</code></td>
      <td>
        <p><code>File; optional</code></p>
        <p>Additional Makevars file supplied as R_MAKEVARS_USER.</p>
      </td>
    </tr>
    <tr>
      <td><code>env_vars</code></td>
      <td>
        <p><code>Dictionary; optional</code></p>
        <p>Extra environment variables to define for building the package.</p>
      </td>
    </tr>
    <tr>
      <td><code>inst_files</code></td>
      <td>
        <p><code>Label keyed Dictionary; optional</code></p>
        <p>Files to be bundled with the package through the inst directory.
           The values of the dictionary will specify the package relative
           destination path. For example, '' will bundle the files to the top level
           directory, and 'mydir' will bundle all files into a directory mydir.</p>
      </td>
    </tr>
    <tr>
      <td><code>tools</code></td>
      <td>
        <p><code>List of labels; optional</code></p>
        <p>Executables that code in this package will try to find in the system.</p>
      </td>
    </tr>
    <tr>
      <td><code>build_tools</code></td>
      <td>
        <p><code>List of labels; optional</code></p>
        <p>Executables that native code compilation will try to find in the system.</p>
      </td>
    </tr>
    <tr>
      <td><code>metadata</code></td>
      <td>
        <p><code>String keyed Dictionary; optional</code></p>
        <p>Metadata key-value pairs to add to the DESCRIPTION file before building.
           Build status variables can be substituted when enclosed within `{}`.</p>
      </td>
    </tr>
    <tr>
      <td><code>stamp</code></td>
      <td>
        <p><code>Bool; default False</code></p>
        <p>Include the stable status file when substituting values in the metadata.
           The volatile status file is always included.</p>
      </td>
    </tr>
  </tbody>
</table>


<a name="r_library"></a>
## r_library

```python
r_library(pkgs, library_path)
```

Executable rule to install the given packages and all dependencies to a user
provided or system default R library. Run the target with --help for usage
information.

The rule used to provide a tar archive of the library as an implicit output.
That feature is now it's own rule -- `r_library_tar`. See documentation for
[r_library_tar rule][r_library_tar] and [example][docker] usage for
container_image rule.

<table class="table table-condensed table-bordered table-params">
  <colgroup>
    <col class="col-param" />
    <col class="param-description" />
  </colgroup>
  <thead>
    <tr>
      <th colspan="2">Attributes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>pkgs</code></td>
      <td>
        <p><code>List of labels, required</code></p>
        <p>Package (and dependencies) to install.</p>
      </td>
    </tr>
    <tr>
      <td><code>library_path</code></td>
      <td>
        <p><code>String; optional</code></p>
        <p>If different from system default, default library location for installation.
        For runtime overrides, use bazel run [target] -- -l [path].</p>
      </td>
    </tr>
  </tbody>
</table>


<a name="r_unit_test"></a>
## r_unit_test

```python
r_unit_test(pkg, suggested_deps, env_vars, tools, data)
```

Rule to keep all deps in the sandbox, and run the provided R test scripts.

When run with `bazel coverage`, this rule will also produce a coverage report
in Cobertura XML format. The coverage report will contain coverage for R code
in the package, and C/C++ code in the `src` directory of R packages.

<table class="table table-condensed table-bordered table-params">
  <colgroup>
    <col class="col-param" />
    <col class="param-description" />
  </colgroup>
  <thead>
    <tr>
      <th colspan="2">Attributes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>pkg</code></td>
      <td>
        <p><code>Label; required</code></p>
        <p>R package (of type r_pkg) to test.</p>
      </td>
    </tr>
    <tr>
      <td><code>suggested_deps</code></td>
      <td>
        <p><code>List of labels; optional</code></p>
        <p>R package dependencies of type `r_pkg`.</p>
      </td>
    </tr>
    <tr>
      <td><code>env_vars</code></td>
      <td>
        <p><code>Dictionary; optional</code></p>
        <p>Extra environment variables to define before running the test.</p>
      </td>
    </tr>
    <tr>
      <td><code>tools</code></td>
      <td>
        <p><code>List of labels; optional</code></p>
        <p>Executables to be made available to the test.</p>
      </td>
    </tr>
    <tr>
      <td><code>data</code></td>
      <td>
        <p><code>List of labels; optional</code></p>
        <p>Data to be made available to the test.</p>
      </td>
    </tr>
  </tbody>
</table>


<a name="r_pkg_test"></a>
## r_pkg_test

```python
r_pkg_test(pkg, suggested_deps, check_args, env_vars, tools, data)
```

Rule to keep all deps of the package in the sandbox, build a source archive
of this package, and run R CMD check on the package source archive in the
sandbox.

<table class="table table-condensed table-bordered table-params">
  <colgroup>
    <col class="col-param" />
    <col class="param-description" />
  </colgroup>
  <thead>
    <tr>
      <th colspan="2">Attributes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>pkg</code></td>
      <td>
        <p><code>Label; required</code></p>
        <p>R package (of type r_pkg) to test.</p>
      </td>
    </tr>
    <tr>
      <td><code>suggested_deps</code></td>
      <td>
        <p><code>List of labels; optional</code></p>
        <p>R package dependencies of type `r_pkg`.</p>
      </td>
    </tr>
    <tr>
      <td><code>check_args</code></td>
      <td>
        <p><code>List of strings; default ["--no-build-vignettes, "--no-manual"]</code></p>
        <p>Additional arguments to supply to R CMD build. Note that building
           vignettes is disabled by default to not require Tex installation for
           users. In order to build vignettes, override this attribute, and ensure
           that the relevant binaries are available in your system default
           PATH (usually /usr/bin and /usr/local/bin)</p>
      </td>
    </tr>
    <tr>
      <td><code>env_vars</code></td>
      <td>
        <p><code>Dictionary; optional</code></p>
        <p>Extra environment variables to define before running the test.</p>
      </td>
    </tr>
    <tr>
      <td><code>tools</code></td>
      <td>
        <p><code>List of labels; optional</code></p>
        <p>Executables to be made available to the test.</p>
      </td>
    </tr>
    <tr>
      <td><code>data</code></td>
      <td>
        <p><code>List of labels; optional</code></p>
        <p>Data to be made available to the test.</p>
      </td>
    </tr>
  </tbody>
</table>


<a name="r_binary"></a>
## r_binary

```python
r_binary(name, src, deps, data, env_vars, tools, rscript_args, script_args, stamp)
```

Build a wrapper shell script for running an executable which will have all the
specified R packages available.

The target can be executed standalone, with `bazel run`, or called from other
executables if <code>RUNFILES_DIR</code> is exported in the environment with
the runfiles of the root executable.

<table class="table table-condensed table-bordered table-params">
  <colgroup>
    <col class="col-param" />
    <col class="param-description" />
  </colgroup>
  <thead>
    <tr>
      <th colspan="2">Attributes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>src</code></td>
      <td>
        <p><code>File; required</code></p>
        <p>An Rscript interpreted file, or file with executable permissions.</p>
      </td>
    </tr>
    <tr>
      <td><code>deps</code></td>
      <td>
        <p><code>List of labels; optional</code></p>
        <p>Dependencies of type <code>r_binary</code>, <code>r_pkg</code>,
           or <code>r_library</code>.</p>
      </td>
    </tr>
    <tr>
      <td><code>data</code></td>
      <td>
        <p><code>List of labels; optional</code></p>
        <p>Files needed by this rule at runtime.</p>
      </td>
    </tr>
    <tr>
      <td><code>env_vars</code></td>
      <td>
        <p><code>Dictionary; optional</code></p>
        <p>Extra environment variables to define before running the binary.</p>
      </td>
    </tr>
    <tr>
      <td><code>tools</code></td>
      <td>
        <p><code>List of labels; optional</code></p>
        <p>Executables to be made available to the binary.</p>
      </td>
    </tr>
    <tr>
      <td><code>rscript_args</code></td>
      <td>
        <p><code>List of strings; optional</code></p>
        <p>If src file does not have executable permissions, arguments for the
           Rscript interpreter. We recommend using the shebang line and giving
           your script execute permissions instead of using this.</p>
      </td>
    </tr>
    <tr>
      <td><code>script_args</code></td>
      <td>
        <p><code>List of strings; optional</code></p>
        <p>A list of arguments to pass to the src script.</p>
      </td>
    </tr>
    <tr>
      <td><code>stamp</code></td>
      <td>
        <p><code>Bool; default False</code></p>
        <p>Include the stable status file in the runfiles of the binary.
           The volatile status file is always included.</p>
      </td>
    </tr>
  </tbody>
</table>

<a name="r_test"></a>
## r_test

```python
r_test(name, src, deps, data, env_vars, tools, rscript_args, script_args, stamp)
```

This is identical to [r_binary](#r_binary) but is run as a test.

<a name="r_markdown"></a>
## r_markdown

```python
r_markdown(name, src, deps, data, env_vars, tools, rscript_args, script_args, stamp,
render_function="rmarkdown::render", input_argument="input", output_dir_argument="output_dir",
render_args)
```

This rule renders an R markdown through generating a stub to call the render
function. The render function and the argument names for the function are
default set for `rmarkdown::render` but can be customized. Note that
`render_args` will need to be quoted appropriately if set. This rule can be
used wherever an [r_binary](#r_binary) rule can be used.

If arguments are given on the command line when running the target, flags of
the form --arg=value are passed as keyword arguments to the render
function. The values can be arbitrary R expressions, and strings will need to
be quoted. The last argument without the prefix `--` will be the output
directory, else the output directory will be the default output
directory of the render function, typically the same directory as the input
file.

<a name="r_toolchain"></a>
## r_toolchain

```python
r_toolchain(r, rscript, version, args, makevars_site, env_vars, tools, files, system_state_file)
```

Toolchain to specify the tools and environment for performing build actions.
Also see [r_register_toolchains](#r_register_toolchains) for how
to configure the default registered toolchains.

<table class="table table-condensed table-bordered table-params">
  <colgroup>
    <col class="col-param" />
    <col class="param-description" />
  </colgroup>
  <thead>
    <tr>
      <th colspan="2">Attributes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>r</code></td>
      <td>
        <p><code>String, default R</code></p>
        <p>Path to R.</p>
      </td>
    </tr>
    <tr>
      <td><code>rscript</code></td>
      <td>
        <p><code>String, default Rscript</code></p>
        <p>Path to Rscript.</p>
      </td>
    </tr>
    <tr>
      <td><code>version</code></td>
      <td>
        <p><code>String; optional</code></p>
        <p>If provided, ensure version of R matches this string in x.y form.</p>
      </td>
    </tr>
    <tr>
      <td><code>args</code></td>
      <td>
        <p><code>List of strings; default ["--no-save", "--no-site-file", "--no-environ"]</code></p>
        <p>Arguments to R and Rscript, in addition to `--slave --no-restore --no-init-file`.</p>
      </td>
    </tr>
    <tr>
      <td><code>makevars_site</code></td>
      <td>
        <p><code>Label; optional</code></p>
        <p>Site-wide Makevars file.</p>
      </td>
    </tr>
    <tr>
      <td><code>env_vars</code></td>
      <td>
        <p><code>Dictionary; optional</code></p>
        <p>Environment variables for BUILD actions.</p>
      </td>
    </tr>
    <tr>
      <td><code>tools</code></td>
      <td>
        <p><code>List of labels; optional</code></p>
        <p>Additional tools to make available in PATH.</p>
      </td>
    </tr>
    <tr>
      <td><code>files</code></td>
      <td>
        <p><code>List of labels; optional</code></p>
        <p>Additional files available to the BUILD actions.</p>
      </td>
    </tr>
    <tr>
      <td><code>system_state_file</code></td>
      <td>
        <p><code>Label; optional</code></p>
        <p>A file that captures your system state. Use it to rebuild all R packages whenever the
           contents of this file change. This is ideally generated by a repository_rule with
           `configure = True`, so that a call to `bazel sync --configure` resets this file.</p>
      </td>
    </tr>
  </tbody>
</table>


# Repository Rules

<a name="r_repository"></a>
## r_repository

```python
r_repository(urls, strip_prefix, type, sha256, build_file)
```

Repository rule in place of `new_http_archive` that can run razel to generate
the BUILD file automatically. See section on
[external packages](#external-packages) and [Razel scripts][scripts].

<table class="table table-condensed table-bordered table-params">
  <colgroup>
    <col class="col-param" />
    <col class="param-description" />
  </colgroup>
  <thead>
    <tr>
      <th colspan="2">Attributes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>urls</code></td>
      <td>
        <p><code>List of strings; required</code></p>
        <p>URLs from which the package source archive can be fetched.</p>
      </td>
    </tr>
    <tr>
      <td><code>strip_prefix</code></td>
      <td>
        <p><code>String; optional</code></p>
        <p>The prefix to strip from all file paths in the archive.</p>
      </td>
    </tr>
    <tr>
      <td><code>type</code></td>
      <td>
        <p><code>String; optional</code></p>
        <p>Type of the archive file (zip, tgz, etc.).</p>
      </td>
    </tr>
    <tr>
      <td><code>sha256</code></td>
      <td>
        <p><code>String; optional</code></p>
        <p>sha256 checksum of the archive to verify.</p>
      </td>
    </tr>
    <tr>
      <td><code>build_file</code></td>
      <td>
        <p><code>File; optional</code></p>
        <p>Optional BUILD file for this repo. If not provided, one will be generated.</p>
      </td>
    </tr>
    <tr>
      <td><code>razel_args</code></td>
      <td>
        <p><code>Dictionary; optional</code></p>
        <p>Other arguments to supply to buildify function in razel.</p>
      </td>
    </tr>
  </tbody>
</table>


<a name="r_repository_list"></a>
## r_repository_list

```python
r_repository_list(package_list, build_file_overrides, remote_repos, other_args)
```

Repository rule that will generate a bzl file containing a macro, to be called
as `r_repositories()`, for `r_repository` definitions for packages in
`package_list` CSV. See section on [external packages](#external-packages).

<table class="table table-condensed table-bordered table-params">
  <colgroup>
    <col class="col-param" />
    <col class="param-description" />
  </colgroup>
  <thead>
    <tr>
      <th colspan="2">Attributes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>package_list</code></td>
      <td>
        <p><code>File; required</code></p>
        <p>CSV containing packages with name, version and sha256; with a header.</p>
      </td>
    </tr>
    <tr>
      <td><code>build_file_overrides</code></td>
      <td>
        <p><code>File; optional</code></p>
        <p>CSV containing package name and BUILD file path; with a header.</p>
      </td>
    </tr>
    <tr>
      <td><code>remote_repos</code></td>
      <td>
        <p><code>Dictionary; optional</code></p>
        <p>Repos to use for fetching the archives.</p>
      </td>
    </tr>
    <tr>
      <td><code>other_args</code></td>
      <td>
        <p><code>Dictionary; optional</code></p>
        <p>Other arguments to supply to generateWorkspaceMacro function in razel.</p>
      </td>
    </tr>
  </tbody>
</table>


<a name="r_rules_dependencies"></a>
## r_rules_dependencies

```python
load("@com_grail_rules_r//R:dependencies.bzl", "r_rules_dependencies")

r_rules_dependencies()
```

Repository rule that provides repository definitions for dependencies of the
BUILD system. One such dependency is the site-wide Makevars file for macOS.


<a name="r_coverage_dependencies"></a>
## r_coverage_dependencies

```python
load("@com_grail_rules_r//R:dependencies.bzl", "r_coverage_dependencies")

r_coverage_dependencies()

load("@r_coverage_deps_bzl//:r_repositories.bzl", coverage_deps = "r_repositories")

coverage_deps()
```

Repository rule that provides repository definitions for dependencies in
computing code coverage for unit tests. Not needed if users already have
a repository definition for the [covr](https://github.com/r-lib/covr) package.


<a name="r_register_toolchains"></a>
## r_register_toolchains

```python
load("@com_grail_rules_r//R:dependencies.bzl", "r_register_toolchains")

r_register_toolchains(r_home, strict, makevars_site, version, args, tools)
```

Repository rule that generates and registers a platform independent toolchain
of type [r_toolchain](#r_toolchain) based on the user's system and
environment. If you want to register your own toolchain for specific platforms,
register them before calling this function in your WORKSPACE file to give them
preference.


**NOTE**: These toolchains read your system state and cache the findings for
future runs. Whenever you install a new R version, or if you want to reset the
toolchain for any reason, run:
```bash
bazel sync --configure
```


<table class="table table-condensed table-bordered table-params">
  <colgroup>
    <col class="col-param" />
    <col class="param-description" />
  </colgroup>
  <thead>
    <tr>
      <th colspan="2">Attributes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>r_home</code></td>
      <td>
        <p><code>String, optional</code></p>
        <p>A path to `R_HOME` (as returned from `R RHOME`). If not specified,
           the rule looks for R and Rscript in `PATH`. The environment variable
           `BAZEL_R_HOME` takes precendence over this value.</p>
      </td>
    </tr>
    <tr>
      <td><code>strict</code></td>
      <td>
        <p><code>Bool; default True</code></p>
        <p>Fail if R is not found on the host system.</p>
      </td>
    </tr>
    <tr>
      <td><code>makevars_site</code></td>
      <td>
        <p><code>Bool; default True</code></p>
        <p>Generate a site-wide Makevars file.</p>
      </td>
    </tr>
    <tr>
      <td><code>version</code></td>
      <td>
        <p><code>String; optional</code></p>
        <p>version attribute value for r_toolchain.</p>
      </td>
    </tr>
    <tr>
      <td><code>args</code></td>
      <td>
        <p><code>List of strings; default ["--no-save", "--no-site-file", "--no-environ"]</code></p>
        <p>args attribute value for r_toolchain.</p>
      </td>
    </tr>
    <tr>
      <td><code>tools</code></td>
      <td>
        <p><code>List of strings; optional</code></p>
        <p>tools attribute value for r_toolchain.</p>
      </td>
    </tr>
  </tbody>
</table>


[r]: https://cran.r-project.org
[exampleA]: tests/exampleA/BUILD
[exampleB]: tests/exampleB/BUILD
[exampleC]: tests/exampleC/BUILD
[scripts]: scripts
[libPaths]: https://stat.ethz.ch/R-manual/R-devel/library/base/html/libPaths.html
[Makevars]: makevars/Makevars.darwin.tpl
[r_library_tar]: R/internal/library.bzl
[docker]: R/container/README.md
