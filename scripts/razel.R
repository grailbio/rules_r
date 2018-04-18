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
#' @param no_test_rules If true, test rules are not generated.
#' @param build_file_name Name of the BUILD file in the repo.
#' @param external If true, adds a tag 'external-r-repo' to the r_pkg rule.
#' @export
buildify <- function(pkg_directory = ".", no_test_rules = TRUE,
                     build_file_name="BUILD.bazel", external=TRUE) {
  desc_file <- file.path(pkg_directory, "DESCRIPTION")
  if (!file.exists(desc_file)) {
    return()
  }

  pkg_description <- read.dcf(desc_file,
                              fields = c("Package", "Depends", "Imports", "Suggests", "LinkingTo",
                                         "LazyData"))
  name <- pkg_description[1, "Package"]

  # Source files
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
    srcs <- sprintf('glob(\n        ["**"],\n        exclude=[\n%s        ],\n    )',
                    exclude_files_list)
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
                         grep("^\\s*useDynLib", readLines(ns_file, warn = FALSE), value = TRUE)))
  shlib_attr <- ifelse(length(shlib_name) == 1 && shlib_name != name,
                       paste0('    shlib_name="', shlib_name, '",\n'), "")

  data_attr <- ifelse(tolower(pkg_description[1, "LazyData"]) %in% c("true", "yes"),
                      "    lazy_data=True,\n", "")

  tags_attr <- ifelse(external, '    tags=["external-r-repo"]', '')

  header <- paste0('load("@com_grail_rules_r//R:defs.bzl", "r_pkg", ',
                   '"r_library", "r_unit_test", "r_pkg_test")\n\n',
                   'package(default_visibility = ["//visibility:public"])')

  # Convenience alias for external repos to map repo name to pkg target.
  pkg_alias <- sprintf('\nalias(\n    name="%s",\n    actual="%s",\n)',
                          paste0("R_", gsub("\\.", "_", name)), name)

  r_pkg <- sprintf('\nr_pkg(\n    name="%s",\n    srcs=%s,\n    deps=%s%s%s%s)',
                   name, srcs, build_deps, shlib_attr, data_attr, tags_attr)
  r_library <- paste0('\nr_library(\n    name="library",\n    pkgs=[":', name,
                      '"],\n    tags=["manual"],\n)')
  r_unit_test <- sprintf(paste0('\nr_unit_test(\n    name="test",\n    pkg_name="%s",\n',
                                '    srcs=%s,\n',
                                '    deps=%s)'),
                         name, srcs, paste0("        :\"", name, "\",\n", check_deps))
  r_pkg_test <- sprintf(paste0('\nr_pkg_test(\n    name="check",\n    pkg_name="%s",\n',
                               '    srcs=%s,\n',
                               '    deps=%s)'),
                        name, srcs, check_deps)

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
    files <- file.path(pkg_name, c("DESCRIPTION", "NAMESPACE"))
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
#'        over local_repo_dir.
#' @param output_file File path for generated output.
#' @param build_file_format Format string for the BUILD file location with
#'        one string placeholder for package name. Can be NULL to use
#'        auto generated BUILD file.
#' @param build_file_overrides_csv CSV file containing package name and
#'        build file path to use in the rule; no headers. If present in this
#'        table, build_file_format will be ignored.
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
#' @export
generateWorkspaceMacro <- function(local_repo_dir = NULL,
                                   package_list_csv = NULL,
                                   output_file = "r_repositories.bzl",
                                   build_file_format = NULL,
                                   build_file_overrides_csv = NULL,
                                   sha256 = TRUE,
                                   rule_type = c("r_repository", "new_http_archive"),
                                   remote_repos = getOption("repos"),
                                   mirror_repo_url = NULL,
                                   use_only_mirror_repo = FALSE) {
  stopifnot(!is.null(local_repo_dir) || !is.null(package_list_csv))
  stopifnot(!use_only_mirror_repo || !is.null(mirror_repo_url))
  rule_type <- match.arg(rule_type)
  stopifnot(!(rule_type == "new_http_archive" && is.null(build_file_format)))

  if (is.null(build_file_format)) {
    build_file_format <- NA_character_
  }

  if (!is.null(package_list_csv)) {
    repo_pkgs <- read.csv(package_list_csv, header = TRUE, stringsAsFactors = FALSE,
                          col.names = c("Package", "Version", "sha256"))
  } else {
    local_repo_path <- paste0("file://", path.expand(local_repo_dir))
    repo_pkgs <-
      as.data.frame(available.packages(repos = local_repo_path, type = "source"))
  }
  repo_pkgs <- cbind(repo_pkgs,
                     Archive = paste0(repo_pkgs$Package, "_", repo_pkgs$Version, ".tar.gz"))

  if (!use_only_mirror_repo) {
    remote_pkgs <-
      available.packages(repos = remote_repos, type = "source")[, c("Package", "Repository")]
    colnames(remote_pkgs) <- c("Package", "Repository.remote")
    repo_pkgs <- merge(repo_pkgs, as.data.frame(remote_pkgs), by = "Package",
                       all.x = TRUE, all.y = FALSE)
  }

  if (sha256 && !("sha256" %in% colnames(repo_pkgs))) {
    # Remove file://
    pkg_files <- substr(file.path(repo_pkgs$Repository, repo_pkgs$Archive), 6, 10000)
    pkg_shas <- sapply(pkg_files, function(pkg_file) {
                         digest::digest(file = pkg_file, algo = "sha256")
                       })
    repo_pkgs <- cbind(repo_pkgs, "sha256" = pkg_shas)
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
    if (!is.null(mirror_repo_url)) {
      pkg_repos <- c(paste0(mirror_repo_url, "/src/contrib"))
    }
    if (!use_only_mirror_repo) {
      pkg_repos <- c(pkg_repos, as.character(pkg$Repository.remote))
      if ("CRAN" %in% names(remote_repos) &&
          startsWith(as.character(pkg$Repository.remote), remote_repos["CRAN"])) {
        # Older versions of CRAN packages get moved to Archive.
        pkg_repos <- c(pkg_repos, paste0(pkg$Repository.remote, "/Archive/", pkg$Package))
      }
    }

    pkg_build_file_format <- ifelse(is.na(pkg$build_file), build_file_format, pkg$build_file)
    bzl_repo_name <- paste0("R_", gsub("\\.", "_", pkg$Package))
    c("",
      sprintf("if not native.existing_rule(\"%s\"):", bzl_repo_name)) -> preamble
    writeLines(paste0(strrep(" ", 4), preamble), output_con)

    c(sprintf("%s(", rule_type),
      paste0("    name = \"", bzl_repo_name, "\","),
      ifelse(!is.na(pkg_build_file_format),
             paste0("    build_file = \"", sprintf(pkg_build_file_format, pkg$Package), "\","),
             "    build_file = None,"),
      ifelse(sha256 && nchar(pkg$sha256) > 0,
             paste0("    sha256 = \"", pkg$sha256, "\","),
             "    sha256 = None,"),
      paste0("    strip_prefix = \"", pkg$Package, "\","),
      "    urls = [",
      paste0("        \"", pkg_repos, "/", pkg$Archive, "\","),
      "    ],",
      ")") -> bazel_repo_def
    writeLines(paste0(strrep(" ", 8), bazel_repo_def), output_con)
  }
}
