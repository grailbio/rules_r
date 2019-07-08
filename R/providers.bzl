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

RPackage = provider(
    doc = "Build information about an R package dependency",
    fields = {
        "pkg_name": "Name of the package",
        "pkg_lib_dir": "Directory where this package is installed",
        "src_files": "All source files in this package",
        "test_files": "All test files in this package",
        "src_archive": "Source archive of this package",
        "bin_archive": "Binary archive of this package",
        "pkg_deps": "Direct deps of this package",
        "transitive_pkg_deps": "depset of all dependencies of this target",
        "transitive_tools": "depset of all system tools",
        "build_tools": "tools needed to build this package",
        "makevars": "User level makevars file for native code compilation",
        "cc_deps": "cc_deps struct for the package",
        "pkg_gcno_dir": "Directory containing instrumented gcno files",
        "external_repo": "Boolean indicating if the package is from an external repo",
    },
)

RLibrary = provider(
    doc = "Build information about an R library",
    fields = {
        "pkgs": "List of directly specified packages in this library",
        "container_file_map": "Files for each container layer type",
    },
)

RBinary = provider(
    doc = "Build information about an R binary",
    fields = {
        "srcs": "depset of src files for this and other binary dependencies",
        "exe": "depset of exe wrapper files for this and other binary dependencies",
        "tools": "depset of system tools for this and other binary dependencies",
        "pkg_deps": "list of direct package dependencies for this and other binary dependencies",
    },
)
