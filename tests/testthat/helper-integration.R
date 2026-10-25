# Helpers for integration tests against the installed fixture package
# `projectData.monocle3.testdata`, version 0.0.0.9004: three BPCells-backed CDS
# resources registered in its manifest (`cds_bpcells_a`, `cds_bpcells_b` and
# `cds_multiassay`, which also carries logcounts, spliced and ADT/CRISPR
# alternative experiments), one ordinary data frame, and `.rda` placeholders for
# the CDS resources. The fixture package is never rebuilt or modified here.
#
# Two modes, selected by the environment variable PDM3_INTEGRATION_TESTS:
#
# * ordinary (unset, empty or "false"): integration tests skip when an optional
#   dependency or the fixture resources are missing, so routine checks stay
#   usable without the Monocle stack.
# * full ("true"): a missing or incompatible prerequisite is an *error* inside
#   the test (class `projectData.monocle3_integration_prerequisite`), which
#   testthat records as a failure, never a skip. Only platform-specific skips
#   made with skip_on_platform() remain, and their reason says so.
#
# These helpers must not force lazy bindings: catalog and state inspection
# only, no `get()`/`data_get()` of a CDS unless a test intends to open it.

testdata_pkg <- "projectData.monocle3.testdata"
testdata_version <- "0.0.0.9004"
testdata_cds <- c("cds_bpcells_a", "cds_bpcells_b", "cds_multiassay")
testdata_ordinary <- "ordinary_data"
testdata_dims <- list(cds_bpcells_a = c(100L, 40L), cds_bpcells_b = c(80L, 30L),
                      cds_multiassay = c(100L, 40L))
projectData_min_version <- "0.0.0.9005"
monocle_stack <- c("monocle3", "BPCells", "SingleCellExperiment",
                   "SummarizedExperiment", "withr")

integration_mode <- function() {
  value <- tolower(trimws(Sys.getenv("PDM3_INTEGRATION_TESTS", unset = "")))
  if (value %in% c("", "false")) return(FALSE)
  if (identical(value, "true")) return(TRUE)
  stop(errorCondition(
    sprintf("PDM3_INTEGRATION_TESTS must be \"true\" or unset/\"false\", not \"%s\".", value),
    class = "projectData.monocle3_integration_config", call = NULL
  ))
}

# Ordinary mode: skip with every problem named. Full mode: signal an error that
# testthat reports as a failed test; `skip()` is never used for a problem.
integration_gate <- function(problems) {
  if (!length(problems)) return(invisible())
  if (integration_mode()) {
    stop(errorCondition(
      paste0("Full integration run (PDM3_INTEGRATION_TESTS=true) cannot proceed:\n",
             paste0("  - ", problems, collapse = "\n"),
             "\nSee the README section \"Full integration run\"."),
      class = "projectData.monocle3_integration_prerequisite", call = NULL
    ))
  }
  skip(paste(problems, collapse = "; "))
}

# Skip only for behavior that genuinely depends on the operating system; in a
# full run the skip reason states that it is a deliberate platform skip.
skip_on_platform <- function(os, reason) {
  tryCatch(
    testthat::skip_on_os(os),
    skip = function(cnd) {
      testthat::skip(paste0(
        if (integration_mode()) "[full integration: platform skip] ",
        "on ", paste(os, collapse = "/"), ": ", reason
      ))
    }
  )
}

missing_packages <- function(pkgs) {
  pkgs <- pkgs[!nzchar(vapply(pkgs, \(p) system.file(package = p), ""))]
  if (length(pkgs)) paste0("package '", pkgs, "' is not installed") else character()
}

dependency_problems <- function(pkgs = c("projectData", monocle_stack)) {
  missing <- missing_packages(pkgs)
  if (length(missing) || !"projectData" %in% pkgs) return(missing)
  if (utils::packageVersion("projectData") < projectData_min_version) {
    return(sprintf("projectData >= %s is required; installed: %s", projectData_min_version,
                   as.character(utils::packageVersion("projectData"))))
  }
  character()
}

