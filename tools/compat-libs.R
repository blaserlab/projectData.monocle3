# Builds the alternative dependency libraries used by tools/compat-matrix.R.
#
#   Rscript tools/compat-libs.R                 # every library not yet built
#   Rscript tools/compat-libs.R bpcells_030     # one library
#
# Each library holds only the packages that differ from the default library;
# everything else (monocle3, the Bioconductor packages, Matrix, testthat, ...) is
# found on the normal library path, so a library is small and quick to rebuild.
# Sources come from CRAN, the CRAN archive and GitHub tags or commits; nothing is
# installed into the default library. A library that already exists is skipped;
# delete its directory to rebuild it. BPCells compiles C++ (it needs the HDF5
# headers: libhdf5-dev on Debian/Ubuntu, `brew install hdf5 pkg-config` on macOS)
# and takes several minutes.
#
# Edit `libs` when a dependency is released: the matrix is meant to stay small.

root <- normalizePath(
  if (file.exists("DESCRIPTION")) "." else file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), ".."),
  winslash = "/"
)

# A CRAN release moves from src/contrib to the archive when it is superseded.
cran_source <- function(pkg, version) {
  c(sprintf("https://cloud.r-project.org/src/contrib/%s_%s.tar.gz", pkg, version),
    sprintf("https://cloud.r-project.org/src/contrib/Archive/%s/%s_%s.tar.gz", pkg, pkg, version))
}
github_tag <- function(repo, tag) sprintf("https://github.com/%s/archive/refs/tags/%s.tar.gz", repo, tag)
github_ref <- function(repo, ref) sprintf("https://github.com/%s/archive/%s.tar.gz", repo, ref)

# Install steps are run in order, each with the library in front of the path.
libs <- list(
  projectdata_cran = list(
    list(pkg = "projectData", url = cran_source("projectData", "0.1.0"))
  ),
  # The development version of the Issue 3 validation (the declared minimum is 0.0.0.9008).
  projectdata_9008 = list(
    list(pkg = "projectData", url = github_ref("blaserlab/projectData", "31ff41524e8f6602751d2e60cd05e73479fc2ebc"))
  ),
  bpcells_030 = list(
    list(pkg = "BPCells", url = github_tag("bnprks/BPCells", "v0.3.0"), subdir = "r")
  ),
  bpcells_031 = list(
    list(pkg = "BPCells", url = github_tag("bnprks/BPCells", "v0.3.1"), subdir = "r")
  ),
  bpcells_main = list(
    list(pkg = "BPCells", url = github_ref("bnprks/BPCells", "main"), subdir = "r")
  )
)

install_step <- function(step, lib) {
  dir <- tempfile("compat-src-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  tarball <- file.path(dir, "src.tar.gz")
  ok <- FALSE
  for (url in step$url) {
    ok <- tryCatch(utils::download.file(url, tarball, mode = "wb", quiet = TRUE) == 0,
                   error = function(e) FALSE, warning = function(w) FALSE)
    if (ok) break
  }
  if (!ok) stop("could not download ", paste(step$url, collapse = " or "))
  utils::untar(tarball, exdir = dir)
  top <- setdiff(list.dirs(dir, recursive = FALSE), dir)
  # The package directory must be named after the package (GitHub archives are
  # named <repo>-<tag>, with the R package in a subdirectory).
  pkg_dir <- if (is.null(step$subdir)) top[1] else file.path(top[1], step$subdir)
  target <- file.path(dir, step$pkg)
  if (!identical(normalizePath(pkg_dir), normalizePath(target, mustWork = FALSE))) {
    file.rename(pkg_dir, target)
  }
  # Dependencies not installed anywhere on the path are installed into `lib`.
  desc <- read.dcf(file.path(target, "DESCRIPTION"), c("Depends", "Imports", "LinkingTo"))
  deps <- unlist(strsplit(gsub("\\([^)]*\\)|\\s", "", paste(desc[!is.na(desc)], collapse = ",")), ","))
  deps <- setdiff(deps[nzchar(deps)], c("R", rownames(utils::installed.packages(priority = "base"))))
  missing <- deps[!vapply(deps, requireNamespace, NA, quietly = TRUE)]
  if (length(missing)) utils::install.packages(missing, lib = lib)
  utils::install.packages(target, repos = NULL, type = "source", lib = lib)
  stopifnot(requireNamespace(step$pkg, lib.loc = lib, quietly = TRUE))
}

args <- commandArgs(trailingOnly = TRUE)
selected <- if (length(args)) args else names(libs)
unknown <- setdiff(selected, names(libs))
if (length(unknown)) stop("unknown library: ", paste(unknown, collapse = ", "))

for (name in selected) {
  lib <- file.path(root, "tools", "compat-libs", name)
  if (dir.exists(lib) && length(list.files(lib))) {
    message("== ", name, ": exists, skipped")
    next
  }
  message("== ", name)
  dir.create(lib, recursive = TRUE, showWarnings = FALSE)
  .libPaths(c(lib, .libPaths()))
  ok <- tryCatch({
    for (step in libs[[name]]) install_step(step, lib)
    TRUE
  }, error = function(e) {
    message("FAILED: ", conditionMessage(e))
    FALSE
  })
  if (!ok) {
    unlink(lib, recursive = TRUE)
    quit(status = 1)
  }
  .libPaths(.libPaths()[-1])
}
