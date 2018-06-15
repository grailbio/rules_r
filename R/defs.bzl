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

"""R package build, test and install Bazel rules.

r_pkg will build the package and its dependencies and install them in
Bazel's sandbox.

r_unit_test will install all the dependencies of the package in Bazel's
sandbox and generate a script to run the test scripts from the package.

r_pkg_test will install all the dependencies of the package in Bazel's
sandbox and generate a script to run R CMD CHECK on the package.

r_library will install all the listed packages in Bazel's sandbox, and
generate a script to install the packages on the user's machine.
Additionally, a target '%{name}.tar' will be generated on demand and
will contain the root of an R library containing all the listed
packages.

r_binary will install all the dependencies of the executable in Bazel's
sandbox and generate a script to run the executable.

r_test is similar to r_binary, but acts as a test.
"""

load("@com_grail_rules_r//R/internal:build.bzl", "r_binary_pkg", "r_pkg")
load("@com_grail_rules_r//R/internal:library.bzl", "r_library", "r_library_tar")
load("@com_grail_rules_r//R/internal:tests.bzl", "r_pkg_test", "r_unit_test")
load("@com_grail_rules_r//R/internal:binary.bzl", "r_binary", "r_test")

def r_package(pkg_name, pkg_srcs, pkg_deps, pkg_suggested_deps = []):
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

def r_package_with_test(pkg_name, pkg_srcs, pkg_deps, pkg_suggested_deps = [], test_timeout = "short"):
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
