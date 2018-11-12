R Rules for Bazel [![Build Status](https://travis-ci.org/grailbio/rules_r.svg?branch=master)](https://travis-ci.org/grailbio/rules_r)
=================

<div class="toc">
  <h4>Rules</h4>
  <ul>
    <li><a href="#r_pkg">r_pkg</a></li>
    <li><a href="#r_library">r_library</a></li>
    <li><a href="#r_unit_test">r_unit_test</a></li>
    <li><a href="#r_pkg_test">r_pkg_test</a></li>
    <li><a href="#r_binary">r_binary</a></li>
    <li><a href="#r_test">r_test</a></li>
  </ul>
</div>

<div class="toc">
  <h4>Workspace Rules</h4>
  <ul>
    <li><a href="#r_repository">r_repository</a></li>
    <li><a href="#r_repository_list">r_repository_list</a></li>
  </ul>
</div>

<div class="toc">
  <h4>Convenience Macros</h4>
  <ul>
    <li><a href="#r_package">r_package</a></li>
    <li><a href="#r_package_with_test">r_package_with_test</a></li>
  </ul>
</div>

## Overview

These rules are used for building [R][r] packages with Bazel. Although R has an
excellent package management system, there is no continuous build and
integration system for entire R package repositories. An advantage of using
Bazel, over a custom solution of tracking the package dependency graph and
triggering builds accordingly on each commit, is that R packages can be built
and tested as part of one build system in multi-language monorepos.

## Getting started

The following assumes that you are familiar with how to use Bazel in general.

In order to use the rules, you must have bazel 0.10.0 or later and add the
following to your WORKSPACE file:

```python
# Change master to the git tag you want.
http_archive(
    name = "com_grail_rules_r",
    strip_prefix = "rules_r-master",
    urls = ["https://github.com/grailbio/rules_r/archive/master.tar.gz"],
)

load("@com_grail_rules_r//R:dependencies.bzl", "r_rules_dependencies")

r_rules_dependencies()
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

## Configuration

These rules assume that you have R installed on your system (we recommend 3.4.3
or above), and can be located using the `PATH` environment variable.

For each package, you can also specify a different Makevars file that can be
used to have finer control over native code compilation. For macOS, the
[Makevars][Makevars] file used as default helps find `gfortran`. To change the
defaults for your repository, you can provide arguments `makevars_darwin`
and/or `makevars_linux` to `r_rules_dependencies`.

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
Rscript \
  -e 'options("repos"="https://cloud.r-project.org")' \
  -e 'non_base_pkgs <- installed.packages(priority=c("recommended", "NA"))[, "Package"]' \
  -e 'remove.packages(non_base_pkgs, lib=.Library)'

# If not set up already, create the directory for R_LIBS_USER.
Rscript \
  -e 'dir.create(Sys.getenv("R_LIBS_USER"), recursive=TRUE, showWarnings=FALSE)'
```

For more details on how R searches different paths for packages, see
[libPaths][libPaths].

## External packages

To depend on external packages from CRAN and other remote repos, you can define the
packages as a CSV with three columns -- Package, Version, and sha256. Then use
`repository_list` rule to define R repositories for each package. For packages
not in a CRAN like repo (e.g. github), you can use `r_repository` rule directly. For
packages on your local system but outside your main repository, you will have to use
`local_repository` with a saved BUILD file. Same for VCS repositories.

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
r_repository_list(
    name = "r_repositories_bzl",
    build_file_overrides = "@myrepo//third-party/R:build_file_overrides.csv",
    package_list = "@myrepo//third-party/R:packages.csv",
    remote_repos = {
        "BioCsoft": "https://bioconductor.org/packages/3.6/bioc",
        "BioCann": "https://bioconductor.org/packages/3.6/data/annotation",
        "BioCexp": "https://bioconductor.org/packages/3.6/data/experiment",
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

NOTE: Periods ('.') in the package names are replaced with underscores ('_')
because bazel does not allow periods in repository names.

## Examples

Some examples are available in the tests directory of this repo.
- See [tests/exampleA][exampleA] for a barebones R package.
- See [tests/exampleB][exampleB] for a barebones R package that depends on another package.
- See [tests/exampleC][exampleC] for an R package that depends on external R packages.

Also see [Razel scripts][scripts] that provide utility functions to generate `BUILD` files
and `WORKSPACE` rules for external packages.

## Docker

See [container support][docker].


<a name="r_pkg"></a>
## r_pkg

```python
r_pkg(srcs, pkg_name, deps, cc_deps, build_args, install_args, config_override, roclets,
      roclets_deps, makevars_user, env_vars, inst_files, tools, build_tools)
```

Rule to install the package and its transitive dependencies in the Bazel
sandbox, so it can be depended upon by other package builds.

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
        <p>Additional arguments to supply to R CMD build.</p>
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
      <td><code>makevars_user</code></td>
      <td>
        <p><code>File; default to @com_grail_rules_r_makevars//:Makevars</code></p>
        <p>User level Makevars file.</p>
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
r_unit_test(pkg, suggested_deps)
```

Rule to keep all deps in the sandbox, and run the provided R test scripts.

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
  </tbody>
</table>


<a name="r_pkg_test"></a>
## r_pkg_test

```python
r_pkg_test(pkg, suggested_deps, check_args)
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
        <p>Additional arguments to supply to R CMD check.</p>
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
  </tbody>
</table>


<a name="r_binary"></a>
## r_binary

```python
r_binary(name, srcs, deps, data, env_vars, tools, rscript_args)
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
        <p><code>String; optional</code></p>
        <p>If src file does not have executable permissions, arguments for the
           Rscript interpreter. We recommend using the shebang line and giving
           your script execute permissions instead of using this.</p>
      </td>
    </tr>
  </tbody>
</table>

<a name="r_test"></a>
## r_test

```python
r_test(name, srcs, deps, data, env_vars, tools, rscript_args)
```

This is idential to <a href="#r_binary">r_binary</a> but is run as a test.


<a name="r_repository"></a>
## r_repository

```python
r_repository(urls, strip_prefix, type, sha256, build_file)
```

Repository rule in place of `new_http_archive` that can run razel to generate
the BUILD file automatically.

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
`package_list` CSV.

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


<a name="r_package"></a>
## r_package

```python
r_package(pkg_name, pkg_srcs, pkg_deps, pkg_suggested_deps=[])
```

Convenience macro to generate the `r_pkg` and `r_library` targets.


<a name="r_package_with_test"></a>
## r_package_with_test

```python
r_package_with_test(pkg_name, pkg_srcs, pkg_deps, pkg_suggested_deps=[], test_timeout="short")
```

Convenience macro to generate the `r_pkg`, `r_library`,
`r_unit_test`, and `r_pkg_test` targets.


Contributing
------------

Contributions are most welcome. Please submit a pull request giving the owners
of this github repo access to your branch for minor style related edits, etc.

Known Issues
------------

Please check open issues at the github repo.

We have tested only on macOS and Ubuntu (VM and Docker).

[r]: https://cran.r-project.org
[exampleA]: tests/exampleA/BUILD
[exampleB]: tests/exampleB/BUILD
[exampleC]: tests/exampleC/BUILD
[scripts]: scripts
[libPaths]: https://stat.ethz.ch/R-manual/R-devel/library/base/html/libPaths.html
[Makevars]: makevars/Makevars.darwin.tpl
[r_library_tar]: R/internal/library.bzl
[docker]: R/container/README.md
