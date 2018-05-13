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
"""This module defines the WORKSPACE dependencies for the toolchain system."""

load(
    "@com_grail_rules_r//R/toolchains:defs.bzl",
    _local_r_toolchain = "local_r_toolchain",
)

def default_r_toolchain(version = None, local_r_home = None, **kwargs):
    if version == "local":
        _local_r_toolchain(name = "default_r_toolchain", r_home = local_r_home, **kwargs)
    elif version.endswith("_local"):
        _local_r_toolchain(
            name = "default_r_toolchain",
            version = version[:len(version) - len("_local")],
            **kwargs
        )
    else:
        fail("unsupported R version: '%s'" % version)

    native.register_toolchains("@default_r_toolchain//:toolchain")
