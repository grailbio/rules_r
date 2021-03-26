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

_REPO_NAME_PREFIX = "R_"

def _r_dep(name, version, sha256, urls = None, strip_prefix = None):
    repo_name = _REPO_NAME_PREFIX + name
    if repo_name not in native.existing_rules():
        if urls == None:
            urls = [
                "https://cloud.r-project.org/src/contrib/" + name + "_" + version + ".tar.gz",
                "https://cloud.r-project.org/src/contrib/Archive/" + name + "/" + name + "_" + version + ".tar.gz",
            ]
        if strip_prefix == None:
            strip_prefix = name

        _r_repository(
            name = repo_name,
            razel_args = {
                "repo_name_prefix": _REPO_NAME_PREFIX,
            },
            sha256 = sha256,
            strip_prefix = strip_prefix,
            urls = urls,
        )

def r_coverage_dependencies():
    # Optional function to specify covr R package and dependencies. It is recommended that users
    # include covr in their WORKSPACE themselves as R_covr. This will allow them to use pre-built
    # binary packages, and their own CRAN mirror repositories.

    # Has httr omitted from dependencies because we won't need it.
    _r_dep(
        name = "covr",
        sha256 = "6e9bc4960c16c340278fb44a728680e2b361592f5d864097406ab4a58e39a26a",
        strip_prefix = "covr-9f7dcf60c370b9683433996867faefaf2c3f5772",
        urls = ["https://github.com/siddharthab/covr/archive/9f7dcf60c370b9683433996867faefaf2c3f5772.tar.gz"],
        version = None,
    )

    _r_repository_list(
        name = "r_coverage_deps_bzl",
        other_args = {
            "pkg_type": "both",
        },
        package_list = "@com_grail_rules_r//R/internal:coverage_deps_list.csv",
        remote_repos = {
            # CRAN does not retain binary archives for macOS.
            "CRAN": "https://cran.microsoft.com/snapshot/2021-03-20",
        },
    )
