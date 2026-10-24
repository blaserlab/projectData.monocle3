# Unsupported externally backed secondary assays are rejected before anything
# is written; supported multi-assay objects still round-trip.

# A small BPCells matrix directory, independent of any Monocle-managed counts.
external_bpcells <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  counts <- cds_fixtures()$human$expected$counts
  BPCells::write_matrix_dir(
    as(as(Matrix::Matrix(counts, sparse = TRUE), "dgCMatrix"), "IterableMatrix"),
    file.path(dir, "alt")
  )
}

# An ADT-style experiment whose counts assay is BPCells-backed.
disk_backed_alt <- function(base, env = parent.frame()) {
  m <- matrix(as.numeric(seq_len(6L * ncol(base)) %% 7L), 6L, ncol(base),
              dimnames = list(paste0("adt", 1:6), colnames(base)))
  bp <- BPCells::write_matrix_dir(
    as(as(Matrix::Matrix(m, sparse = TRUE), "dgCMatrix"), "IterableMatrix"),
    file.path(withr::local_tempdir(.local_envir = env), "adt")
  )
  alt <- SingleCellExperiment::SingleCellExperiment(assays = list(counts = m))
  SummarizedExperiment::assay(alt, "counts", withDimnames = FALSE) <- bp
  alt
}

expect_rejected <- function(cds, pkg, locations, ..., overwrite = FALSE) {
  before <- file_state(pkg)
  err <- expect_error(
    suppressMessages(save_monocle_cds(cds, "ds", pkg, overwrite = overwrite)),
    class = "projectData.monocle3_external_assay"
  )
  expect_s3_class(err, "projectData.monocle3_save_error")
  msg <- conditionMessage(err)
  for (loc in locations) expect_match(msg, loc, fixed = TRUE)
  expect_match(msg, "not preserved by Monocle's native serialization", fixed = TRUE)
  expect_match(msg, "in-memory", fixed = TRUE)
  expect_identical(file_state(pkg), before)
  expect_length(stage_dirs(pkg), 0L)
  invisible(err)
}

test_that("external_assays() classifies assays without reading values", {
  skip_if_no_monocle()
  cds <- fixture_bpcells_cds()
  expect_equal(nrow(external_assays(cds)), 0L)

  SummarizedExperiment::assay(cds, "logcounts") <- log1p(cds_fixtures()$human$expected$counts)
  expect_equal(nrow(external_assays(cds)), 0L)

  SummarizedExperiment::assay(cds, "spliced") <- external_bpcells()
  found <- external_assays(cds)
  expect_identical(found$location, "assay 'spliced'")
  expect_match(found$backing, "MatrixDir")

  # A lazily transformed chain is still judged by its leaves.
  SummarizedExperiment::assay(cds, "spliced") <- external_bpcells() * 2
  expect_identical(external_assays(cds)$location, "assay 'spliced'")
})

test_that("a BPCells-backed secondary assay is rejected; no output is created", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  cds <- fixture_bpcells_cds()
  SummarizedExperiment::assay(cds, "spliced") <- external_bpcells()

  expect_rejected(cds, pkg, "assay 'spliced'")
  expect_false(dir.exists(file.path(pkg, "inst")))
  expect_false(file.exists(file.path(pkg, "data", "ds.rda")))
})

test_that("a rejected save with overwrite = TRUE leaves existing resources untouched", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  save_quiet(fixture_bpcells_cds(), "ds", pkg)
  save_quiet(fixture_memory_cds("mouse"), "other", pkg)
  before <- file_state(pkg)

  cds <- fixture_bpcells_cds()
  SummarizedExperiment::assay(cds, "spliced") <- external_bpcells()
  expect_rejected(cds, pkg, "assay 'spliced'", overwrite = TRUE)
  expect_identical(file_state(pkg), before)
  # The resource that was there is still intact and valid.
  expect_s4_class(SummarizedExperiment::assay(open_saved(pkg, "ds"), "counts"), "MatrixDir")
})

test_that("a disk-backed altExp assay is rejected with its location", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  cds <- fixture_bpcells_cds()
  SingleCellExperiment::altExp(cds, "ADT") <- disk_backed_alt(cds)
  expect_rejected(cds, pkg, "altExp 'ADT' / assay 'counts'")
})

