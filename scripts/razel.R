# Copyright 2017 GRAIL, Inc.
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

# Utility functions to create BUILD files and WORKSPACE rules for R packages for use
# in Bazel build system.

#' Create a BUILD file from the package directory.
#'
#' It checks for the DESCRIPTION, NAMESPACE, .Rinstignore, and .Rbuildignore files.
#' All dependencies are assumed to be external dependencies; if they are present
#' elsewhere you must manually edit the file later.
#' This tool is not perfect; you must always examine the generated BUILD file,
#' especially the exclude section of the srcs glob.
#' @param pkg_directory
#' @param no_test_rules If true, test rules are not generated.
#' @export
buildify <- function(pkg_directory = ".", no_test_rules = TRUE) {
  desc_file <- file.path(pkg_directory, "DESCRIPTION")
  if (!file.exists(desc_file)) {
    return()
  }

  pkg_description <- read.dcf(desc_file,
                              fields = c("Package", "Depends", "Imports", "Suggests", "LinkingTo",
                                         "LazyData"))
  name <- pkg_description[1, "Package"]

  # Source files

  buildignore <- file.path(pkg_directory, ".Rbuildignore")
  instignore <- file.path(pkg_directory, ".Rinstignore")
  exclude_patterns <- c()
  if (file.exists(buildignore)) {
    exclude_patterns <- c(exclude_patterns, trimws(readLines(buildignore)))
  }
  if (file.exists(instignore)) {
    exclude_patterns <- c(exclude_patterns, trimws(readLines(instignore)))
  }
  exclude_patterns <- exclude_patterns[exclude_patterns != ""]
  exclude_globs <- c()
  if (length(exclude_patterns) > 0) {
    exclude_globs <- shQuote(as.character(sapply(paste0("**/*", exclude_patterns),
                                                 paste0, c("*", "*/**"))))
  }
  exclude_globs_list <- paste0(exclude_globs, collapse = ", ")
  srcs <- sprintf('glob(["**"], exclude=[%s])', exclude_globs_list)

  # Dependency files

  base_pkgs <- installed.packages(priority = "high")[, "Package"]
  process_deps <- function(pkgs_csv) {
    if ((length(pkgs_csv) == 1) && is.na(pkgs_csv[1])) {
      return(character(0))
    }
    pkgs_csv <- paste(pkgs_csv, collapse = ",")
    pkg_vec <- strsplit(pkgs_csv, ",")[[1]]
    pkg_vec <- gsub("\\(.*", "", pkg_vec)
    pkg_vec <- gsub("\n", "", pkg_vec)
    pkg_vec <- trimws(pkg_vec, which = "both")
    pkg_vec <- pkg_vec[!pkg_vec %in% c("", "R", base_pkgs)]

    return(pkg_vec)
  }
  dep_targets <- function(deps) {
    if (length(deps) == 0) {
      return("")
    }
    do.call(paste, c(as.list(sprintf("\"@R_%s//:%s\"", gsub("\\.", "_", deps), deps)),
                     list(sep = ", ")))
  }

  depends <- process_deps(pkg_description[, "Depends"])
  imports <- process_deps(pkg_description[, "Imports"])
  links <- process_deps(pkg_description[, "LinkingTo"])
  suggests <- process_deps(pkg_description[, "Suggests"])
  build_deps <- dep_targets(c(depends, imports, links))
  check_deps <- dep_targets(c(depends, imports, links, suggests))
  stopifnot(length(build_deps) == 1)
  stopifnot(length(check_deps) == 1)

  ns_file <- file.path(pkg_directory, "NAMESPACE")
  shlib_name <- gsub("[\"\']", "",
                     sub("useDynLib\\((.*?)[,\\)].*$", "\\1",
                         grep("^\\s*useDynLib", readLines(ns_file), value = TRUE)))
  shlib_attr <- ifelse(length(shlib_name) == 1 && shlib_name != name,
                       paste0(', shlib_name="', shlib_name, '"'), "")

  data_attr <- ifelse(tolower(pkg_description[1, "LazyData"]) %in% c("true", "yes"),
                      ", lazy_data=True", "")

  header <- paste(c(paste0('load("@com_grail_rules_r//R:defs.bzl", "r_pkg", ',
                           '"r_library", "r_unit_test", "r_pkg_test")'),
                    'package(default_visibility = ["//visibility:public"])'), sep = "\n")

  r_pkg <- sprintf('r_pkg(name="%s", srcs=%s, deps=[%s] %s %s)',
                   name, srcs, build_deps, shlib_attr, data_attr)
  r_library <- sprintf('r_library(name="library", pkgs=[":%s"], tags=["manual"])',
                       name)
  r_unit_test <- sprintf('r_unit_test(name="test", pkg_name="%s", srcs=%s, deps=[%s])',
                         name, srcs, paste0(":\"", name, "\", ", check_deps))
  r_pkg_test <- sprintf('r_pkg_test(name="check", pkg_name="%s", srcs=%s, deps=[%s])',
                        name, srcs, check_deps)

  build_file <- file.path(pkg_directory, "BUILD")
  if (file.exists(build_file)) {
    # Built vignettes store their index in the build directory; we need to delete that.
    # This is only needed on case insensitive FS.
    message("Deleting existing BUILD file/directory.")
    stopifnot(unlink(build_file, recursive = TRUE) == 0)
  }

  cat(header, r_pkg, r_library, file = build_file, sep = "\n")
  if (!no_test_rules) {
    cat(r_unit_test, r_pkg_test, file = build_file, sep = "\n", append = TRUE)
  }

  status <- system(paste("buildifier", build_file))
  if (status == 127) {
    warning("buildifier not found on this system; could not format BUILD file")
  } else if (status != 0) {
    warning("buildifier could not format the file")
  }
}

