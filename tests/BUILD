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

load("@com_grail_rules_r//R:defs.bzl", "r_library")

r_library(
    name = "library",
    pkgs = [
        "//exampleC",
        "@R_bitops//:bitops",
    ],
    visibility = [
        "//binary:__pkg__",
        "//container:__pkg__",
    ],
)

load("@com_grail_rules_r//R:defs.bzl", "r_toolchain")

r_toolchain(
    name = "r-toolchain-linux",
    args = [
        "--no-save",
        "--no-site-file",
        "--no-environ",
    ],
    files = [
        "@llvm_toolchain//:compiler_components",
        "@llvm_toolchain//:linker_components",
    ],
    makevars_site = "@llvm_toolchain//:Makevars",
    r = "/usr/bin/R",
    rscript = "/usr/bin/Rscript",
    system_state_file = "@com_grail_rules_r_toolchains//:system_state.txt",
    tools = [
        "@llvm_toolchain//:bin/clang",
        "@llvm_toolchain//:bin/clang++",
        "@llvm_toolchain//:bin/ld",
        "@llvm_toolchain//:bin/ld.lld",
        "@llvm_toolchain//:bin/llvm-cov",
    ],
    visibility = ["//visibility:public"],
)

toolchain(
    name = "toolchain-linux",
    exec_compatible_with = [
        "@bazel_tools//platforms:linux",
        "@bazel_tools//platforms:x86_64",
    ],
    target_compatible_with = [
        "@bazel_tools//platforms:linux",
        "@bazel_tools//platforms:x86_64",
    ],
    toolchain = ":r-toolchain-linux",
    toolchain_type = "@com_grail_rules_r//R:toolchain_type",
    visibility = ["//visibility:public"],
)
