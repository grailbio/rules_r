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

if [[ "${CONFIG_OVERRIDE:-}" ]]; then
  cp "${CONFIG_OVERRIDE}" "${PKG_SRC_DIR}/configure"
fi

copy_inst_files() {
  local IFS=","
  for copy_pair in ${INST_FILES_MAP}; do
    IFS=":" read -r dst src <<< "${copy_pair}"
    mkdir -p "$(dirname "${dst}")"
    cp -f "${src}" "${dst}"
  done
}
copy_inst_files

# Copy files to the tmp location.
TMP_SRC_TAR="${TMP_SRC}.tar.gz"
copy_cmd=(
  rsync "--recursive" "--copy-links" "--no-perms" "--chmod=u+w" "--executability" "--specials")
if [[ "${PKG_SRC_DIR}" == "." ]]; then
  # Need to exclude special directories in the execroot.
  copy_cmd+=("--exclude" "bazel-out" "--exclude" "external" "--delete-excluded")
fi
copy_cmd+=("${EXEC_ROOT}/${PKG_SRC_DIR}/" "${TMP_SRC}")
"${copy_cmd[@]}"
TMP_FILES+=("${TMP_SRC}")

# Hack: copy the .so files inside the package source so that they are installed
# (in bazel's sandbox as well as on user's system) along with package libs, and
# use relative rpath (Linux) or change the install name to use @loader_path
# (macOS).
if [[ "${C_SO_FILES}" ]]; then
  C_SO_LD_FLAGS=""
  mkdir -p "${TMP_SRC}/inst/libs"
  for so_file in ${C_SO_FILES}; do
    eval so_file="${so_file}" # Use eval to remove outermost quotes.
    so_file_name="$(basename "${so_file}")"
    cp "${so_file}" "${TMP_SRC}/inst/libs/${so_file_name}"
    if [[ "$(uname)" == "Darwin" ]]; then
      C_SO_LD_FLAGS+="../inst/libs/${so_file_name} "
      chmod u+w "${TMP_SRC}/inst/libs/${so_file_name}"
      install_name_tool -id "@loader_path/${so_file_name}" "${TMP_SRC}/inst/libs/${so_file_name}"
    elif [[ "$(uname)" == "Linux" ]]; then
      C_SO_LD_FLAGS+="-L../inst/libs -l:${so_file_name} "
    fi
  done
  if [[ "$(uname)" == "Linux" ]]; then
    #shellcheck disable=SC2016
    C_SO_LD_FLAGS+="-Wl,-rpath,"\''$$ORIGIN'\'" "
  fi
fi

if [[ "${ROCLETS}" ]]; then
  symlink_r_libs "${R_LIBS_ROCLETS//_EXEC_ROOT_/${EXEC_ROOT}/}"
  silent "${RSCRIPT}" - <<EOF
bazel_libs <- .libPaths()
bazel_libs <- bazel_libs[! bazel_libs %in% c(.Library, .Library.site)]
if ("devtools" %in% installed.packages(bazel_libs)[, "Package"]) {
  devtools::document(pkg='${TMP_SRC}', roclets=c(${ROCLETS}))
} else {
  roxygen2::roxygenize(package.dir='${TMP_SRC}', roclets=c(${ROCLETS}))
}
EOF
fi

symlink_r_libs "${R_LIBS_DEPS//_EXEC_ROOT_/${EXEC_ROOT}/}"

silent "${R}" CMD build "${BUILD_ARGS}" "${TMP_SRC}"
mv "${PKG_NAME}"*.tar.gz "${TMP_SRC_TAR}"
TMP_FILES+=("${TMP_SRC_TAR}")

# Unzip the built package as the new source, remove any non-reproducible
# artifacts, perform any additional cleanups, and repackage.
rm -r "${TMP_SRC}"
mkdir -p "${TMP_SRC}"
tar -C "${TMP_SRC}" --strip-components=1 -xzf "${TMP_SRC_TAR}"
sed -i'.bak' -e "/^Packaged: /d" "${TMP_SRC}/DESCRIPTION"
rm "${TMP_SRC}/DESCRIPTION.bak"
if "${INSTRUMENTED}"; then
  # .gcno and .gcda files are not cleaned up after R CMD build.
  find "${TMP_SRC}" \( -name '*.gcda' -or -name '*.gcno' \) -delete
fi
# Repackage tar with package name as root, and without mtime.
(
  cd "${TMP_SRC}"
  # Reset mtime for all files and directories.
  # R's help DB is specially sensitive to timestamps of .Rd files in man/.
  TZ=UTC find "${TMP_SRC}" -exec touch -amt 197001010000 {} \+
  if [[ "$(tar --version)" == "bsdtar"* ]]; then
    flags=("-s" "@^@${PKG_NAME}/@")
  else
    flags=("--transform" "s@^@${PKG_NAME}/@")
  fi
  # Ask gzip to not store the timestamp.
  tar "${flags[@]}" -cf - -- * | gzip --no-name -c > "${TMP_SRC_TAR}"
)

# Done building the package source archive.
mv "${TMP_SRC_TAR}" "${PKG_SRC_ARCHIVE}"

trap - EXIT
cleanup
