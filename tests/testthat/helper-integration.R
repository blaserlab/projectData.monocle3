# Helpers for integration tests against the installed fixture package
# `projectData.monocle3.testdata`, version 0.0.0.9004: three BPCells-backed CDS
# resources registered in its manifest (`cds_bpcells_a`, `cds_bpcells_b` and
# `cds_multiassay`, which also carries logcounts, spliced and ADT/CRISPR
# alternative experiments), one ordinary data frame, and `.rda` placeholders for
# the CDS resources. The fixture package is never rebuilt or modified here.
#
# Two families of integration tests, each with its own strictness switch:
#
# * Self-contained end-to-end tests (test-e2e-*.R, helper-synthetic.R) generate
#   their data package with the current implementation and need only the declared
#   runtime dependencies (the Monocle stack and projectData). Switch:
#   PDM3_INTEGRATION_TESTS.
# * Historical compatibility tests (test-historical-*.R) load native resources
#   written by an earlier version, shipped in the installed package
#   `projectData.monocle3.testdata`. Switch: PDM3_HISTORICAL_TESTS.
#
# Each switch takes "true", "false" or nothing:
#
# * ordinary (unset, empty or "false"): the family's tests skip when a
#   prerequisite is missing, so routine checks stay usable without the Monocle
#   stack or the fixture package.
# * strict ("true"): a missing or incompatible prerequisite is an *error* inside
#   the test (class `projectData.monocle3_integration_prerequisite`), which
#   testthat records as a failure, never a skip. Only platform-specific skips
#   made with skip_on_platform() remain, and their reason says so.
#
# The families are independent: strict self-contained tests never need the
# historical fixtures, and a missing fixture package skips (or, with
# PDM3_HISTORICAL_TESTS=true, fails) only the historical tests.
#
# These helpers must not force lazy bindings: catalog and state inspection
# only, no `get()`/`data_get()` of a CDS unless a test intends to open it.

testdata_pkg <- "projectData.monocle3.testdata"
# Fixture identity: a minimum version plus checksums of the two files that hold
# each resource's content. The fixtures are never regenerated, so a later
# version of the fixture package with unchanged resources is accepted.
testdata_min_version <- "0.0.0.9004"
testdata_fingerprint <- c(
  "cds_bpcells_a/file_index.rds" = "d74de557be079aad2cf281104db4ff0c",
  "cds_bpcells_a/cds_object.rds" = "1d2d8a9e61e0ec5066794bcdc37ff55d",
  "cds_bpcells_b/file_index.rds" = "10bec1ffc28db9b32186be5cd51d3c94",
  "cds_bpcells_b/cds_object.rds" = "cc37069fa783a474f401038f994a253a",
  "cds_multiassay/file_index.rds" = "b9464e41673bb24377cd50bd5b6cff76",
  "cds_multiassay/cds_object.rds" = "41bd3ded6bb9053c5262c56d7f3c6299"
)
testdata_cds <- c("cds_bpcells_a", "cds_bpcells_b", "cds_multiassay")
testdata_ordinary <- "ordinary_data"
testdata_dims <- list(cds_bpcells_a = c(100L, 40L), cds_bpcells_b = c(80L, 30L),
                      cds_multiassay = c(100L, 40L))
projectData_min_version <- "0.0.0.9005"
monocle_stack <- c("monocle3", "BPCells", "SingleCellExperiment",
                   "SummarizedExperiment", "withr")

switch_value <- function(name) {
  value <- tolower(trimws(Sys.getenv(name, unset = "")))
  if (value %in% c("", "false")) return(FALSE)
  if (identical(value, "true")) return(TRUE)
  stop(errorCondition(
    sprintf("%s must be \"true\" or unset/\"false\", not \"%s\".", name, value),
    class = "projectData.monocle3_integration_config", call = NULL
  ))
}

# Strict mode of the self-contained end-to-end tests.
integration_mode <- function() switch_value("PDM3_INTEGRATION_TESTS")

# Strict mode of the historical compatibility tests.
historical_mode <- function() switch_value("PDM3_HISTORICAL_TESTS")