#' Function to generate BUILD files for all packages in a local repo.
#'
#' @param local_repo_dir Local copy of the repository.
#' @param build_file_prefix Prefix that will be prepended to the package name
#'        to generate the BUILD file name.
#' @param build_file_suffix Suffix that will be appended to the package name
#'        to generate the BUILD file name.
#' @param overwrite Recreate the build file if it exists already.
buildifyRepo <- function(local_repo_dir, build_file_prefix = "BUILD.",
                         build_file_suffix = "", overwrite = FALSE) {
  if (grepl(.Platform$file.sep, build_file_prefix)) {
    dir.create(dirname(build_file_prefix), recursive = TRUE, showWarnings = FALSE)
  }

  pkg_tgzs <- list.files(file.path(local_repo_dir, "src", "contrib"), full.names = TRUE)
  tmp_dir <- tempdir()
  for (pkg_tgz in pkg_tgzs) {
    if (!grepl("tar.gz", pkg_tgz)) {
      next
    }
    pkg_name <- sub("_.*.tar.gz", "", basename(pkg_tgz))
    build_file <- paste0(build_file_prefix, pkg_name, build_file_suffix)
    if (!overwrite && file.exists(build_file)) {
      next
    }
    exdir <- file.path(tmp_dir, pkg_name)
    files <- file.path(pkg_name, c("DESCRIPTION", "NAMESPACE"))
    files_optional <- file.path(pkg_name, c(".Rbuildignore", ".Rinstignore"))
    untar(pkg_tgz, files = files, exdir = exdir)
    suppressWarnings(untar(pkg_tgz, files = files_optional, exdir = exdir,
                           extras = " 2> /dev/null"))
    buildify(file.path(exdir, pkg_name))
    file.rename(file.path(exdir, pkg_name, "BUILD"), build_file)
    unlink(exdir, recursive = TRUE)
  }
}

