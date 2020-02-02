#!/bin/bash
set -euo pipefail

# Check version
if [[ "${REQUIRED_VERSION:-}" ]]; then
  r_version="$("${R:-"R"}" --slave --vanilla \
    -e 'v <- getRversion()' \
    -e 'cat(v$major, v$minor, sep=".")')"
  if [[ "${REQUIRED_VERSION}" != "${r_version}" ]]; then
    >&2 printf "Required R version is %s; you have %s\\n" "${REQUIRED_VERSION}" "${r_version}"
    exit 1
  fi
fi

# Redirect stdout to provided argument, if any.
if (( $# == 1 )); then
  exec > "${1}"
fi

# Version
printf "=== R version information ===\\n"
"${R:-"R"}" --slave --vanilla --version

# Config
printf "\\n=== R configuration ===\\n"
"${R:-"R"}" CMD config --all --no-user-files "${SITE_FILES_FLAG:-"--no-site-files"}"

# Environment
printf "\\n=== R environment ===\\n"
# TODO: Important variables are defined in
# https://stat.ethz.ch/R-manual/R-devel/library/base/html/EnvVar.html
# But in build actions, bazel will mask most of the ones not coming from R, so we can ignore those.
# shellcheck disable=SC2086
"${RSCRIPT:-"Rscript"}" --no-init-file ${ARGS:-} -e 'Sys.getenv()' | grep "^R_" | grep -v "^R_SESSION_TMPDIR"
