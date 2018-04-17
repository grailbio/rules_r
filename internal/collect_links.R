#!/usr/bin/env Rscript
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

# This script collects the given src files and directories into a destination
# directory by creating relative path symlinks to all the files recursively.

# NOTE: symlinks do not work across packages, so this program is not used.
# https://groups.google.com/forum/#!msg/bazel-discuss/aTMlHOe5R60/lxSVwfsRCAAJ

longestVectorPrefix <- function(a, b) {
  min_len <- min(length(a), length(b))
  if (min_len == 0) {
    return("")
  }

  diffs <- which(a[1:min_len] != b[1:min_len])
  if (length(diffs) == 0) {
    return(min_len)
  } else {
    return(diffs[1]-1)
  }
}

pathComponents <- function(path) {
  strsplit(path, "/")[[1]]
}

relativePath <- function(src, dst) {
  src_components <- pathComponents(normalizePath(dirname(src)))
  dst_components <- pathComponents(normalizePath(dirname(dst)))
  common_components <- longestVectorPrefix(src_components, dst_components)
  do.call(file.path, as.list(c(rep("..", length(dst_components) - common_components),
                               src_components[-seq_len(common_components)], basename(src))))
}

arguments <- commandArgs(trailing = TRUE)
stopifnot(length(arguments) > 0)
dst_root <- arguments[1]
srcs <- arguments[-1]

all_dirs <- list.dirs(path = srcs, full.names = FALSE, recursive = TRUE)
for (d in all_dirs) {
  dir.create(path = file.path(dst_root, d), recursive = TRUE, showWarnings = FALSE)
}

for (src in srcs) {
  src_files <- sort(list.files(path = src, all.files = TRUE, full.names = TRUE, recursive = TRUE,
                               include.dirs = FALSE))
  dst_files <- sort(list.files(path = src, all.files = TRUE, full.names = FALSE, recursive = TRUE,
                               include.dirs = FALSE))
  dst_files <- file.path(dst_root, dst_files)

  for (i in seq_along(src_files)) {
    stopifnot(basename(src_files[i]) == basename(dst_files[i]))
    relative_path <- relativePath(src_files[i], dst_files[i])
    file.symlink(from = relative_path, to = dst_files[i])
  }
}
