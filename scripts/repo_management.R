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

# Utility functions to manage private repo of third party packages.
# See documentation for functions annotated with '@export'.
# Only CRAN and Bioc mirrors are tested.

# This script needs the following packages to function.
# - BiocInstaller
# - devtools
# - digest
# - tools

# TODO: Use tools::package_dependencies to avoid using devtools.

# Options to also download binary archives.
options("BinariesMac" = TRUE)  # Binaries for Mac
options("BinariesWin" = FALSE)  # Binaries for Win
options("RVersions" = c("3.3", "3.4"))  # Binaries for these R versions.

# Factors in unexpected places create problems.
options("stringsAsFactors" = FALSE)

# Returns source archive locations of repos.
srcContribDir <- function() {
  return("/src/contrib")
}

# Returns macOS binary archive locations of repos based on R version.
macContribDir <- function(r_version) {
  if (r_version %in% c("3.1", "3.2", "3.3")) {
    return(paste0("/bin/macosx/mavericks/contrib/", r_version))
  } else {
    return(paste0("/bin/macosx/el-capitan/contrib/", r_version))
  }
}

# Returns windows binary archive locations of repos based on R version.
winContribDir <- function(r_version) {
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
  return((bioc_version == "3.5" && r_version == "3.4") ||
         (bioc_version == "3.4" && r_version == "3.3"))
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
# archived_packages is a data frame with character columns Package and Version.
downloadArchivedPackages <- function(archived_packages, repo_dir, repos) {
  contrib_dir <- file.path(repo_dir, file.path("src", "contrib"))

  failed_packages <- character()
  for (index in seq_len(nrow(archived_packages))) {
    pkg_name <- as.character(archived_packages$Package[index])
    pkg_version <- as.character(archived_packages$Version[index])
    pkg_file <- paste0(pkg_name, "_", pkg_version, ".tar.gz")
    cran_archive_url <- paste0("https://cran.r-project.org/src/contrib/Archive/",
                               pkg_name, "/", pkg_file)
    suppressWarnings(tryCatch(
      download.file(cran_archive_url, file.path(contrib_dir, pkg_file)),
      error = function(e) {
        failed_packages <<- c(pkg_name, failed_packages)
      }))
  }
  if (length(failed_packages) > 0) {
    warning(paste("Failed to download archived packages:", paste(failed_packages, collapse = ", ")))
  }
}

# Gets package SHAs for source archive packages from the repo directory.
packageSHAs <- function(pkgs, repo_dir=".") {
  if (nrow(pkgs) == 0) {
    return(cbind(pkgs, "sha256"=character()))
  }
  pkg_files <-
    file.path(repo_dir, "src", "contrib", paste0(pkgs$Package, "_", pkgs$Version, ".tar.gz"))
  pkg_shas <- sapply(pkg_files, function(filepath) digest::digest(file=filepath, algo="sha256"))
  return(cbind(pkgs, "sha256"=pkg_shas))
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
#' @param deps If FALSE, will not automatically download (unstated) dependencies. See argument
#'        dependencies in \link{install.packages}.
#' @param biocVersion If provided, will use this to get remote repos, else will use repos returned
#'        by \code{getOption("repos")}.
#' @return Data frame containing package name, version and sha256 of the source archive for all
#'         packages added to the repo that were not previously present.
#' @export
addPackagesToRepo <- function(pkgs, versions = NA, repo_dir, deps = NA, bioc_version = NA) {
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

  package_deps <- devtools::package_deps(pkgs, dependencies = deps, type = "source")$package
  implicit_package_deps <- setdiff(package_deps, pkgs)
  implicit_package_deps <- setdiff(implicit_package_deps, repo_packages$Package)

  repos <- getOption("repos")
  if (!is.na(bioc_version)) {
    repos <- BiocInstaller::biocinstallRepos(version = bioc_version)
  }
  packages_available <- as.data.frame(available.packages(repos = repos)[, c("Package", "Version")])

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
  current_packages <- merge(packages_merged, repo_packages)[, "Package"]
  packages_merged <- packages_merged[!(packages_merged$Package %in% current_packages), ]

  # Packages that are requested at their latest version.
  latest_packages_mask <- (packages_merged$Version == packages_merged$Version.available)
  latest_packages <- packages_merged[latest_packages_mask, "Package"]
  downloadLatestPackages(latest_packages, repo_dir, repos)

  archived_packages <- packages_merged[!latest_packages_mask, ]
  downloadArchivedPackages(archived_packages, repo_dir, repos)

  updateRepoIndex(repo_dir)

  packageSHAs(packages_merged[,c("Package", "Version")], repo_dir = repo_dir)
}

#' Adds all deps of a dev package to the repo, if not already present.
#'
#' @param pkg Name of the package directory or tarball.
#' @param repo_dir Directory where the repository structure will be created.
#' @param biocVersion If provided, will use this to get remote repos, else will use repos returned
#'        by \code{getOption("repos")}.
#' @return Same as addPackagesToRepo.
#' @export
addDevPackageDepsToRepo <- function(pkg, repo_dir, bioc_version = NA) {
  repos <- getOption("repos")
  if (!is.na(bioc_version)) {
    repos <- BiocInstaller::biocinstallRepos(version = bioc_version)
  }

  # Also get suggested deps to build vignettes, etc. with dependencies = TRUE.
  deps <- devtools::dev_package_deps(pkg, dependencies = TRUE, repos = repos, type="source")$package
  addPackagesToRepo(pkgs = deps, versions = rep(NA_character_, length(deps)),
                    repo_dir = repo_dir, bioc_version)
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
  bioc_version <- ifelse(requireNamespace("BiocInstaller"), BiocInstaller::biocVersion(), NA)
  addPackagesToRepo(pkgs = pkgs[, "Package"], versions = vers,
                    bioc_version = bioc_version, repo_dir = repo_dir)
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
