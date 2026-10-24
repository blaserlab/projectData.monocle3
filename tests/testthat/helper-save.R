# Helpers for the save_monocle_cds() tests. Real CDS objects are restored from
# the fixtures built in helper-fixtures.R; everything destructive happens in
# disposable package source trees.

# A BPCells-backed CDS restored from a fixture, cached for the test run.
# `expected` values of the fixture are in cds_fixtures()[[which]]$expected.
fixture_bpcells_cds <- function(which = "human") {
  key <- paste0("bp_", which)
  if (is.null(fixture_cache[[key]])) {
    dir <- tempfile("pdm3-load-")
    dir.create(dir)
    withr::defer(unlink(dir, recursive = TRUE), envir = testthat::teardown_env())
    matrix_control <- monocle3::set_matrix_control(list(
      matrix_class = "BPCells", matrix_mode = "dir", matrix_path = dir
    ))
    fixture_cache[[key]] <- with_attached("monocle3", suppressMessages(
      monocle3::load_monocle_objects(cds_fixtures()[[which]]$saved,
                                     matrix_control = matrix_control)
    ))
  }
  fixture_cache[[key]]
}

# The same CDS (metadata and reductions included) with in-memory counts.
fixture_memory_cds <- function(which = "human") {
  key <- paste0("mem_", which)
  if (is.null(fixture_cache[[key]])) {
    fixture_cache[[key]] <- with_attached("monocle3", suppressMessages(
      monocle3::convert_counts_matrix(fixture_bpcells_cds(which),
                                      list(matrix_class = "dgCMatrix"))
    ))
  }
  fixture_cache[[key]]
}

# Runs save_monocle_cds() silently, returning the result and the warnings.
save_quiet <- function(...) {
  warnings <- list()
  result <- withCallingHandlers(
    suppressMessages(save_monocle_cds(...)),
    warning = function(w) {
      warnings[[length(warnings) + 1L]] <<- w
      invokeRestart("muffleWarning")
    }
  )
  list(result = result, warnings = warnings)
}

# A data-package source tree with an ordinary dataset in data/.
new_save_pkg <- function(name = "savedata", env = parent.frame()) {
  pkg <- new_pkg_source(name, env = env)
  ordinary_data <- data.frame(letters = letters[1:10])
  add_rda(pkg, "ordinary_data", list(ordinary_data = ordinary_data))
  pkg
}

# Restores a saved resource of a source tree the way the loader does, into a
# disposable work directory.
open_saved <- function(pkg, name, env = parent.frame()) {
  work <- withr::local_tempdir(.local_envir = env)
  open_monocle_cds(
    list(resource = name, objects = name),
    list(source = file.path(pkg, "inst", "extdata", name), work_dir = work),
    list()
  )[[name]]
}

stage_dirs <- function(pkg) {
  list.files(pkg, pattern = "^\\.projectData\\.monocle3-stage", all.files = TRUE)
}

# Loads data/<name>.rda into a fresh environment and returns the object.
load_placeholder <- function(pkg, name) {
  env <- new.env()
  loaded <- load(file.path(pkg, "data", paste0(name, ".rda")), envir = env)
  list(names = loaded, object = env[[name]])
}

save_other_entry <- c(
  "Resource: other_res", "Loader: other::loader", "Source: extdata/other_thing",
  "Objects: other_obj", "Title: Hand-written title"
)

install_source_pkg <- function(pkg, env = parent.frame()) {
  lib <- withr::local_tempdir(.local_envir = env)
  out <- system2(file.path(R.home("bin"), "R"),
                 c("CMD", "INSTALL", "--no-test-load", "-l", shQuote(lib), shQuote(pkg)),
                 stdout = TRUE, stderr = TRUE)
  if (!file.exists(file.path(lib, basename(pkg), "DESCRIPTION"))) {
    stop("installation failed:\n", paste(out, collapse = "\n"))
  }
  lib
}

# A CDS with extra assays and ADT/CRISPR alternative experiments, built on a
# fixture CDS (`base`). Values are deterministic and small.
add_multiassay <- function(base) {
  counts <- cds_fixtures()$human$expected$counts
  SummarizedExperiment::assay(base, "logcounts") <- log1p(counts)
  SummarizedExperiment::assay(base, "spliced") <- Matrix::Matrix(counts * 0.5, sparse = TRUE)

  make_alt <- function(prefix, n_features, seed) {
    withr::with_seed(seed, {
      m <- matrix(rpois(n_features * ncol(base), 4), n_features, ncol(base),
                  dimnames = list(paste0(prefix, seq_len(n_features)), colnames(base)))
    })
    alt <- SingleCellExperiment::SingleCellExperiment(
      assays = list(counts = m, logcounts = log1p(m)),
      rowData = data.frame(row.names = rownames(m), marker = paste0("m_", rownames(m))),
      metadata = list(source = prefix, n = n_features)
    )
    alt
  }
  SingleCellExperiment::altExp(base, "ADT") <- make_alt("adt", 8L, 6154L)
  SingleCellExperiment::altExp(base, "CRISPR") <- make_alt("sg", 5L, 3971L)
  base
}

fixture_multiassay_cds <- function(counts = c("memory", "bpcells")) {
  counts <- match.arg(counts)
  add_multiassay(if (counts == "memory") fixture_memory_cds() else fixture_bpcells_cds())
}

dense <- function(x) unname(as.matrix(x))

# Assay names without monocle's internal, derived counts_row_order.
biological_assays <- function(cds) {
  setdiff(SummarizedExperiment::assayNames(cds), "counts_row_order")
}

expect_alt_exps_equal <- function(original, reloaded) {
  expect_identical(SingleCellExperiment::altExpNames(reloaded),
                   SingleCellExperiment::altExpNames(original))
  for (nm in SingleCellExperiment::altExpNames(original)) {
    a <- SingleCellExperiment::altExp(original, nm)
    b <- SingleCellExperiment::altExp(reloaded, nm)
    expect_identical(dim(b), dim(a))
    expect_identical(dimnames(b), dimnames(a))
    expect_identical(SummarizedExperiment::assayNames(b), SummarizedExperiment::assayNames(a))
    for (assay in SummarizedExperiment::assayNames(a)) {
      expect_equal(dense(SummarizedExperiment::assay(b, assay)),
                   dense(SummarizedExperiment::assay(a, assay)))
    }
    expect_equal(as.data.frame(SummarizedExperiment::rowData(b)),
                 as.data.frame(SummarizedExperiment::rowData(a)))
    expect_identical(S4Vectors::metadata(b), S4Vectors::metadata(a))
  }
}

# The assays that must survive a save and a load, and, when Monocle's
# counts_row_order is present, that it is consistent with the counts.
expect_round_trip_equal <- function(original, reloaded) {
  expect_identical(dimnames(reloaded), dimnames(original))
  expect_setequal(biological_assays(reloaded), biological_assays(original))
  for (assay in setdiff(biological_assays(original), "counts")) {
    expect_equal(dense(SummarizedExperiment::assay(reloaded, assay)),
                 dense(SummarizedExperiment::assay(original, assay)))
  }
  expect_equal(unname(cds_counts(reloaded)), unname(cds_counts(original)))
  if ("counts_row_order" %in% SummarizedExperiment::assayNames(reloaded)) {
    expect_equal(dense(SummarizedExperiment::assay(reloaded, "counts_row_order")),
                 dense(SummarizedExperiment::assay(reloaded, "counts")))
  }
  expect_alt_exps_equal(original, reloaded)
}
