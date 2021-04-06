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

message("Collecting coverage for R tests...")

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

r_coverage <- local({
  trace_files <- list.files(path = coverage_dir, pattern = "^covr_trace_[^/]+$", full.names = TRUE)
  if (bazel_r_debug) {
    print("R coverage trace files:")
    print(trace_files)
  }
  if (length(trace_files) == 0) {
    return(NULL)
  }
  # Merging coverage trace files may need loading the user R packages; which
  # could result in warnings. Let's log them instead of failing.
  options(warn=1)
  res <- covr:::merge_coverage(trace_files)
  options(warn=2)
  return(res)
})

############
# Native code coverage

# Copy the gcda files in coverage_dir to their corresponding
# source directories.
local({
  copy_gcda <- function(coverage_dir, strip_components) {
    files <- list.files(path = coverage_dir, pattern = "\\.gcda$", all.files = TRUE, recursive = TRUE)
    for (from_path in files) {
      to_path <- from_path
      for (i in seq_len(strip_components)) {
        to_path <- sub("[^/]*/", "", to_path)
      }
      to_dir <- dirname(to_path)
      if (!dir.exists(to_dir)) {
        dir.create(to_dir, recursive = TRUE)
      }
      file.copy(from = file.path(coverage_dir, from_path), to = to_path)
    }
  }
  # We already set GCOV_PREFIX_STRIP to be 0 before running the tests, so now
  # we strip components as needed.

  # Files from /tmp/bazel/R/src.
  # Recreate path if it has been deleted since building the packages.  We
  # need the path to actually exist so we can resolve symlinks and find out
  # how many actual components to strip.
  tmp_src_path <- "/tmp/bazel/R/src"
  if (!dir.exists(tmp_src_path)) {
    dir.create(tmp_src_path, recursive = TRUE)
  }
  r_coverage_dir <- file.path(coverage_dir, normalizePath(tmp_src_path))
  copy_gcda(r_coverage_dir, 0)

  # These are compiled in /proc/self/cwd/bazel-out/*/bin in linux, and
  # EXEC_ROOT/TEST_WORKSPACE/bazel-out/*/bin for macOS.
  if (grepl("linux", R.version$os)) {
    prefix <- "proc/self/cwd/bazel-out"
    strip <- 2 # For stripping the components k8-*/bin
  } else if (grepl("darwin", R.version$os)) {
    # Get the path to the sandbox by only retaining current directory path until execroot.
    sandbox_dir <- sub("/execroot.*$", "", normalizePath(getwd()))
    # Go one level up to remove sandbox number.
    prefix <- dirname(sandbox_dir)
    strip <- 6 # [sandbox_number] + execroot + [test_workspace] + bazel-out + darwin-* + bin
  }
  cc_dep_coverage_dir <- file.path(coverage_dir, prefix)
  copy_gcda(cc_dep_coverage_dir, strip)
})

if (bazel_r_debug) {
  message("gcno files paths:")
  print(list.files(pattern = "(\\.gcno$|\\.gcda)", recursive = TRUE))
}

# Obtain paths to packages as the compiler was invoked in these directories and so
# gcno files have embedded paths to source files relative to these directories.
pkg_paths <- local({
  pkgs <- list.files(Sys.getenv("R_LIBS_USER"), full.names = TRUE)
  pkgs <- normalizePath(pkgs) # Resolve symlinks.
  pkg_libs <- dirname(pkgs) # Individual lib directories of packages.
  pkg_paths <- dirname(pkg_libs) # Path to bazel packages.
  # Get paths relative to cwd.
  wd <- paste0(getwd(), "/")
  wd_parent <- paste0(dirname(wd), "/")
  pkg_paths <- sapply(pkg_paths, function(path) {
    if (startsWith(path, wd)) {
      # Package belongs to this workspace; do nothing.
      return(sub(wd, "", path))
    } else if (startsWith(path, wd_parent)) {
      # Package belongs to an external workspace; replace path to external/...
      return(sub(wd_parent, "external/", path))
    } else {
      stop("unrecognized R package path: ", path)
    }
  })
  pkg_names <- basename(pkgs)
  names(pkg_paths) <- pkg_names
  return(pkg_paths)
})

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
  if (any(grepl("Invalid (\\.gcno)|(\\.gcda) File!", res))) {
    writeLines(res, stderr())
    return(FALSE)
  }
  if (bazel_r_verbose) {
    writeLines(res, stderr())
  }
  return(TRUE)
}

