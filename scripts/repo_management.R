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

# Utility functions to manage private repo of third party packages.
# See documentation for functions annotated with '@export'.
# Only CRAN and Bioc mirrors are tested.

# This script needs the following packages to function.
# - digest
# - tools

# Options to also download binary archives.
options("BinariesMac" = TRUE)  # Binaries for Mac
options("BinariesWin" = FALSE)  # Binaries for Win
options("RVersions" = c("3.4", "3.5", "3.6"))  # Binaries for these R versions.
options("ForceDownload" = FALSE)  # Download packages even if src package already present in repo.

# Factors in unexpected places create problems.
options("stringsAsFactors" = FALSE)

# Returns source archive locations of repos.
srcContribDir <- function() {
  return("/src/contrib")
}

# Returns macOS binary archive locations of repos based on R version.
macContribDir <- function(r_version) {
  stopifnot(r_version %in% getOption("RVersions"))
  return(paste0("/bin/macosx/el-capitan/contrib/", r_version))
}

# Returns windows binary archive locations of repos based on R version.
winContribDir <- function(r_version) {
  stopifnot(r_version %in% getOption("RVersions"))
  return(paste0("/bin/windows/contrib/", r_version))
}

# Returns true if this repo has binary packages for this R version.
isValidBinRepo <- function(repo, r_version) {
  if (!startsWith(repo, "https://bioconductor.org/packages/")) {
    return(TRUE)
  }

  if (!endsWith(repo, "bioc")) {
    return(FALSE)
  }

  bioc_version <- gsub("(.*packages/|/bioc)", "", repo)
  return((bioc_version == "3.9" && r_version == "3.6") ||
         (bioc_version == "3.8" && r_version == "3.5") ||
         (bioc_version == "3.7" && r_version == "3.5") ||
         (bioc_version == "3.6" && r_version == "3.4") ||
         (bioc_version == "3.5" && r_version == "3.4"))
}

# Download the latest available specified packages.
downloadLatestPackages <- function(pkgs, repo_dir, repos) {
  contrib_dir <- file.path(repo_dir, file.path("src", "contrib"))
  dir.create(contrib_dir, recursive = TRUE, showWarnings = FALSE)
  download.packages(pkgs, destdir = contrib_dir, repos = repos, type = "source")

  for (r_version in getOption("RVersions")) {
    bin_repos <- repos[sapply(repos, isValidBinRepo, r_version)]

    if (getOption("BinariesMac")) {
      mac_contrib_dir <- paste0(repo_dir, macContribDir(r_version))
      dir.create(mac_contrib_dir, recursive = TRUE, showWarnings = FALSE)
      download.packages(pkgs, destdir = mac_contrib_dir,
                        contriburl = paste0(bin_repos, macContribDir(r_version)),
                        type = "mac.binary")
    }

    if (getOption("BinariesWin")) {
      win_contrib_dir <- paste0(repo_dir, winContribDir(r_version))
      dir.create(win_contrib_dir, recursive = TRUE, showWarnings = FALSE)
      download.packages(pkgs, destdir = win_contrib_dir,
                        contriburl = paste0(bin_repos, winContribDir(r_version)),
                        type = "win.binary")
    }
  }
}

# Download source archive for packages at specified versions.
# archived_packages is a data frame with character columns Package, Version and Repository.
downloadArchivedPackages <- function(archived_packages, repo_dir) {
  contrib_dir <- file.path(repo_dir, file.path("src", "contrib"))

  failed_packages <- character()
  for (index in seq_len(nrow(archived_packages))) {
    pkg_name <- as.character(archived_packages$Package[index])
    pkg_version <- as.character(archived_packages$Version[index])
    pkg_file <- paste0(pkg_name, "_", pkg_version, ".tar.gz")
    archive_url <- paste0(archived_packages$Repository[index], "/Archive/",
                          pkg_name, "/", pkg_file)
    suppressWarnings(tryCatch(
      download.file(archive_url, file.path(contrib_dir, pkg_file)),
      error = function(e) {
        failed_packages <<- c(pkg_name, failed_packages)
      }))
  }
  if (length(failed_packages) > 0) {
    warning(paste("Failed to download archived packages:", paste(failed_packages, collapse = ", ")))
  }
}