#' Generate Bazel WORKSPACE file.
#'
#' Generates http archive rules for the Bazel WORKSPACE file.
#' @param local_repo_dir Local copy of the repository.
#' @param workspace_file File path for generated output.
#' @param build_file_prefix Prefix that will be prepended to the package name
#'        to generate the BUILD file name.
#' @param build_file_suffix Suffix that will be appended to the package name
#'        to generate the BUILD file name.
#' @param sha256 If TRUE, calculate the SHA256 digest (using
#'        \code{\link[digest]{digest}}) and include it in the WORKSPACE rule.
#' @param mirror_repo_url If not NA, will place this as the first entry in the
#'        WORKSPACE rule URLs, before the repos returned by
#'        \code{getOption("repos")}.
#' @param use_only_mirror_repo If true, will use only the provided mirror repo
#'        URL.
#' @param bioc_version If not NA, release version of Bioconductor to use for
#'        generating remote repo URLs, overriding the values returned by
#'        \code{getOption("repos")}.
#' @export
generateWorkspaceFile <- function(local_repo_dir,
                                  workspace_file = "WORKSPACE",
                                  build_file_prefix = "BUILD.",
                                  build_file_suffix = "",
                                  sha256 = TRUE,
                                  mirror_repo_url = NA_character_,
                                  use_only_mirror_repo = FALSE,
                                  bioc_version = NA_character_) {
  stopifnot(!use_only_mirror_repo || !is.na(mirror_repo_url))

  repo_pkgs <- as.data.frame(available.packages(repos = paste0("file://",
                                                               path.expand(local_repo_dir))))
  repo_pkgs <- cbind(repo_pkgs,
                     Archive = paste0(repo_pkgs$Package, "_", repo_pkgs$Version, ".tar.gz"))

  if (!use_only_mirror_repo) {
    remote_repos <- getOption("repos")
    if (!is.na(bioc_version)) {
      if (!requireNamespace("BiocInstaller", quietly = TRUE)) {
        source("https://bioconductor.org/biocLite.R")
      }
      BiocInstaller::biocinstallRepos(version = bioc_version)
    }
    remote_pkgs <- available.packages(repos = remote_repos)[, c("Package", "Repository")]
    repo_pkgs <- merge(repo_pkgs, as.data.frame(remote_pkgs), by = "Package",
                       all.x = TRUE, all.y = FALSE, suffixes = c("", ".remote"))
  }

  if (sha256) {
    # Remove file://
    pkg_files <- substr(file.path(repo_pkgs$Repository, repo_pkgs$Archive), 6, 10000)
    pkg_shas <- sapply(pkg_files, function(pkg_file) {
                         digest::digest(file = pkg_file, algo="sha256")
                       })
    repo_pkgs <- cbind(repo_pkgs, "sha256" = pkg_shas)
  }

  header <- "# Autogenerated repo definitions for R packages (see scripts/razel.R).\n"
  cat(header, file=workspace_file)

  for (i in seq_len(nrow(repo_pkgs))) {
    pkg <- repo_pkgs[i, ]
    pkg_repos <- c()
    if (!is.na(mirror_repo_url)) {
      pkg_repos <- c(paste0(mirror_repo_url, "/src/contrib"))
    }
    if (!use_only_mirror_repo) {
      pkg_repos <- c(pkg_repos, as.character(pkg$Repository.remote))
      if (!grepl("bioconductor", pkg$Repository.remote)) {
        # Older versions of CRAN packages get moved to Archive.
        pkg_repos <- c(pkg_repos, paste0(pkg$Repository.remote, "/Archive/", pkg$Package))
      }
    }
    paste0("\nnew_http_archive(\n",
           "    name = \"R_", gsub("\\.", "_", pkg$Package), "\",\n",
           "    build_file = \"", build_file_prefix, pkg$Package, build_file_suffix, "\",\n",
           ifelse(sha256,
                  paste0("    sha256 = \"", pkg$sha256, "\",\n"),
                  ""),
           "    strip_prefix = \"", pkg$Package, "\",\n",
           "    urls = [\n",
           paste0("        \"", pkg_repos, "/", pkg$Archive, "\",\n", collapse=""),
           "    ],\n",
           ")\n")  -> bazel_repo_def
    cat(bazel_repo_def, file = workspace_file, append = TRUE)
  }
}
