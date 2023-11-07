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

load("@rules_r//R:defs.bzl", "r_library")

r_library(
    name = "library",
    pkgs = [
        "//packages/exampleC",
        "@R_bitops//:bitops",
    ],
    visibility = [
        "//binary:__pkg__",
        "//container:__pkg__",
    ],
)

load("@rules_r//R:defs.bzl", "r_toolchain")

r_toolchain(
    name = "r-toolchain-linux",
    args = [
        "--no-save",
        "--no-site-file",
        "--no-environ",
    ],
    files = select({
        "@bazel_tools//src/conditions:linux_x86_64": [
            "@llvm_toolchain//:compiler-components-x86_64-linux",
            "@llvm_toolchain//:linker-components-x86_64-linux",
        ],
        "//conditions:default": None,
    }),
    makevars_site = "//cran:Makevars.gnu",
    r = "/usr/bin/R",
    rscript = "/usr/bin/Rscript",
    system_state_file = "@rules_r_toolchains//:system_state.txt",
    tools = [
        "@llvm_toolchain_llvm//:bin/clang",
        "@llvm_toolchain_llvm//:bin/clang++",
        "@llvm_toolchain_llvm//:bin/ld.lld",
        "@llvm_toolchain_llvm//:bin/llvm-cov",
    ],
    visibility = ["//visibility:public"],
)

r_toolchain(
    name = "r-toolchain-darwin",
    args = [
        "--no-save",
        "--no-site-file",
        "--no-environ",
    ],
    env_vars = {
        "ZERO_AR_DATE": "1",  # For reproducible builds.
    },
    files = select({
        "@bazel_tools//src/conditions:darwin_x86_64": [
            "@llvm_toolchain//:compiler-components-x86_64-darwin",
            "@llvm_toolchain//:linker-components-x86_64-darwin",
        ],
        "//conditions:default": None,
    }),
    makevars_site = "@rules_r_makevars_darwin",
    system_state_file = "@rules_r_toolchains//:system_state.txt",
    tools = [
        "@llvm_toolchain_llvm//:bin/clang",
        "@llvm_toolchain_llvm//:bin/clang++",
        "@llvm_toolchain_llvm//:bin/llvm-cov",
    ],
    version = "4.1",
    visibility = ["//visibility:public"],
)

# Toolchain to use R from nix packages.
# Also remember to set the rscript path in r_repository_list in your WORKSPACE file.
r_toolchain(
    name = "r-toolchain-nix",
    args = [
        "--no-save",
        "--no-site-file",
        "--no-environ",
    ],
    files = ["@Rnix//:lib"],
    system_state_file = ":empty",
    tags = ["manual"],
    tools = [
        "@Rnix//:bin/R",
        "@Rnix//:bin/Rscript",
    ],
    version = "4.1",
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
    toolchain_type = "@rules_r//R:toolchain_type",
    visibility = ["//visibility:public"],
)

toolchain(
    name = "toolchain-darwin",
    exec_compatible_with = [
        "@bazel_tools//platforms:osx",
        "@bazel_tools//platforms:x86_64",
    ],
    target_compatible_with = [
        "@bazel_tools//platforms:osx",
        "@bazel_tools//platforms:x86_64",
    ],
    toolchain = ":r-toolchain-darwin",
    toolchain_type = "@rules_r//R:toolchain_type",
    visibility = ["//visibility:public"],
)

toolchain(
    name = "toolchain-nix",
    tags = ["manual"],
    toolchain = ":r-toolchain-nix",
    toolchain_type = "@rules_r//R:toolchain_type",
    visibility = ["//visibility:public"],
)

genrule(
    name = "gen_empty",
    outs = ["empty"],
    cmd = "touch $@",
)