# Ordinary mode only checks that the fixture resources exist; full mode also
# requires the expected version and the complete structure.
installed_testdata_problems <- function(strict = integration_mode()) {
  root <- system.file(package = testdata_pkg)
  if (!nzchar(root)) return(sprintf("package '%s' is not installed", testdata_pkg))
  installed <- as.character(utils::packageVersion(testdata_pkg))
  extdata <- list.files(file.path(root, "extdata"))
  if (!strict) {
    if (all(testdata_cds %in% extdata)) return(character())
    return(sprintf("needs %s %s (resources %s); installed: %s", testdata_pkg, testdata_version,
                   paste(testdata_cds, collapse = ", "), installed))
  }
  version <- if (!identical(installed, testdata_version)) {
    sprintf("%s version %s is required; installed: %s", testdata_pkg, testdata_version, installed)
  }
  resources <- if (!setequal(extdata, testdata_cds)) {
    sprintf("installed extdata/ must contain exactly %s; found: %s",
            paste(testdata_cds, collapse = ", "), paste(extdata, collapse = ", "))
  }
  indexes <- testdata_cds[!file.exists(file.path(root, "extdata", testdata_cds, "file_index.rds"))]
  index <- if (length(indexes)) {
    paste0("installed resource without file_index.rds: ", paste(indexes, collapse = ", "))
  }
  manifest <- file.path(root, "projectData", "manifest.dcf")
  registered <- if (!file.exists(manifest)) {
    "installed package has no projectData/manifest.dcf"
  } else {
    entries <- as.data.frame(read.dcf(manifest), stringsAsFactors = FALSE)
    entries <- entries[!is.na(entries$Resource), , drop = FALSE]
    if (!setequal(entries$Resource, testdata_cds) ||
        !all(entries$Loader == "projectData.monocle3::cds")) {
      paste0("installed manifest must register exactly ", paste(testdata_cds, collapse = ", "),
             " with loader projectData.monocle3::cds")
    }
  }
  items <- utils::data(package = testdata_pkg)$results[, "Item"]
  datasets <- if (!setequal(items, c(testdata_cds, testdata_ordinary))) {
    paste0("installed data() items must be exactly ",
           paste(c(testdata_cds, testdata_ordinary), collapse = ", "))
  }
  c(version, resources, index, registered, datasets)
}

# Fixture source tree. Full mode requires PDM3_TESTDATA_SOURCE; ordinary mode
# also tries a sibling directory of this package.
testdata_source <- function() {
  from_env <- Sys.getenv("PDM3_TESTDATA_SOURCE", unset = "")
  candidates <- c(
    if (nzchar(from_env)) from_env,
    if (!integration_mode()) file.path(dirname(normalizePath(test_path("..", ".."))), testdata_pkg)
  )
  for (path in candidates) {
    desc <- file.path(path, "DESCRIPTION")
    if (file.exists(desc) && identical(read.dcf(desc, "Package")[[1]], testdata_pkg) &&
        dir.exists(file.path(path, "inst", "extdata"))) {
      return(normalizePath(path))
    }
  }
  NULL
}

tree_md5 <- function(dir) {
  files <- list.files(dir, recursive = TRUE, all.files = TRUE)
  stats::setNames(unname(tools::md5sum(file.path(dir, files))), files)
}

# Full mode: the source tree exists, has the expected version and structure, and
# the installed fixture package carries identical resources and manifest.
testdata_source_problems <- function() {
  src <- testdata_source()
  if (is.null(src)) {
    return(sprintf("PDM3_TESTDATA_SOURCE must point to the %s source tree (currently: %s)",
                   testdata_pkg, if (nzchar(Sys.getenv("PDM3_TESTDATA_SOURCE"))) {
                     paste0("\"", Sys.getenv("PDM3_TESTDATA_SOURCE"), "\", which is not that package")
                   } else "unset"))
  }
  version <- read.dcf(file.path(src, "DESCRIPTION"), "Version")[[1]]
  if (!identical(version, testdata_version)) {
    return(sprintf("fixture source %s is version %s; %s is required", src, version, testdata_version))
  }
  extdata <- list.files(file.path(src, "inst", "extdata"))
  if (!setequal(extdata, testdata_cds)) {
    return(sprintf("fixture source inst/extdata must contain exactly %s; found: %s",
                   paste(testdata_cds, collapse = ", "), paste(extdata, collapse = ", ")))
  }
  root <- system.file(package = testdata_pkg)
  if (!nzchar(root)) return(character())
  differs <- function(a, b) !identical(tree_md5(a), tree_md5(b))
  c(
    if (differs(file.path(src, "inst", "extdata"), file.path(root, "extdata"))) {
      sprintf("installed %s extdata/ differs from the source %s; reinstall from that source", testdata_pkg, src)
    },
    if (differs(file.path(src, "inst", "projectData"), file.path(root, "projectData"))) {
      sprintf("installed %s manifest differs from the source %s; reinstall from that source", testdata_pkg, src)
    }
  )
}

full_run_problems <- function() {
  c(dependency_problems(), installed_testdata_problems(strict = TRUE),
    testdata_source_problems())
}

# Prerequisites of tests that use the installed fixture package. Cached per
# mode because the checks are repeated by every test.
integration_cache <- new.env()
cached <- function(key, fn) {
  if (is.null(integration_cache[[key]])) integration_cache[[key]] <- list(value = fn())
  integration_cache[[key]]$value
}

skip_if_no_testdata <- function() {
  if (integration_mode()) {
    integration_gate(cached("testdata_full", \() c(dependency_problems(),
                                                  installed_testdata_problems(strict = TRUE))))
  } else {
    skip_on_cran()
    integration_gate(c(dependency_problems(), installed_testdata_problems(strict = FALSE)))
  }
}

# Prerequisites of tests that also need the fixture source tree; returns its path.
require_testdata_source <- function() {
  if (integration_mode()) {
    integration_gate(cached("source_full", testdata_source_problems))
  }
  src <- testdata_source()
  if (is.null(src)) skip(paste(testdata_pkg, "source tree not available (set PDM3_TESTDATA_SOURCE)"))
  src
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