# Fix paths in gcov files to be relative to workspace and not to the compiler directory.
# Returns null if the fixed path is not in the test workspace.
parse_gcov_file <- function(gcov_file, compiler_dir) {
  lns <- readLines(gcov_file)
  source_file <- sub("^.*Source:(\\./)?", "", lns[1])

  # Filter any files with absolute paths; these are most likely system headers.
  if (startsWith(source_file, '/')) {
    return(NULL)
  }

  if (compiler_dir != "") {
    source_file <- file.path(compiler_dir, source_file)
    lns[1] <- sub("Source:.*", paste0("Source:", source_file), lns[1])
    writeLines(text = lns, con = gcov_file)
  }

  # Filter unavailable files; these are most likely not instrumented.
  if (!file.exists(source_file)) {
    return(NULL)
  }

  parsed <- covr:::parse_gcov(gcov_file)

  # To revert covr normalized path to relative path in the srcref objects, we
  # have to recreate the srcfile object.
  # TODO: Maybe just maintain a map of path replacements for fixing the final XML
  # instead of fixing the paths here.
  src_file <- srcfilecopy(source_file, readLines(source_file))
  for (i in seq_along(parsed)) {
    attr(parsed[[i]][["srcref"]], "srcfile") <- src_file
  }
  return(parsed)
}
vparse_gcov_file <- Vectorize(parse_gcov_file, "gcov_file", USE.NAMES = FALSE)

run_gcov <- function() {
  gcov_path <- Sys.which("gcov")
  llvm_cov_path <- Sys.which("llvm-cov")

  r_pkg_src_dirs <- file.path(pkg_paths, "src")
  r_pkg_src_dirs <- Filter(dir.exists, r_pkg_src_dirs)

  run_gcov_files <- function(gcov_inputs) {
    if (length(gcov_inputs) == 0)
      return(list())

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

    list.files(pattern = "\\.gcov$", recursive = TRUE, full.names = TRUE)
  }

  run_gcov_cc_deps <- function() {
    gcov_inputs <- list.files(pattern = "\\.gcno", recursive = TRUE)
    gcov_inputs <- Filter(function(path) !any(startsWith(path, r_pkg_src_dirs)), gcov_inputs)

    outputs <- run_gcov_files(gcov_inputs)
    on.exit(unlink(outputs))

    # Filter any files with absolute paths; these are most likely system headers.
    Filter(Negate(is.null), vparse_gcov_file(outputs, ""))
  }
  cc_dep_line_coverages <- run_gcov_cc_deps()

  run_gcov_r_pkg <- function(compiler_dir) {
    gcov_inputs <- list.files(compiler_dir, pattern = "\\.gcno$", recursive = TRUE)

    # Switch to the compiler directory to run gcov so all embedded relative paths makes sense.
    orig_dir <- getwd()
    setwd(compiler_dir)
    outputs <- run_gcov_files(gcov_inputs)
    setwd(orig_dir)
    outputs <- file.path(compiler_dir, outputs)
    on.exit(unlink(outputs))

    # Parse the gcov files and fix the paths they represent.
    Filter(Negate(is.null), vparse_gcov_file(outputs, compiler_dir))
  }
  r_pkg_line_coverages <- sapply(r_pkg_src_dirs, run_gcov_r_pkg)

  line_coverages <- c(r_pkg_line_coverages, cc_dep_line_coverages)
  if (length(line_coverages) == 0) {
    return(NULL)
  }

  structure(
    as.list(unlist(line_coverages, recursive = FALSE)),
    class = "coverage")
}
cc_coverage <- run_gcov()

############
# Report

if (is.null(r_coverage) && is.null(cc_coverage)) {
  # Let the coverage file be empty.
  quit(save = "no", status = 0)
}

output_file <- Sys.getenv("COVERAGE_OUTPUT_FILE", NA)
local({
  coverage <- structure(c(r_coverage, cc_coverage),
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
      f <- sub("_WORKSPACE_ROOT_/", "", f) # Placeholder for packages at workspace root.
      f <- sub(test_workspace_pattern, "", f)
      return(f)
    }
    # C++ file paths will be their absolute paths.
    f <- sub(execroot_pattern, "", f)
    f <- sub("^bazel-out/[^/]+/bin/", "", f)
    f <- sub(test_workspace_pattern, "", f)
    return(f)
  }

  coverage_xml <- xml2::read_xml(output_file)
  packages_xml <- xml2::xml_child(coverage_xml, "packages")

  # For recent covr versions, the sources list is empty.
  # So let's always empty it.
  sources_xml <- xml2::xml_child(coverage_xml, "sources")
  for (src in xml2::xml_children(sources_xml)) {
    xml2::xml_remove(src)
  }

  # Remove timestamp
  xml2::xml_attr(coverage_xml, "timestamp") <- "1960-01-01 00:00:00"

  # Fix filenames.
  classes <- xml2::xml_child(xml2::xml_child(packages_xml, "package"), "classes")
  classes_list <- xml2::xml_children(classes)
  fixed_filenames <- sapply(classes_list, function(cl) {
    f <- fix_filename(xml2::xml_attr(cl, "filename"))
    xml2::xml_attr(cl, "filename") <- f
    f
  })
  file_order <- order(fixed_filenames)

  # Sort filenames.
  sorted_classes <- xml2::xml_add_sibling(classes, classes)
  for (i in seq_along(file_order)) {
    xml2::xml_replace(xml2::xml_child(sorted_classes, i),
                      xml2::xml_child(classes, file_order[i]))
  }
  xml2::xml_remove(classes)

  xml2::write_xml(coverage_xml, output_file)
  return(invisible(NULL))
})

message("Done collecting coverage for R tests.")
