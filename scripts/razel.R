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
#' @param pkg_bin_archive If set, uses the relative path provided here to
#'        specify a binary archive of the package.
#' @param no_test_rules If true, test rules are not generated.
#' @param build_file_name Name of the BUILD file in the repo.
#' @param external If true, adds a tag 'external-r-repo' to the r_pkg rule.
#' @export
buildify <- function(pkg_directory = ".", pkg_bin_archive = NULL,
                     no_test_rules = TRUE,
                     build_file_name="BUILD.bazel", external=TRUE) {
  if (is.null(pkg_bin_archive)) {
    desc_file <- file.path(pkg_directory, "DESCRIPTION")
    if (!file.exists(desc_file)) {
      return()
    }
  } else {
    desc_file <- grep("^[^/]+/DESCRIPTION$", untar(pkg_bin_archive, list = TRUE), value = TRUE)
    untar(pkg_bin_archive, files = desc_file)
    stopifnot(file.exists(desc_file))
  }

  # Source files

  pkg_srcs_attr <- function() {
    srcs <- sprintf('glob(["**"])')
    buildignore <- file.path(pkg_directory, ".Rbuildignore")
    instignore <- file.path(pkg_directory, ".Rinstignore")
    exclude_patterns <- c()
    if (file.exists(buildignore)) {
      exclude_patterns <- c(exclude_patterns, trimws(readLines(buildignore, warn = FALSE)))
    }
    if (file.exists(instignore)) {
      exclude_patterns <- c(exclude_patterns, trimws(readLines(instignore, warn = FALSE)))
    }
    exclude_patterns <- exclude_patterns[exclude_patterns != ""]
    exclude_files <- c(build_file_name)
    if (length(exclude_patterns) > 0) {
      all_files <- list.files(path = pkg_directory, all.files = TRUE, full.names = FALSE,
                              recursive = TRUE, include.dirs = TRUE)
      for (exclude_pattern in exclude_patterns) {
        matches <- grep(exclude_pattern, all_files, ignore.case = TRUE, perl = TRUE, value=TRUE)
        exclude_files <- c(exclude_files, matches)
      }
    }
    if (length(exclude_files) > 0) {
      exclude_files_list <- paste0(strrep(' ', 12), '"', unique(exclude_files), '",\n', collapse="")
      srcs <- sprintf('srcs = glob(\n        ["**"],\n        exclude=[\n%s        ],\n    )',
                      exclude_files_list)
    }
    return(srcs)
  }

  if (is.null(pkg_bin_archive)) {
    pkg_rule <- "r_pkg"
    srcs_attr <- pkg_srcs_attr()
  } else {
    pkg_rule <- "r_binary_pkg"
    srcs_attr <- sprintf('src = "%s"', pkg_bin_archive)
  }

  # Dependency files

  base_pkgs <- installed.packages(priority = "base")[, "Package"]
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
    deps <- unique(deps)
    if (length(deps) == 0) {
      return('[],\n')
    }
    dep_targets <- paste0(sprintf("        \"@R_%s\",\n", gsub("\\.", "_", deps)),
                          collapse="")
    return(sprintf('[\n%s    ],\n', dep_targets))
  }

  pkg_description <-
      read.dcf(desc_file, fields = c("Package", "Depends", "Imports", "Suggests", "LinkingTo"))
  name <- pkg_description[1, "Package"]

  depends <- process_deps(pkg_description[, "Depends"])
  imports <- process_deps(pkg_description[, "Imports"])
  links <- process_deps(pkg_description[, "LinkingTo"])
  suggests <- process_deps(pkg_description[, "Suggests"])
  build_deps <- dep_targets(c(depends, imports, links))
  check_deps <- dep_targets(c(depends, imports, links, suggests))
  stopifnot(length(build_deps) == 1)
  stopifnot(length(check_deps) == 1)

  tags_attr <- ifelse(external, '    tags=["external-r-repo"]', '')

  header <- paste0('load("@com_grail_rules_r//R:defs.bzl",',
                   '"r_pkg", "r_binary_pkg",',
                   '"r_library", "r_unit_test", "r_pkg_test")\n\n',
                   'package(default_visibility = ["//visibility:public"])')

  # Convenience alias for external repos to map repo name to pkg target.
  pkg_alias <- sprintf('\nalias(\n    name="%s",\n    actual="%s",\n)',
                          paste0("R_", gsub("\\.", "_", name)), name)

  r_pkg <- sprintf('\n%s(\n    name="%s",\n    %s,\n    deps=%s%s)',
                   pkg_rule, name, srcs_attr, build_deps, tags_attr)
  r_library <- paste0('\nr_library(\n    name="library",\n    pkgs=[":', name,
                      '"],\n    tags=["manual"],\n)')
  r_unit_test <- sprintf(paste0('\nr_unit_test(\n    name="test",\n    pkg="%s",\n',
                                '    suggested_deps=%s)'),
                         name, check_deps)
  r_pkg_test <- sprintf(paste0('\nr_pkg_test(\n    name="check",\n    pkg="%s",\n',
                               '    suggested_deps=%s)'),
                        name, check_deps)

  build_file <- file.path(pkg_directory, build_file_name)
  if (file.exists(build_file)) {
    # Built vignettes store their index in the build directory; we need to delete that.
    # This is only needed on case insensitive FS.
    message("Deleting existing BUILD file/directory.")
    stopifnot(unlink(build_file, recursive = TRUE) == 0)
  }

  cat(header, pkg_alias, r_pkg, r_library, file = build_file, sep = "\n")
  if (!no_test_rules) {
    cat(r_unit_test, r_pkg_test, file = build_file, sep = "\n", append = TRUE)
  }

  if (Sys.which("buildifier") == "") {
    return()
  }

  result <- system2("buildifier", build_file)
  if (result != 0) {
    warning(sprintf("buildifier could not format the file (return code %s)", result))
  }
}

