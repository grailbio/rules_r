Razel scripts
=============

These are a crude collection of functions to help generate `BUILD` files for R
packages, and `WORKSPACE` rules for external R packages. They may become part
of a package in the future.

Source these scripts and then call the functions as you need. Please use with
caution.

## razel.R

Functions in this script help generate `BUILD` files for your own package and
for packages from external repositories like CRAN and Bioc.

For your own package, use the function `buildify` directly. For external
packages, you will have to first create a local repository containing all the
packages that you want included in your build system, and then call
`buildifyRepo` and `generateWorkspaceFile`. See
[repo_management.R](#repo_managementr) for managing a local repo of your package
dependencies.

```R
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
buildify <- function(pkg_directory = ".", no_test_rules = TRUE) ...


#' Function to generate BUILD files for all packages in a local repo.
#'
#' @param local_repo_dir Local copy of the repository.
#' @param build_file_prefix Prefix that will be prepended to the package name
#'        to generate the BUILD file name.
#' @param build_file_suffix Suffix that will be appended to the package name
#'        to generate the BUILD file name.
#' @param overwrite Recreate the build file if it exists already.
buildifyRepo <- function(local_repo_dir, build_file_prefix = "BUILD.",
                         build_file_suffix = "", overwrite = FALSE) ...


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
                                  bioc_version = NA_character_) ...
```

## repo_management.R

Functions in this script help manage a local repo of your package dependencies
so the razel script functions can inspect the contents of the packages, and
generate BUILD files for them.

You also have the option of downloading binary packages to this repo in case
you want to use this local repo as a functional mirror for macOS and windows.

```R
# Options to also download binary archives.
options("BinariesMac" = TRUE)  # Binaries for Mac
options("BinariesWin" = FALSE)  # Binaries for Win
options("RVersions" = c("3.3", "3.4"))  # Binaries for these R versions.


#' Already downloaded source archive packages in the repo.
#'
#' @param repo_dir Directory with the repository structure.
#' @return Data frame containing package name and version.
#' @export
repoPackages <- function(repo_dir) ...


#' Update the index of a repo after manual addition or deletion of packages.
#'
#' @param repo_dir Directory with the repository structure.
#' @export
updateRepoIndex <- function(repo_dir) ...


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
addPackagesToRepo <- function(pkgs, versions = NA, repo_dir, deps = NA, bioc_version = NA) ...


#' Adds all deps of a dev package to the repo, if not already present.
#'
#' @param pkg Name of the package directory or tarball.
#' @param repo_dir Directory where the repository structure will be created.
#' @param biocVersion If provided, will use this to get remote repos, else will use repos returned
#'        by \code{getOption("repos")}.
#' @return Same as addPackagesToRepo.
#' @export
addDevPackageDepsToRepo <- function(pkg, repo_dir, bioc_version = NA) ...


#' Dumps the packages installed in this library into a repo structure.
#'
#' @param repo_dir Directory where the repository structure will be created.
#' @param keep_versions Whether to download the same versions of packages as in this library.
#' @return Same as addPackagesToRepo.
#' @export
cloneLibraryToRepo <- function(repo_dir, keep_versions = TRUE) ...


#' Install the packages in the repo to a given library, if not already installed.
#'
#' Replaces packages where versions are different.
#' @param repo_dir Directory with the repository structure.
#' @param lib_site Directory with the R library.
#' @export
installRepoToLibrary <- function(repo_dir, lib_site) ...
```
