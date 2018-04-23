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

def _r_dep(name, version, sha256):
    if "R_" + name not in native.existing_rules():
        _r_repository(
            name = "R_" + name,
            sha256 = sha256,
            strip_prefix = name,
            urls = [
                "https://cloud.r-project.org/src/contrib/" + name + "_" + version + ".tar.gz",
                "https://cloud.r-project.org/src/contrib/Archive/" + name + "/" + name + "_" + version + ".tar.gz",
            ],
        )

_COVR_BUILD_FILE_CONTENT = """
load("@com_grail_rules_r//R:defs.bzl", "r_pkg")

package(default_visibility = ["//visibility:public"])

r_pkg(
    name = "covr",
    srcs = glob(
        ["**"],
        exclude = [],
    ),
    deps = [
        "@R_crayon//:crayon",
        "@R_jsonlite//:jsonlite",
        "@R_rex//:rex",
        "@R_withr//:withr",
    ],
)
"""

def r_coverage_dependencies():
    if "R_covr" not in native.existing_rules():
        # We patch covr by removing its dependency on httr.  httr is only used when uploading
        # coverage reports to third-party services, and not in our case, and is problematic
        # as a dependency as it drags in openssl.
        _http_archive(
            name = "R_covr",
            build_file_content = _COVR_BUILD_FILE_CONTENT,
            patch_cmds = ["pwd && ls && sed '/httr/d' DESCRIPTION > tmp && mv tmp DESCRIPTION"],
            strip_prefix = "covr-749652849c1379719e40121103d3655d0796e676",
            urls = [
                "https://github.com/r-lib/covr/archive/749652849c1379719e40121103d3655d0796e676.tar.gz"
            ],
            sha256 = "4a798d3b13e4729070a8f58b77e5f2e5298a0f58d11ab83c6e45f4c6a4d3f5b4",
        )

    _r_dep("crayon", "1.3.4", "fc6e9bf990e9532c4fcf1a3d2ce22d8cf12d25a95e4779adfa17713ed836fa68")
    _r_dep("withr", "2.1.2", "41366f777d8adb83d0bdbac1392a1ab118b36217ca648d3bb9db763aa7ff4686")
    _r_dep("R6", "2.2.2", "0ef7df0ace1fddf821d329f9d9a5d42296085350ae0d94af62c45bd203c8415e")
    _r_dep("jsonlite", "1.5", "6490371082a387cb1834048ad8cdecacb8b6b6643751b50298c741490c798e02")
    _r_dep("rex", "1.1.2", "bd3c74ceaf335336f5dd04314d0a791f6311e421a2158f321f5aab275f539a2a")
    _r_dep("magrittr", "1.5", "05c45943ada9443134caa0ab24db4a962b629f00b755ccf039a2a2a7b2c92ae8")
    _r_dep("lazyeval", "0.2.1", "83b3a43e94c40fe7977e43eb607be0a3cd64c02800eae4f2774e7866d1e93f61")