#' Function to generate BUILD files for all packages in a local repo.
#'
#' @param local_repo_dir Local copy of the repository.
#' @param build_file_format Format string for the BUILD file location with
#'        one string placeholder for package name.
#' @param overwrite Recreate the build file if it exists already.
buildifyRepo <- function(local_repo_dir, build_file_format = "BUILD.%s", overwrite = FALSE) {
  pkg_tgzs <- list.files(file.path(local_repo_dir, "src", "contrib"), full.names = TRUE)
  tmp_dir <- tempdir()
  for (pkg_tgz in pkg_tgzs) {
    if (!grepl("tar.gz", pkg_tgz)) {
      next
    }
    pkg_name <- sub("_.*.tar.gz", "", basename(pkg_tgz))
    build_file <- sprintf(build_file_format, pkg_name)
    if (!overwrite && file.exists(build_file)) {
      next
    }
    exdir <- file.path(tmp_dir, pkg_name)
    files <- file.path(pkg_name, c("DESCRIPTION"))
    files_optional <- file.path(pkg_name, c(".Rbuildignore", ".Rinstignore"))
    untar(pkg_tgz, files = files, exdir = exdir)
    suppressWarnings(untar(pkg_tgz, files = files_optional, exdir = exdir,
                           extras = " 2> /dev/null"))
    buildify(file.path(exdir, pkg_name))
    dir.create(dirname(build_file_format), recursive = TRUE, showWarnings = FALSE)
    file.rename(file.path(exdir, pkg_name, "BUILD"), build_file)
    unlink(exdir, recursive = TRUE)
  }
}

