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

source "$(dirname "${BASH_SOURCE[0]}")/build_pkg_common.sh"

mkdir -p "${PKG_LIB_PATH}"

symlink_r_libs "${R_LIBS_DEPS//_EXEC_ROOT_/${EXEC_ROOT}/}"

tar -C "${TMP_SRC}" --strip-components=1 -xzf "${PKG_SRC_ARCHIVE}"

if [[ "${DIRECT_FROM_SOURCE:-false}" ]]; then
  # Copy over some steps from build_pkg_src.sh that are only needed if we are
  # building directly from a source archive, and did not have to run that script
  # first.
  if [[ "${CONFIG_OVERRIDE:-}" ]]; then
    cp "${CONFIG_OVERRIDE}" "${TMP_SRC}/configure"
  fi
  if [[ "${C_SO_FILES:-}" ]]; then
    mkdir -p "${TMP_SRC}/inst/libs"
    for so_file in ${C_SO_FILES}; do
      eval so_file="${so_file}" # Use eval to remove outermost quotes.
      so_file_name="$(basename "${so_file}")"
      cp "${so_file}" "${TMP_SRC}/inst/libs/${so_file_name}"
      if [[ "$(uname)" == "Darwin" ]]; then
        chmod u+w "${TMP_SRC}/inst/libs/${so_file_name}"
        install_name_tool -id "@loader_path/${so_file_name}" "${TMP_SRC}/inst/libs/${so_file_name}"
      fi
    done
  fi
fi

# Install the package to the common temp library.
silent "${R}" CMD INSTALL --built-timestamp='' "${INSTALL_ARGS}" --no-lock --build --library="${TMP_LIB}" --clean "${TMP_SRC}"
rm -rf "${PKG_LIB_PATH:?}/${PKG_NAME}" # Delete empty directories to make way for move.
mv -f "${TMP_LIB}/${PKG_NAME}" "${PKG_LIB_PATH}/"

# Make the tar.gz reproducible by removing mtime and gzip timestamp.
tmp_tar_dir="$(mktemp -d --tmpdir=bazel-out)"
TMP_FILES+=("${tmp_tar_dir}")
tar -C "${tmp_tar_dir}" -xzf "${PKG_NAME}"*gz  # .tgz on macOS and .tar.gz on Linux.
# Reset mtime so that tarball is reproducible.
TZ=UTC find "${tmp_tar_dir}" -exec touch -amt 197001010000 {} \+
# Ask gzip to not store the timestamp.
tar -C "${tmp_tar_dir}" -cf - "${PKG_NAME}" | gzip --no-name -c > "${PKG_BIN_ARCHIVE}"


if "${INSTRUMENTED}"; then
  silent "${RSCRIPT}" "${INSTRUMENT_SCRIPT}" "${PKG_LIB_PATH}" "${PKG_NAME}"
  # Copy .gcno files next to the source files.
  if [[ -d "${TMP_SRC}/src" ]]; then
    rsync "--recursive" "--copy-links" "--no-perms" "--chmod=a+w" "--prune-empty-dirs" \
      "--include=*.gcno" "--include=*/" "--exclude=*" \
      "${TMP_SRC}/src" "$(dirname "${PKG_LIB_PATH}")"
  fi
fi

trap - EXIT
cleanup
