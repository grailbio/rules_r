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
    "@com_grail_rules_r//R:repositories.bzl",
    _r_repository = "r_repository",
    _r_repository_list = "r_repository_list",
)

def r_coverage_dependencies():
    # Optional function to specify covr R package and dependencies. It is recommended that users
    # include covr in their WORKSPACE themselves as R_covr. This will allow them to use pre-built
    # binary packages, and their own CRAN mirror repositories.

    _r_repository_list(
        name = "r_coverage_deps_bzl",
        other_args = {
            "pkg_type": "both",
        },
        package_list = "@com_grail_rules_r//R/internal:coverage_deps_list.csv",
        remote_repos = {
            # CRAN does not retain binary archives for macOS.
            "CRAN": "https://cran.microsoft.com/snapshot/2021-04-01",
        },
    )