test_that("nested altExps are inspected recursively and report the full path", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  cds <- fixture_bpcells_cds()
  inner <- disk_backed_alt(cds)
  outer <- SingleCellExperiment::SingleCellExperiment(
    assays = list(counts = matrix(1, 2L, ncol(cds),
                                  dimnames = list(c("a", "b"), colnames(cds))))
  )
  SingleCellExperiment::altExp(outer, "normalized") <- inner
  SingleCellExperiment::altExp(cds, "ADT") <- outer

  expect_identical(external_assays(cds)$location,
                   "altExp 'ADT' / altExp 'normalized' / assay 'counts'")
  expect_rejected(cds, pkg, "altExp 'ADT' / altExp 'normalized' / assay 'counts'")
})

test_that("all offending assays are reported together", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  cds <- fixture_bpcells_cds()
  SummarizedExperiment::assay(cds, "spliced") <- external_bpcells()
  SingleCellExperiment::altExp(cds, "ADT") <- disk_backed_alt(cds)
  expect_rejected(cds, pkg, c("assay 'spliced'", "altExp 'ADT' / assay 'counts'"))
})

test_that("a nested altExp with an in-memory counts assay is not rejected", {
  skip_if_no_monocle()
  cds <- fixture_bpcells_cds()
  # The counts_row_order exemption is for the main CDS only; in-memory is fine anywhere.
  alt <- SingleCellExperiment::SingleCellExperiment(assays = list(
    counts = matrix(1, 2L, ncol(cds), dimnames = list(c("a", "b"), colnames(cds))),
    counts_row_order = matrix(1, 2L, ncol(cds), dimnames = list(c("a", "b"), colnames(cds)))
  ))
  SingleCellExperiment::altExp(cds, "ADT") <- alt
  expect_equal(nrow(external_assays(cds)), 0L)
  SummarizedExperiment::assay(alt, "counts_row_order", withDimnames = FALSE) <- external_bpcells()[1:2, ]
  SingleCellExperiment::altExp(cds, "ADT") <- alt
  expect_identical(external_assays(cds)$location, "altExp 'ADT' / assay 'counts_row_order'")
})

test_that("a supported multi-assay CDS saves and round-trips (BPCells counts)", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  cds <- fixture_multiassay_cds("bpcells")
  expect_true(all(c("logcounts", "spliced") %in% SummarizedExperiment::assayNames(cds)))
  expect_identical(SingleCellExperiment::altExpNames(cds), c("ADT", "CRISPR"))

  out <- save_quiet(cds, "ds", pkg)
  expect_length(out$warnings, 0L)
  restored <- open_saved(pkg, "ds")
  expect_s4_class(SummarizedExperiment::assay(restored, "counts"), "MatrixDir")
  expect_true("counts_row_order" %in% SummarizedExperiment::assayNames(restored))
  expect_round_trip_equal(cds, restored)
})

test_that("in-memory counts are converted automatically while secondary assays and altExps survive", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  cds <- fixture_multiassay_cds("memory")
  expect_false(methods::is(SummarizedExperiment::assay(cds, "counts"), "IterableMatrix"))

  out <- save_quiet(cds, "ds", pkg)
  expect_length(out$warnings, 0L)
  # The caller's object is untouched.
  expect_false(methods::is(SummarizedExperiment::assay(cds, "counts"), "IterableMatrix"))

  restored <- open_saved(pkg, "ds")
  expect_s4_class(SummarizedExperiment::assay(restored, "counts"), "MatrixDir")
  for (a in c("logcounts", "spliced")) {
    expect_false(methods::is(SummarizedExperiment::assay(restored, a), "IterableMatrix"))
  }
  expect_round_trip_equal(cds, restored)
})

test_that("rejected objects are not modified", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  cds <- fixture_bpcells_cds()
  SummarizedExperiment::assay(cds, "spliced") <- external_bpcells()
  SingleCellExperiment::altExp(cds, "ADT") <- disk_backed_alt(cds)
  snapshot <- cds
  expect_error(suppressMessages(save_monocle_cds(cds, "ds", pkg)),
               class = "projectData.monocle3_external_assay")
  expect_identical(cds, snapshot)
  expect_identical(SummarizedExperiment::assayNames(cds), SummarizedExperiment::assayNames(snapshot))
})

test_that("a BPCells wrapper around an R matrix is conservatively refused", {
  skip_if_no_monocle()
  cds <- fixture_bpcells_cds()
  SummarizedExperiment::assay(cds, "mm") <-
    as(as(cds_fixtures()$human$expected$counts, "dgCMatrix"), "IterableMatrix")
  expect_identical(external_assays(cds)$location, "assay 'mm'")
})
