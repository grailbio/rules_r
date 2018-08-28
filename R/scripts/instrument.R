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

# Instrument the package by adding a hook to trace its function calls, and
# adding a finalizer to save the trace to a location determined on package
# load using an environment variable. The logic here imitates covr:::add_hooks
# to some extent.

# NOTE: coverage trace counters are part of the covr namespace. We set a
# finalizer to save the trace counters on session exit, with a reasonable
# assumption that the covr package, once loaded, will not be manually
# unloaded.

options(warn=2)

args_list <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args_list) == 3)

lib <- args_list[[1]]
pkg_name <- args_list[[2]]
pkg_src <- args_list[[3]]

# Skip instrumented execution if covr is not available.
# Needed for using instrumented packages without covr as a runtime dependency.
check_line <- "if (inherits(try(loadNamespace(\"covr\"), silent = TRUE), \"environment\")) {"

# The load script is an R program that is used to load the package.
# Similar to 'add_hooks' function from covr, we modify this loader to
# instrument the package at load time.
pkg_path <- file.path(lib, pkg_name)
load_script <- file.path(pkg_path, "R", pkg_name)
loader_lines <- readLines(load_script)

# Add package load hook to insert tracers in package functions.
hook_lines <-
  c(paste0("    ", check_line),
    "        cat(\"Instrumented R package\", info$pkgname, \"\\n\")",
    "        setHook(packageEvent(pkg, \"onLoad\"), function(...) covr:::trace_environment(ns, clear = FALSE))",
    "    }")
loader_lines <- append(loader_lines, hook_lines, length(loader_lines) - 1L)

# Setup covr to save its trace counters on exit to the COVERAGE_DIR directory
# set up by bazel when collecting coverage.  In the rare case that somebody
# decides to use the instrumented package directly outside of bazel, substitute
# COVERAGE_DIR with /tmp.
# Also fix mcexit to save counters for any forked R sessions from the 'parallel' package.
trace_lines <-
  c(check_line,
    "    covr:::save_trace_on_exit(Sys.getenv(\"COVERAGE_DIR\", \"/tmp\"))",
    "    covr:::fix_mcexit(Sys.getenv(\"COVERAGE_DIR\", \"/tmp\"))",
    "}")
loader_lines <- c(loader_lines, trace_lines)

writeLines(text = loader_lines, con = load_script)

# We copy the src files along with the .gcno, etc. files to their corresponding
# location in bazel-bin.
# TODO: Trim down to only the files we need; make C/C++ files a separate dependency.
from <- file.path(pkg_src, "src")
if (dir.exists(from)) {
  file.copy(from = from, to = dirname(lib), recursive = TRUE, copy.date = TRUE)
}
