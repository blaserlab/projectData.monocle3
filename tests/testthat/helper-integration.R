# Helpers for integration tests against the installed fixture package
# `projectData.monocle3.testdata`, version 0.0.0.9002: three BPCells-backed CDS
# resources registered in its manifest (`cds_bpcells_a`, `cds_bpcells_b` and
# `cds_multiassay`, which also carries logcounts, spliced and ADT/CRISPR
# alternative experiments), one ordinary data frame, and `.rda` placeholders for
# the CDS resources. Later versions of that package dropped some of these
# resources, so the tests skip unless all of them are installed. The fixture
# package is never rebuilt or modified here.
#
# These helpers must not force lazy bindings: catalog and state inspection
# only, no `get()`/`data_get()` of a CDS unless a test intends to open it.

testdata_pkg <- "projectData.monocle3.testdata"
testdata_cds <- c("cds_bpcells_a", "cds_bpcells_b", "cds_multiassay")
testdata_dims <- list(cds_bpcells_a = c(100L, 40L), cds_bpcells_b = c(80L, 30L),
                      cds_multiassay = c(100L, 40L))

skip_if_no_testdata <- function() {
  skip_on_cran()
  for (pkg in c("projectData", testdata_pkg, "monocle3", "BPCells",
                "SummarizedExperiment", "withr")) {
    skip_if_not_installed(pkg)
  }
  extdata <- list.files(system.file("extdata", package = testdata_pkg))
  if (!all(testdata_cds %in% extdata)) {
    skip(paste0("needs ", testdata_pkg, " 0.0.0.9002 (resources ",
                paste(testdata_cds, collapse = ", "), "); installed: ",
                as.character(utils::packageVersion(testdata_pkg))))
  }
}

# Starts from no attached collections, and restores projectData session state
# (attachments, loaders, config) when the calling test finishes.
local_testdata_session <- function(env = parent.frame()) {
  skip_if_no_testdata()
  local_clean_projectData(env = env)
  if (NROW(projectData::data_collections())) {
    projectData::data_detach()
  }
  invisible()
}

# Catalog rows for the fixture package, one per object, without opening any.
testdata_catalog <- function() {
  cat <- projectData::data_catalog()
  cat <- cat[cat$package == testdata_pkg, , drop = FALSE]
  cat[match(unique(cat$object), cat$object), , drop = FALSE]
}

catalog_row <- function(object) {
  cat <- testdata_catalog()
  cat[cat$object == object, , drop = FALSE]
}

# The directory of a restored BPCells matrix. `@dir` is the slot of the
# BPCells `MatrixDir` class; BPCells exports no accessor for it.
bpcells_dir <- function(cds) {
  mat <- SummarizedExperiment::assay(cds, "counts")
  stopifnot(methods::is(mat, "MatrixDir"))
  mat@dir
}

# Dense copy of a small block of a BPCells matrix. BPCells warns (once per 8
# hours) that densifying may use a lot of memory; that is expected for a
# few cells, so only that specific warning is muffled.
dense_block <- function(mat, i = 1:5, j = 1:5) {
  withCallingHandlers(
    as.matrix(mat[i, j]),
    warning = function(w) {
      if (grepl("Converting to a dense matrix", conditionMessage(w), fixed = TRUE)) {
        invokeRestart("muffleWarning")
      }
    }
  )
}

# Installation state of the fixture package: file names and checksums.
snapshot_installed <- function() {
  root <- system.file(package = testdata_pkg)
  files <- list.files(root, recursive = TRUE, all.files = TRUE, full.names = TRUE)
  list(files = sub(root, "", files, fixed = TRUE),
       md5 = unname(tools::md5sum(files)),
       mtime = file.mtime(files))
}

# Runs R code in a fresh process with the same library paths, returning its
# stdout. Used to show behavior that requires nothing else to be loaded.
rscript_output <- function(lines) {
  script <- withr::local_tempfile(fileext = ".R")
  writeLines(lines, script)
  out <- suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"), c("--vanilla", shQuote(script)),
    stdout = TRUE, stderr = TRUE,
    env = paste0("R_LIBS=", paste(.libPaths(), collapse = .Platform$path.sep))
  ))
  out
}
