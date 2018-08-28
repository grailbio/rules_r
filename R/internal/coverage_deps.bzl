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
)
load(
    "@bazel_tools//tools/build_defs/repo:http.bzl",
    _http_archive = "http_archive",
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

    _r_dep("R6", "2.2.2", "0ef7df0ace1fddf821d329f9d9a5d42296085350ae0d94af62c45bd203c8415e")
    _r_dep("Rcpp", "0.12.18", "fcecd01e53cfcbcf58dec19842b7235a917b8d98988e4003cc090478c5bbd300")
    _r_dep("crayon", "1.3.4", "fc6e9bf990e9532c4fcf1a3d2ce22d8cf12d25a95e4779adfa17713ed836fa68")
    _r_dep("digest", "0.6.15", "882e74bb4f0722260bd912fd7f8a0fcefcf44c558f43ac8a03d63e53d25444c5")
    _r_dep("jsonlite", "1.5", "6490371082a387cb1834048ad8cdecacb8b6b6643751b50298c741490c798e02")
    _r_dep("lazyeval", "0.2.1", "83b3a43e94c40fe7977e43eb607be0a3cd64c02800eae4f2774e7866d1e93f61")
    _r_dep("magrittr", "1.5", "05c45943ada9443134caa0ab24db4a962b629f00b755ccf039a2a2a7b2c92ae8")
    _r_dep("rex", "1.1.2", "bd3c74ceaf335336f5dd04314d0a791f6311e421a2158f321f5aab275f539a2a")
    _r_dep("withr", "2.1.2", "41366f777d8adb83d0bdbac1392a1ab118b36217ca648d3bb9db763aa7ff4686")
    _r_dep("xml2", "1.2.0", "0a7a916fe9c5da9ac45aeb4c6b6b25d33c07652d422b9f2bb570f2e8f4ac9494")
