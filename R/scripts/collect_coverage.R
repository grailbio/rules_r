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

# Collect code coverage

# NOTE:
# This might break in the future if we start specifying cc_deps as a dependency
# attribute in instrumented_files. More proper support for coverage in starlark
# rules is in the roadmap --
# https://bazel.build/roadmaps/coverage.html#improve-adding-coverage-support-for-skylark-rules-p2

options(warn=2)

bazel_r_debug <- (Sys.getenv("BAZEL_R_DEBUG") == "true")
bazel_r_verbose <- (Sys.getenv("BAZEL_R_VERBOSE") == "true")
if (bazel_r_debug) {
  bazel_r_verbose <- TRUE
  options(echo = TRUE)
}

stopifnot(requireNamespace("covr"))

test_workspace <- Sys.getenv("TEST_WORKSPACE")
coverage_dir <- Sys.getenv("COVERAGE_DIR")

############
# R coverage

coverage <- local({
  trace_files <- list.files(path = coverage_dir, pattern = "^covr_trace_[^/]+$", full.names = TRUE)
  if (length(trace_files) == 0) {
    return(NULL)
  }
  covr:::merge_coverage(trace_files)
})

############
# Native code coverage

# Copy the gcno files and their corresponding source code to locations within
# COVERAGE_DIR.
# e.g. COVERAGE_DIR/workspace_path_to_package/src/init.gcno, etc.
local({
  copy_gcno <- function(gcno) {
    to_dir <- file.path(coverage_dir, dirname(gcno))
    if (!dir.exists(to_dir)) {
      dir.create(to_dir, recursive = TRUE)
    }
    filename_sans_ext <- tools::file_path_sans_ext(basename(gcno))
    filegroup_pattern <- sprintf("^%s\\.?[^.]*$", filename_sans_ext)
    gcno_filegroup <- list.files(dirname(gcno),
                                 pattern = filegroup_pattern,
                                 full.names = TRUE)
    for (f in gcno_filegroup) {
      file.copy(from = f, to = file.path(coverage_dir, f))
    }
  }
  gcno_files <- list.files(pattern = "\\.gcno$", all.files = TRUE, recursive = TRUE)
  invisible(Vectorize(copy_gcno)(gcno_files))
})

if (bazel_r_debug) {
  print("GCOV_PREFIX_STRIP and gcno files paths:")
  print(Sys.getenv("GCOV_PREFIX_STRIP"))
  print(list.files(coverage_dir, "\\.gcno$", recursive = TRUE))
  print(list.files(coverage_dir, "\\.gcda$", recursive = TRUE))
}

# Obtain paths to packages as the compiler was invoked in these directories and so
# gcno files have embedded paths to source files relative to these directories.
pkg_paths <- local({
  lib_paths <- strsplit(Sys.getenv("R_LIBS"), ':')[[1]]
  pkg_libs <- installed.packages(lib.loc=lib_paths)[, "LibPath"]
  pkg_libs <- sub(paste0("^", getwd(), "/"), "", pkg_libs)
  pkg_libs <- sub(paste0("^../", test_workspace, "/"), "", pkg_libs)
  pkg_libs <- Filter(function(x) !startsWith(x, "../"), pkg_libs)  # Filter external packages.

  pkg_names <- names(pkg_libs)
  dirname(pkg_libs)
})

# Fix paths in gcov files to be relative to workspace and not to the compiler directory.
# Returns null if the fixed path is not in the test workspace.
fix_gcov_file <- function(gcov_file, compiler_dir) {
  lns <- readLines(gcov_file)
  source_file <- sub("^.*Source:", "", lns[1])

  if (startsWith(source_file, '/')) {
    return(NULL)
  }

  source_file <- file.path(compiler_dir, source_file)
  lns[1] <- sub("Source:.*", paste0("Source:", source_file), lns[1])
  writeLines(text = lns, con = gcov_file)
  gcov_file
}
vfix_gcov_file <- Vectorize(fix_gcov_file, "gcov_file", USE.NAMES = FALSE)

# Try the given gcov command, returning TRUE or FALSE indicating success.
try_gcov <- function(gcov_path, args) {
  gcov_version_line <- paste(system2(gcov_path, "--version", stdout = TRUE), collapse = " ")
  if (bazel_r_debug) {
    message(paste("gcov version:", gcov_version_line))
    message(paste(c(gcov_path, args), collapse = " "))
  }
  options(warn=1)
  res <- system2(gcov_path, args, env = c("GCOV_EXIT_AT_ERROR=1"), stdout = TRUE, stderr = TRUE)
  options(warn=2)
  if (length(attributes(res)) > 0) {
    writeLines(res, stderr())
    return(FALSE)
  }
  # gcov from LLVM can return a 0 status code when the file formats don't match.
  if (any(grepl("Invalid .gcno File", res))) {
    writeLines(res, stderr())
    return(FALSE)
  }
  if (bazel_r_verbose) {
    writeLines(res, stderr())
  }
  return(TRUE)
}

