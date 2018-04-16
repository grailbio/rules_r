#!/bin/bash
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

set -euo pipefail

bin_archive=$1
pkg_lib_path=$2
pkg_name=$3
out=$4

# TODO: Make this fail if there is a non-empty diff, when this passes for all packages.
diff \
  <(tar -tf "${bin_archive}" | grep -v '/$' | sort) \
  <(cd "${pkg_lib_path}" && find "${pkg_name}" -not -type d | sort) \
  >"${out}" \
  || true
