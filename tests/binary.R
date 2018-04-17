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

arguments <- commandArgs()
source_file <- substr(arguments[which(sapply(arguments, startsWith, "--file="))[1]],
                      nchar("--file=") + 1, 1e6)
setwd(dirname(source_file))

extra_pkgs <- commandArgs(trailingOnly=TRUE)

stopifnot(all(c("exampleC", "bitops", "R6", extra_pkgs) %in%
              installed.packages(priority=c("recommended", "NA"))[, "Package"]))

stopifnot(file.exists("binary_data.txt"))