run_gcov <- function() {
  gcov_path <- Sys.which("gcov")
  llvm_cov_path <- Sys.which("llvm-cov")
  gcov_outputs <- sapply(file.path(pkg_paths, "src"), function(compiler_dir) {
    path <- file.path(coverage_dir, compiler_dir)

    # Collect gcno files from the compiler directory.
    gcov_inputs <- list.files(path, pattern = "\\.gcno$",
                              recursive = TRUE, full.names = TRUE)
    if (length(gcov_inputs) == 0)
      return(list())

    # Switch to the compiler directory to run gcov so all embedded relative paths makes sense.
    orig_dir <- getwd()
    setwd(path)
    res <- FALSE
    if (nchar(gcov_path) > 0) {
      res <- try_gcov(gcov_path, args = c(gcov_inputs, "-p"))
    }
    if (!isTRUE(res) && nchar(llvm_cov_path) > 0) {
      res <- try_gcov(llvm_cov_path, args = c("gcov", gcov_inputs, "-p"))
    }
    if (!isTRUE(res)) {
      stop("unable to process .gcno files")
    }
    setwd(orig_dir)

    # Collect gcov files and fix the paths they represent.
    pkg_outputs <- list.files(path, pattern = "\\.gcov$",
                              recursive = TRUE, full.names = TRUE)
    Filter(Negate(is.null), vfix_gcov_file(pkg_outputs, compiler_dir))
  })
  gcov_outputs <- unlist(gcov_outputs, recursive = FALSE)

  structure(
    as.list(unlist(recursive = FALSE,
      lapply(gcov_outputs, covr:::parse_gcov))),
    class = "coverage")
}
res <- run_gcov()

############
# Report

output_file <- Sys.getenv("COVERAGE_OUTPUT_FILE", NA)
local({
  coverage <- structure(c(coverage, res),
                        class = "coverage",
                        package = NULL,
                        relative = FALSE)

  # Exclude both RcppExports to avoid redundant coverage information, and follow ignore directives.
  line_exclusions <- c("src/RcppExports.cpp", "R/RcppExports.R", covr:::parse_covr_ignore())
  coverage <- covr:::exclude(coverage, line_exclusions = line_exclusions)

  covr:::to_cobertura(coverage, filename = output_file)
})

############
# Standardize XML (paths, stamps, order of files)

local({
  test_workspace_pattern <- paste0("^external/", test_workspace, "/")
  execroot_pattern <- paste0("^.*", file.path("execroot", Sys.getenv("TEST_WORKSPACE"), ""))
  tmp_src_path <- normalizePath("/tmp/bazel/R/src", mustWork = FALSE)
  fix_filename <- function(f) {
    if (startsWith(f, tmp_src_path)) {
      f <- sub(paste0(tmp_src_path, "/"), "", f)
      f <- sub(test_workspace_pattern, "", f)
      return(f)
    }
    # C++ file paths will be their absolute paths anyway.
    f <- sub(execroot_pattern, "", f)
    f <- sub("^bazel-out/[^/]+/bin/", "", f)
    f <- sub(test_workspace_pattern, "", f)
    return(f)
  }

  coverage_xml <- xml2::read_xml(output_file)
  sources_xml <- xml2::xml_child(coverage_xml, "sources")
  packages_xml <- xml2::xml_child(coverage_xml, "packages")

  # Remove timestamp
  xml2::xml_attr(coverage_xml, "timestamp") <- "1960-01-01 00:00:00"

  # Fix filenames.
  fixed_filenames <- sapply(xml2::xml_children(sources_xml), function(s) {
    f <- fix_filename(xml2::xml_text(s))
    xml2::xml_text(s) <- f
    f
  })
  file_order <- order(fixed_filenames)

  classes <- xml2::xml_child(xml2::xml_child(packages_xml, "package"), "classes")
  for (cl in xml2::xml_children(classes)) {
    xml2::xml_attr(cl, "filename") <- fix_filename(xml2::xml_attr(cl, "filename"))
  }

  # Sort filenames.
  sorted_sources <- xml2::xml_add_sibling(sources_xml, sources_xml)
  sorted_classes <- xml2::xml_add_sibling(classes, classes)
  for (i in seq_along(file_order)) {
    xml2::xml_replace(xml2::xml_child(sorted_sources, i),
                      xml2::xml_child(sources_xml, file_order[i]))
    xml2::xml_replace(xml2::xml_child(sorted_classes, i),
                      xml2::xml_child(classes, file_order[i]))
  }
  xml2::xml_remove(sources_xml)
  xml2::xml_remove(classes)

  xml2::write_xml(coverage_xml, output_file)
})