# Ordinary mode: skip with every problem named. Strict mode (`strict`): signal an
# error that testthat reports as a failed test; `skip()` is never used for a
# problem. `env_var` only shapes the message.
integration_gate <- function(problems, strict = integration_mode(),
                             env_var = "PDM3_INTEGRATION_TESTS") {
  if (!length(problems)) return(invisible())
  if (strict) {
    stop(errorCondition(
      paste0("Strict integration run (", env_var, "=true) cannot proceed:\n",
             paste0("  - ", problems, collapse = "\n"),
             "\nSee the README section \"Integration tests\"."),
      class = "projectData.monocle3_integration_prerequisite", call = NULL
    ))
  }
  skip(paste(problems, collapse = "; "))
}

historical_gate <- function(problems) {
  if (!length(problems)) return(invisible())
  integration_gate(paste("[historical fixtures]", problems), strict = historical_mode(),
                   env_var = "PDM3_HISTORICAL_TESTS")
}

# Skip only for behavior that genuinely depends on the operating system; in a
# strict run the skip reason states that it is a deliberate platform skip.
skip_on_platform <- function(os, reason) {
  tryCatch(
    testthat::skip_on_os(os),
    skip = function(cnd) {
      testthat::skip(paste0(
        if (integration_mode() || historical_mode()) "[strict integration: platform skip] ",
        "on ", paste(os, collapse = "/"), ": ", reason
      ))
    }
  )
}