# Gets package SHAs for archive packages from the repo directory.
packageSHAs <- function(pkgs, repo_dir=".") {
  pkgs <- as.data.frame(pkgs)
  if (nrow(pkgs) == 0) {
    return(cbind(pkgs, "sha256"=character()))
  }

  helper <- function(contribDir, colname, extension) {
    pkg_files <-
      file.path(contribDir, paste0(pkgs$Package, "_", pkgs$Version, extension))
    pkg_shas <- sapply(pkg_files, function(filepath) {
        if (file.exists(filepath)) {
          digest::digest(file=filepath, algo="sha256")
        } else {
          NA_character_
        }
    })
    colname <- gsub("\\.", "_", colname)
    pkgs[, colname] <<- pkg_shas
  }

  helper(file.path(repo_dir, "src", "contrib"), "sha256", ".tar.gz")
  for (r_version in getOption("RVersions")) {
    if (getOption("BinariesMac")) {
      mac_contrib_dir <- paste0(repo_dir, macContribDir(r_version))
      helper(mac_contrib_dir, paste0("mac_", r_version, "_sha256"), ".tgz")
    }
    if (getOption("BinariesWin")) {
      win_contrib_dir <- paste0(repo_dir, winContribDir(r_version))
      helper(win_contrib_dir, paste0("win_", r_version, "_sha256"), ".zip")
    }
  }
  return(pkgs)
}

#' Already downloaded source archive packages in the repo.
#'
#' @param repo_dir Directory with the repository structure.
#' @return Data frame containing package name and version.
#' @export
repoPackages <- function(repo_dir) {
  if (!file.exists(paste0(repo_dir, srcContribDir(), "/PACKAGES"))) {
    # Destination is not an indexed repository.
    return(data.frame(Package = character(), Version = character()))
  }

  repo_path <- paste0("file://", normalizePath(repo_dir))
  return(as.data.frame(available.packages(repos = repo_path))[, c("Package", "Version")])
}

#' Update the index of a repo after manual addition or deletion of packages.
#'
#' @param repo_dir Directory with the repository structure.
#' @export
updateRepoIndex <- function(repo_dir) {
  tools::write_PACKAGES(paste0(repo_dir, srcContribDir()), type = "source")
  for (r_version in getOption("RVersions")) {
    macDir <- paste0(repo_dir, macContribDir(r_version))
    winDir <- paste0(repo_dir, winContribDir(r_version))
    if (file.exists(macDir)) {
      tools::write_PACKAGES(macDir, type = "mac.binary")
    }
    if (file.exists(winDir)) {
      tools::write_PACKAGES(winDir, type = "win.binary")
    }
  }
}