#' Generate Bazel WORKSPACE file macro.
#'
#' Generates repository rules for the Bazel WORKSPACE file.
#' @param local_repo_dir Local copy of the repository.
#' @param package_list_csv CSV file containing package name, version, and
#'        possibly empty sha256, with header. If supplied, takes precedence
#'        over local_repo_dir. If using a non-default \code{pkg_type}, and
#'        using \code{sha256}, then at least one more column should be
#'        present with the name
#'        '{mac|win}_{r_major_version}_{r_minor_version}_sha256'.
#' @param output_file File path for generated output.
#' @param build_file_format Format string for the BUILD file location with
#'        one string placeholder for package name. Can be NULL to use
#'        auto generated BUILD file.
#' @param build_file_overrides_csv CSV file containing package name and
#'        build file path to use in the rule; no headers. If present in this
#'        table, build_file_format will be ignored.
#' @param pkg_type The type of archive to use from the repositories. See
#'        \code{install.packages}. If \code{both}, then the type of archive is
#'        chosen based on what is available in the local repo (always
#'        preferring a later version), or in the packages csv with a non-NA
#'        sha256. Platforms other than darwin are forced to have \code{source}
#'        package type. If a binary archive is being used, any build file
#'        overrides will be ignored.
#' @param sha256 If TRUE, calculate the SHA256 digest (using
#'        \code{\link[digest]{digest}}) and include it in the WORKSPACE rule.
#' @param rule_type The type of rule to use. If new_http_archive, then
#'        build_file_format must be provided.
#' @param remote_repos Repo URLs to use.
#' @param mirror_repo_url If not NA, will place this as the first entry in the
#'        WORKSPACE rule URLs, before the repos returned by
#'        \code{getOption("repos")}.
#' @param use_only_mirror_repo If true, will use only the provided mirror repo
#'        URL.
#' @param fail_fast If true, will fail loading the workspace if a package was
#'        not found. Otherwise, the failure will happen on first use of the
#'        package.
#' @export
generateWorkspaceMacro <- function(local_repo_dir = NULL,
                                   package_list_csv = NULL,
                                   output_file = "r_repositories.bzl",
                                   build_file_format = NULL,
                                   build_file_overrides_csv = NULL,
                                   pkg_type = c("source", "both"),
                                   sha256 = TRUE,
                                   rule_type = c("r_repository", "new_http_archive"),
                                   remote_repos = getOption("repos"),
                                   mirror_repo_url = NULL,
                                   use_only_mirror_repo = FALSE,
                                   fail_fast = FALSE) {
  stopifnot(!is.null(local_repo_dir) || !is.null(package_list_csv))
  stopifnot(!use_only_mirror_repo || !is.null(mirror_repo_url))
  rule_type <- match.arg(rule_type)
  stopifnot(!(rule_type == "new_http_archive" && is.null(build_file_format)))

  pkg_type <- match.arg(pkg_type)
  if (Sys.info()["sysname"] != "Darwin") {
    pkg_type <- "source"
  }

  if (is.null(build_file_format)) {
    build_file_format <- NA_character_
  }

  if (!is.null(package_list_csv)) {
    repo_pkgs <- read.csv(package_list_csv, header = TRUE, stringsAsFactors = FALSE)
    colnames(repo_pkgs)[1:3] <- c("Package", "Version", "sha256")
    binary_package_available <- rep(FALSE, nrow(repo_pkgs))
    if (pkg_type == "both") {
      r_version <- R.Version()
      minor_version <- gsub("\\..*", "", r_version$minor)
      sha256_col <- paste0("mac_", r_version$major, "_", minor_version, "_sha256")
      if (sha256_col %in% colnames(repo_pkgs)) {
        binary_package_available <- !is.na(repo_pkgs[, sha256_col])
        repo_pkgs[binary_package_available, "sha256"] <-
          repo_pkgs[binary_package_available, sha256_col]
      } else {
        pkg_type <- "source"
      }
    }
  } else {
    local_repo_path <- paste0("file://", path.expand(local_repo_dir))
    repo_pkgs <- as.data.frame(available.packages(repos = local_repo_path, type = "source"),
                               stringsAsFactors = FALSE)
    binary_package_available <- rep(FALSE, nrow(repo_pkgs))
    if (pkg_type == "both") {
      repo_bin_pkgs <- as.data.frame(available.packages(repos = local_repo_path, type = "binary"),
                                stringsAsFactors = FALSE)[, c("Package", "Version", "Repository")]
      repo_merged_pkgs <- merge(repo_pkgs, repo_bin_pkgs, by = "Package",
                                all.x = TRUE, all.y = FALSE,
                                suffixes = c("", ".binary"))

      vecCompareVersion <- Vectorize(compareVersion)
      binary_package_available <- !is.na(repo_merged_pkgs[, "Repository.binary"]) &
        vecCompareVersion(repo_merged_pkgs[, "Version.binary"], repo_merged_pkgs[, "Version"]) >= 0
    }
  }
  repo_pkgs <- cbind(repo_pkgs,
                     Archive = paste0(repo_pkgs$Package, "_", repo_pkgs$Version,
                                      ifelse(binary_package_available, ".tgz", ".tar.gz")),
                     stringsAsFactors = FALSE)

  findPackages <- function(repos, suffix) {
    mergeWithRemote <- function(type) {
      remote_pkgs <- as.data.frame(
          available.packages(repos = repos, type = type)[, c("Package", "Repository")],
          stringsAsFactors = FALSE)
      colnames(remote_pkgs) <- c("Package", paste0("Repository", suffix))
      merge(repo_pkgs[ifelse(type == rep("binary", length(binary_package_available)),
                             binary_package_available,
                             !binary_package_available), ],
            remote_pkgs, by = "Package", all.x = TRUE, all.y = FALSE)
    }

    if (pkg_type == "both") {
      unordered <- rbind(mergeWithRemote("binary"), mergeWithRemote("source"),
                         make.row.names = FALSE, stringsAsFactors = FALSE)
      return(unordered[match(repo_pkgs[, "Package"], unordered[, "Package"]), ])
    } else {
      return(mergeWithRemote("source"))
    }
  }

  if (!is.null(mirror_repo_url)) {
    repo_pkgs <- findPackages(mirror_repo_url, ".mirrored")
  }

  if (length(remote_repos) > 0) {
    repo_pkgs <- findPackages(remote_repos, ".remote")
  }

  if (sha256 && is.null(package_list_csv)) {
    pkg_files <- file.path(ifelse(binary_package_available,
                                  contrib.url(local_repo_dir, type="binary"),
                                  contrib.url(local_repo_dir, type="source")),
                           repo_pkgs$Archive)
    pkg_shas <- sapply(pkg_files, function(pkg_file) {
                         digest::digest(file = pkg_file, algo = "sha256")
                       })
    repo_pkgs <- cbind(repo_pkgs, "sha256" = pkg_shas, stringsAsFactors = FALSE)
  }

  if (!is.null(build_file_overrides_csv)) {
    build_file_overrides <- read.csv(build_file_overrides_csv, header = TRUE,
                                      stringsAsFactors = FALSE,
                                      col.names = c("Package", "build_file"))
    repo_pkgs <- merge(repo_pkgs, build_file_overrides, by = "Package",
                       all.x = TRUE, all.y = FALSE)
  } else {
    repo_pkgs <- cbind(repo_pkgs, "build_file" = NA_character_)
  }
  repo_pkgs[binary_package_available, "build_file"] <- NA_character_

  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  file.create(output_file)
  output_con <- file(output_file, open = "w")
  on.exit(close(output_con))

  c("# Autogenerated repo definitions for R packages (see scripts/razel.R)",
    "",
    "load(\"@com_grail_rules_r//R:repositories.bzl\", \"r_repository\")",
    "",
    "def r_repositories():") -> header
  writeLines(header, output_con)

  for (i in seq_len(nrow(repo_pkgs))) {
    pkg <- repo_pkgs[i, ]
    pkg_repos <- c()
    if ("Repository.mirrored" %in% colnames(pkg) && !is.na(pkg$Repository.mirrored)) {
      pkg_repos <- c(pkg_repos, as.character(pkg$Repository.mirrored))
    }
    if (!use_only_mirror_repo && "Repository.remote" %in% colnames(pkg) &&
        !is.na(pkg$Repository.remote)) {
      pkg_repos <- c(pkg_repos, as.character(pkg$Repository.remote))
      if (!binary_package_available[i]) {
        pkg_repos <- c(pkg_repos, paste0(pkg$Repository.remote, "/Archive/", pkg$Package))
      }
    }
    if (isTRUE(fail_fast) && length(pkg_repos) == 0) {
      stop("Package not available in any of the provided repos: ", pkg$Package)
    }
    if (length(pkg_repos) > 0) {
      pkg_urls <- paste0("        \"", pkg_repos, "/", pkg$Archive, "\",")
    } else {
      pkg_urls <- c()
    }

    pkg_build_file_format <- ifelse(is.na(pkg$build_file), build_file_format, pkg$build_file)
    bzl_repo_name <- paste0("R_", gsub("\\.", "_", pkg$Package))
    c("",
      sprintf("if not native.existing_rule(\"%s\"):", bzl_repo_name)) -> preamble
    writeLines(paste0(strrep(" ", 4), preamble), output_con)

    if (rule_type == "r_repository" && binary_package_available[i]) {
      pkg_type_attr <- sprintf('    pkg_type = "binary",')
    } else {
      pkg_type_attr <- character()
    }

    c(sprintf("%s(", rule_type),
      sprintf('    name = "%s",', bzl_repo_name),
      ifelse(!is.na(pkg_build_file_format),
             sprintf('    build_file = "%s",', sprintf(pkg_build_file_format, pkg$Package)),
             "    build_file = None,"),
      pkg_type_attr,
      ifelse(sha256 && nchar(pkg$sha256) > 0,
             sprintf('    sha256 = "%s",', pkg$sha256),
             "    sha256 = None,"),
      sprintf('    strip_prefix = "%s",', pkg$Package),
      "    urls = [",
      pkg_urls,
      "    ],",
      ")") -> bazel_repo_def
    writeLines(paste0(strrep(" ", 8), bazel_repo_def), output_con)
  }
}