# Symbolic links: the tests of the link policy need a platform where links can
# be created and where Sys.readlink() reports them (the package relies on it to
# find links). The capability is probed, not inferred from the operating
# system, so a Windows account that may create links runs the tests. A skip is
# labelled as a platform skip in strict runs.
symlink_problems <- function() {
  dir <- tempfile("pdm3-symlink-probe-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  writeLines("x", file.path(dir, "file"))
  dir.create(file.path(dir, "dir"))
  one <- function(kind, target) {
    link <- file.path(dir, paste0(kind, "_link"))
    made <- tryCatch(isTRUE(suppressWarnings(file.symlink(target, link))), error = function(e) FALSE)
    if (!made) return(sprintf("a %s symbolic link cannot be created", kind))
    if (!nzchar(Sys.readlink(link))) return(sprintf("Sys.readlink() does not report a %s symbolic link", kind))
    character()
  }
  c(one("file", "file"), one("directory", "dir"))
}

skip_if_no_symlinks <- function(problems = cached("symlinks", symlink_problems)) {
  if (length(problems)) {
    skip(paste0(
      if (integration_mode() || historical_mode()) "[strict integration: platform skip] ",
      "symbolic links on ", .Platform$OS.type, ": ", paste(problems, collapse = "; ")
    ))
  }
}

# Skips when symbolic links are unusable, then makes `from` a link to `target`.
make_link <- function(target, from) {
  skip_if_no_symlinks()
  if (!isTRUE(suppressWarnings(file.symlink(target, from)))) {
    stop("could not create a symbolic link from ", from, " to ", target)
  }
  invisible(from)
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

# Ordinary mode only checks that the fixture resources exist; strict mode also
# requires the minimum version, the complete structure and the fixture
# fingerprint (the content checksums of every resource).
installed_testdata_problems <- function(strict = historical_mode(), pkg = testdata_pkg) {
  root <- system.file(package = pkg)
  if (!nzchar(root)) return(sprintf("package '%s' is not installed", pkg))
  installed <- as.character(utils::packageVersion(testdata_pkg))
  extdata <- list.files(file.path(root, "extdata"))
  if (!strict) {
    if (all(testdata_cds %in% extdata)) return(character())
    return(sprintf("needs %s >= %s (resources %s); installed: %s", testdata_pkg, testdata_min_version,
                   paste(testdata_cds, collapse = ", "), installed))
  }
  version <- if (numeric_version(installed) < testdata_min_version) {
    sprintf("%s version >= %s is required; installed: %s", testdata_pkg, testdata_min_version, installed)
  }
  resources <- if (!setequal(extdata, testdata_cds)) {
    sprintf("installed extdata/ must contain exactly %s; found: %s",
            paste(testdata_cds, collapse = ", "), paste(extdata, collapse = ", "))
  }
  indexes <- testdata_cds[!file.exists(file.path(root, "extdata", testdata_cds, "file_index.rds"))]
  index <- if (length(indexes)) {
    paste0("installed resource without file_index.rds: ", paste(indexes, collapse = ", "))
  }
  fingerprint <- if (is.null(resources) && !length(indexes)) {
    found <- tools::md5sum(file.path(root, "extdata", names(testdata_fingerprint)))
    changed <- names(testdata_fingerprint)[!identical_checksums(found, testdata_fingerprint)]
    if (length(changed)) {
      paste0("installed fixture content differs from the historical fixtures (checksum mismatch: ",
             paste(changed, collapse = ", "), "); install the original ", testdata_pkg, " resources")
    }
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
  c(version, resources, index, fingerprint, registered, datasets)
}

identical_checksums <- function(found, expected) {
  unname(found == expected & !is.na(found))
}

# Fixture source tree. Strict mode requires PDM3_TESTDATA_SOURCE; ordinary mode
# also tries a sibling directory of this package.
testdata_source <- function() {
  from_env <- Sys.getenv("PDM3_TESTDATA_SOURCE", unset = "")
  candidates <- c(
    if (nzchar(from_env)) from_env,
    if (!historical_mode()) file.path(dirname(normalizePath(test_path("..", ".."))), testdata_pkg)
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

# Strict mode: the source tree exists, has the expected version and structure, and
# the installed fixture package carries identical resources and manifest.
testdata_source_problems <- function() {
  src <- testdata_source()
  if (is.null(src)) {
    return(sprintf("PDM3_TESTDATA_SOURCE must point to the %s source tree (currently: %s)",
                   testdata_pkg, if (nzchar(Sys.getenv("PDM3_TESTDATA_SOURCE"))) {
                     paste0("\"", Sys.getenv("PDM3_TESTDATA_SOURCE"), "\", which is not that package")
                   } else "unset"))
  }
  if (!nzchar(system.file(package = testdata_pkg))) return(character())
  version <- read.dcf(file.path(src, "DESCRIPTION"), "Version")[[1]]
  # A newer source is accepted: the checks below still require its resources
  # and manifest to be identical to the installed fixtures.
  if (numeric_version(version) < testdata_min_version ||
      utils::packageVersion(testdata_pkg) < testdata_min_version) {
    return(sprintf("fixture source %s is version %s; at least %s is required (installed: %s)",
                   src, version, testdata_min_version, utils::packageVersion(testdata_pkg)))
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

# Everything the self-contained family needs beyond its own fixtures.
self_contained_problems <- function() dependency_problems()

# Everything the historical family needs, reported at once.
historical_problems <- function() {
  c(dependency_problems(), installed_testdata_problems(strict = TRUE), testdata_source_problems())
}

# Prerequisites of tests that use the installed fixture package. Cached per
# mode because the checks are repeated by every test.
integration_cache <- new.env()
cached <- function(key, fn) {
  if (is.null(integration_cache[[key]])) integration_cache[[key]] <- list(value = fn())
  integration_cache[[key]]$value
}

skip_if_no_testdata <- function() {
  if (historical_mode()) {
    historical_gate(cached("testdata_strict", \() c(dependency_problems(),
                                                    installed_testdata_problems(strict = TRUE))))
  } else {
    skip_on_cran()
    historical_gate(c(dependency_problems(), installed_testdata_problems(strict = FALSE)))
  }
}

# Prerequisites of tests that also need the fixture source tree; returns its path.
require_testdata_source <- function() {
  if (historical_mode()) {
    historical_gate(cached("source_strict", testdata_source_problems))
  }
  src <- testdata_source()
  if (is.null(src)) {
    skip(paste("[historical fixtures]", testdata_pkg, "source tree not available (set PDM3_TESTDATA_SOURCE)"))
  }
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
  withr::with_envvar(
    c(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep)),
    suppressWarnings(system2(
      file.path(R.home("bin"), "Rscript"), c("--vanilla", shQuote(script)),
      stdout = TRUE, stderr = TRUE
    ))
  )
}
