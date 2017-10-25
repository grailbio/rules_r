R Rules for Bazel [![Build Status](https://travis-ci.org/grailbio/rules_r.svg?branch=master)](https://travis-ci.org/grailbio/rules_r)
=================

<div class="toc">
  <h2>Rules</h2>
  <ul>
    <li><a href="#r_pkg">r_pkg</a></li>
    <li><a href="#r_library">r_library</a></li>
    <li><a href="#r_unit_test">r_unit_test</a></li>
    <li><a href="#r_pkg_test">r_pkg_test</a></li>
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

In order to use the rules, you must have bazel 0.5.3 or later and add the
following to your WORKSPACE file:

```python
http_archive(
    name = "com_grail_rules_r",
    strip_prefix = "rules_r-0.3.1",
    urls = ["https://github.com/grailbio/rules_r/archive/0.3.1.tar.gz"],
)
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

These rules assume that you have R installed on your system and can be located
using the `PATH` environment variable. They also assume that packages with
priority `recommended` are in the default R library (given by `.Library`
variable in R).

For each package, you can also specify a different Makevars file that can be
used to have finer control over native code compilation. For macOS, the
[Makevars][Makevars] file used as default helps find `gfortran`.

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
  -e 'pkgs <- available.packages()' \
  -e 'install.packages(pkgs[which(pkgs[, "Priority"] == "recommended"), "Package"], lib=.Library)' \
  -e 'remove.packages(installed.packages(priority="NA")[, "Package"], lib=.Library)'

# If not set up already, fix a directory for R_LIBS_USER.
echo 'R_LIBS_USER="/opt/r-libs/"' >> ~/.Renviron
```

For more details on how R searches different paths for packages, see
[libPaths][libPaths].

## Examples

Some examples are available in the tests directory of this repo.
- See [tests/exampleA][exampleA] for a barebones R package.
- See [tests/exampleB][exampleB] for a barebones R package that depends on another package.
- See [tests/exampleC][exampleC] for an R package that depends on external R packages.

Also see [Razel scripts][scripts] that provide utility functions to generate `BUILD` files
and `WORKSPACE` rules for external packages.

## Docker

You can also create Docker images of R packages using Bazel.

In your `WORKSPACE` file, load the Docker rules and specify the base R image.

```python
# Change to the version of these rules you want and use sha256.
http_archive(
    name = "io_bazel_rules_docker",
    strip_prefix = "rules_docker-v0.3.0",
    urls = ["https://github.com/bazelbuild/rules_docker/archive/v0.3.0.tar.gz"],
)

load(
    "@io_bazel_rules_docker//container:container.bzl",
    "container_pull",
    container_repositories = "repositories",
)

container_repositories()

container_pull(
    name = "r_base",
    registry = "index.docker.io",
    repository = "rocker/r-base",
    tag = "latest",
)
```

And then, in a `BUILD` file, define your library of R packages and install them
in a Docker image. Dependencies are installed implicitly.

```python
load("@com_grail_rules_r//R:defs.bzl", "r_library")

r_library(
    name = "my_r_library",
    pkgs = [
        "//path/to/packageA:r_pkg_target",
        "//path/to/packageB:r_pkg_target",
    ],
    tar_dir = "r-libs",
)  

load("@io_bazel_rules_docker//container:container.bzl", "container_image")

container_image(
    name = "image",
    base = "@r_base//image",
    directory = "/",
    env = {"R_LIBS_USER": "/r-libs"},
    tars = [":my_r_library.tar"],
    repository = "my_repo",
)
```

<a name="r_pkg"></a>
## r_pkg

```python
r_pkg(srcs, pkg_name, deps, install_args, makevars_darwin, makevars_linux,
      shlib_name, lazy_data, post_install_files)
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
      <td><code>install_args</code></td>
      <td>
        <p><code>String; optional</code></p>
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
      <td><code>makevars_darwin</code></td>
      <td>
        <p><code>File; default to //R:Makevars.darwin.generated</code></p>
        <p>Makevars file to use for macOS overrides.</p>
      </td>
    </tr>
    <tr>
      <td><code>makevars_linux</code></td>
      <td>
        <p><code>File; default to R/Makevars.linux</code></p>
        <p>Makevars file to use for Linux overrides.</p>
      </td>
    </tr>
    <tr>
      <td><code>shlib_name</code></td>
      <td>
        <p><code>String; optional</code></p>
        <p>Shared library name, if different from package name.</p>
      </td>
    </tr>
    <tr>
      <td><code>lazy_data</code></td>
      <td>
        <p><code>Bool; default to False</code></p>
        <p>Set to True if the package uses the LazyData feature.</p>
      </td>
    </tr>
    <tr>
      <td><code>post_install_files</code></td>
      <td>
        <p><code>List of strings; optional</code></p>
        <p>Additional files generated as part of the package build and installed with the package.</p>
      </td>
    </tr>
    <tr>
      <td><code>environment_vars</code></td>
      <td>
        <p><code>Dictionary; optional</code></p>
        <p>Extra environment variables to define for building the package.</p>
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

This rule also creates an invisible {name}.tar target which outputs the R
library as a tar file; mainly for use with the Docker rules.

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
    <tr>
      <td><code>tar_dir</code></td>
      <td>
        <p><code>String; default "."</code></p>
        <p>The root directory in the tar file under which the R library will be
        copied.</p>
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
  </tbody>
</table>


<a name="r_pkg_test"></a>
## r_pkg_test

```python
r_pkg_test(pkg, suggested_deps, build_args, check_args)
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
      <td><code>build_args</code></td>
      <td>
        <p><code>String; default "--no-build-vignettes --no-manual"</code></p>
        <p>Additional arguments to supply to R CMD build.</p>
      </td>
    </tr>
    <tr>
      <td><code>check_args</code></td>
      <td>
        <p><code>String; default "--no-build-vignettes --no-manual"</code></p>
        <p>Additional arguments to supply to R CMD check.</p>
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
[Makevars]: R/Makevars.darwin.tpl