#' Adds the specified packages to a repo, if not already present.
#'
#' @param pkgs Character vector containing names of packages
#' @param versions Character vector of same length as pkgs, containing version strings for each
#'        package. A value of NA_character_ for version implies latest available package.
#' @param repo_dir Directory where the repository structure will be created.
#' @param deps The type of dependencies to traverse.
#' @return Data frame containing package name, version and sha256 of the source archive for all
#'         packages added to the repo that were not previously present.
#' @export
addPackagesToRepo <- function(pkgs, versions = NA, repo_dir,
                              deps = c("Depends", "Imports", "LinkingTo")) {
  stopifnot(is.character(pkgs))
  if ((length(versions) == 1) && is.na(versions[1])) {
    versions <- rep(NA_character_, length(pkgs))
  }
  stopifnot(is.character(versions))
  stopifnot(length(pkgs) == length(versions))

  if (length(pkgs) == 0) {
    return()
  }

  repo_packages <- repoPackages(repo_dir)

  package_deps <- tools::package_dependencies(pkgs, which = deps, recursive = TRUE)
  package_deps <- unique(unlist(package_deps, use.names = FALSE))
  implicit_package_deps <- setdiff(package_deps, pkgs)
  implicit_package_deps <- setdiff(implicit_package_deps, repo_packages$Package)

  repos <- getOption("repos")
  packages_available <-
    as.data.frame(available.packages(repos = repos)[, c("Package", "Version", "Repository")])

  packages_to_download <- data.frame(Package = c(pkgs, implicit_package_deps),
                                     Version = c(versions,
                                                 rep(NA_character_, length(implicit_package_deps))))

  packages_merged <- merge(packages_to_download, packages_available, by = c("Package"),
                           suffixes = c("", ".available"))
  # Substitute unspecified version to download with available version.
  packages_merged$Version <- ifelse(is.na(packages_merged$Version),
                                    packages_merged$Version.available,
                                    packages_merged$Version)

  # Discard packages that are already in the repo for their requested version.
  if (!getOption("ForceDownload")) {
    current_packages <- merge(packages_merged, repo_packages)[, "Package"]
    packages_merged <- packages_merged[!(packages_merged$Package %in% current_packages), ]
  }

  # Packages that are requested at their latest version.
  latest_packages_mask <- (packages_merged$Version == packages_merged$Version.available)
  latest_packages <- packages_merged[latest_packages_mask, "Package"]
  downloadLatestPackages(latest_packages, repo_dir, repos)

  archived_packages <- packages_merged[!latest_packages_mask, ]
  downloadArchivedPackages(archived_packages, repo_dir)

  updateRepoIndex(repo_dir)

  packageSHAs(packages_merged[, c("Package", "Version")], repo_dir = repo_dir)
}

#' Writes a CSV of all packages in the repo.
#'
#' @param repo_dir Directory with the repository structure.
#' @param output_file Output CSV file path.
#' @param sha256 If TRUE, compute sha256 of package archives.
#' @export
packageList <- function(repo_dir, output_file, sha256=TRUE) {
  repo_packages <- repoPackages(repo_dir)
  if (sha256) {
    repo_packages <- packageSHAs(repo_packages, repo_dir)
  } else {
    repo_packages <- cbind(repo_packages, "sha256"="")
  }
  write.table(repo_packages, file=output_file, col.names=TRUE, row.names=FALSE, sep=",")
}

#' Dumps the packages installed in this library into a repo structure.
#'
#' @param repo_dir Directory where the repository structure will be created.
#' @param keep_versions Whether to download the same versions of packages as in this library.
#' @return Same as addPackagesToRepo.
#' @export
cloneLibraryToRepo <- function(repo_dir, keep_versions = TRUE) {
  pkgs <- installed.packages()
  pkgs <- pkgs[pkgs$Priority != "base", ]  # Do not include base packages.
  vers <- {if (keep_versions) pkgs[, "Version"] else rep(NA_character_, nrow(pkgs))}
  addPackagesToRepo(pkgs = pkgs[, "Package"], versions = vers, repo_dir = repo_dir)
}

#' Install the packages in the repo to a given library, if not already installed.
#'
#' Replaces packages where versions are different.
#' @param repo_dir Directory with the repository structure.
#' @param lib_site Directory with the R library.
#' @export
installRepoToLibrary <- function(repo_dir, lib_site) {
  repo_packages <- repoPackages(repo_dir)
  already_installed <- installed.packages(lib.loc = lib_site)[, c("Package", "Version")]
  already_installed <- merge(repo_packages, already_installed)$Package

  repo_path <- paste0("file://", normalizePath(repo_dir))
  dir.create(lib_site, recursive = TRUE, showWarnings = FALSE)
  install.packages(setdiff(repo_packages$Package, already_installed), lib = lib_site,
                   repos = repo_path, type = "source")
}
