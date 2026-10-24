# save_monocle_cds(): automatic BPCells conversion of counts, and the round trip
# of additional assays and alternative experiments. Everything writes only to
# disposable package source trees.

test_that("counts_representation() classifies the supported and unsupported counts", {
  skip_if_no_monocle()
  kind <- function(cds) counts_representation(cds)$kind

  expect_identical(kind(fixture_bpcells_cds()), "bpcells_dir")
  expect_identical(kind(fixture_memory_cds()), "convertible")

  # A lazily subset on-disk matrix is still on disk.
  subset <- fixture_bpcells_cds()[1:50, 1:20]
  expect_s4_class(SummarizedExperiment::assay(subset, "counts"), "MatrixSubset")
  expect_identical(kind(subset), "bpcells_dir")

  # A BPCells matrix held in memory is converted, one in an HDF5 file is not.
  mem <- fixture_memory_cds()
  counts <- cds_fixtures()$human$expected$counts
  as_bp <- function(m) BPCells::convert_matrix_type(as(as(m, "dgCMatrix"), "IterableMatrix"), "double")
  SummarizedExperiment::assay(mem, "counts") <- BPCells::write_matrix_memory(as_bp(counts), compress = FALSE)
  expect_identical(kind(mem), "convertible")
  h5 <- BPCells::write_matrix_hdf5(as_bp(counts), withr::local_tempfile(fileext = ".h5"), "m")
  SummarizedExperiment::assay(mem, "counts") <- h5
  expect_identical(kind(mem), "unsupported")
  expect_match(counts_representation(mem)$reason, "MatrixH5", fixed = TRUE)

  dense_cds <- fixture_memory_cds()
  SummarizedExperiment::assay(dense_cds, "counts") <- counts
  expect_identical(kind(dense_cds), "unsupported")
  expect_match(counts_representation(dense_cds)$reason, "'matrix'", fixed = TRUE)
})

test_that("an in-memory CDS is saved without a conversion argument and reloads BPCells-backed", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  cds <- fixture_memory_cds()
  expect_false(methods::is(SummarizedExperiment::assay(cds, "counts"), "IterableMatrix"))

  out <- save_quiet(cds, "ds", pkg)

  expect_length(out$warnings, 0L)
  expect_true(dir.exists(file.path(pkg, "inst", "extdata", "ds", "bpcells_matrix_dir")))
  restored <- open_saved(pkg, "ds")
  expect_s4_class(SummarizedExperiment::assay(restored, "counts"), "MatrixDir")
  expect_identical(counts_representation(restored)$kind, "bpcells_dir")
  expect_identical(dimnames(restored), dimnames(cds))
  expect_equal(unname(cds_counts(restored)), unname(cds_counts(cds)))
})

test_that("an already BPCells-backed CDS is saved without reconversion, keeping values and identifiers", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  cds <- fixture_bpcells_cds()
  testthat::local_mocked_bindings(
    convert_counts_to_bpcells = function(cds, fail) stop("conversion must not be called")
  )

  save_quiet(cds, "ds", pkg)

  restored <- open_saved(pkg, "ds")
  expect_s4_class(SummarizedExperiment::assay(restored, "counts"), "MatrixDir")
  expect_identical(dimnames(restored), dimnames(cds))
  expect_equal(unname(cds_counts(restored)), unname(cds_counts(cds)))
})

test_that("a lazily subset on-disk CDS is saved without reconversion", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  cds <- fixture_bpcells_cds()[1:50, 1:20]
  testthat::local_mocked_bindings(
    convert_counts_to_bpcells = function(cds, fail) stop("conversion must not be called")
  )

  save_quiet(cds, "ds", pkg)

  restored <- open_saved(pkg, "ds")
  expect_identical(dimnames(restored), dimnames(cds))
  expect_equal(unname(cds_counts(restored)), unname(cds_counts(cds)))
})

test_that("a BPCells matrix held in memory is converted to an on-disk matrix", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  cds <- fixture_memory_cds()
  counts <- cds_fixtures()$human$expected$counts
  SummarizedExperiment::assay(cds, "counts") <- BPCells::write_matrix_memory(
    BPCells::convert_matrix_type(as(as(counts, "dgCMatrix"), "IterableMatrix"), "double"),
    compress = FALSE
  )

  save_quiet(cds, "ds", pkg)

  restored <- open_saved(pkg, "ds")
  expect_s4_class(SummarizedExperiment::assay(restored, "counts"), "MatrixDir")
  expect_equal(unname(cds_counts(restored)), unname(counts))
})

for (backing in c("memory", "bpcells")) {
  test_that(paste("additional assays and alternative experiments survive,", backing, "counts"), {
    skip_if_no_monocle()
    pkg <- new_save_pkg()
    cds <- fixture_multiassay_cds(backing)
    snapshot <- cds

    out <- save_quiet(cds, "ds", pkg)

    expect_length(out$warnings, 0L)
    expect_identical(cds, snapshot)
    restored <- open_saved(pkg, "ds")
    expect_s4_class(SummarizedExperiment::assay(restored, "counts"), "MatrixDir")
    expect_true(all(c("logcounts", "spliced") %in% SummarizedExperiment::assayNames(restored)))
    expect_identical(SingleCellExperiment::altExpNames(restored), c("ADT", "CRISPR"))
    expect_round_trip_equal(cds, restored)
    # Reductions and metadata come along as well.
    expect_equal(SingleCellExperiment::reducedDims(restored)$UMAP,
                 SingleCellExperiment::reducedDims(cds)$UMAP, ignore_attr = TRUE)
    expect_equal(as.data.frame(SummarizedExperiment::colData(restored))[, c("group", "n")],
                 as.data.frame(SummarizedExperiment::colData(cds))[, c("group", "n")],
                 ignore_attr = TRUE)
  })
}

test_that("the converted copy, not the caller's CDS, carries counts_row_order", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  cds <- fixture_multiassay_cds("memory")
  # The fixture was derived from a BPCells CDS and still carries a stale one.
  SummarizedExperiment::assay(cds, "counts_row_order") <- NULL
  expect_false("counts_row_order" %in% SummarizedExperiment::assayNames(cds))

  save_quiet(cds, "ds", pkg)

  expect_false("counts_row_order" %in% SummarizedExperiment::assayNames(cds))
  restored <- open_saved(pkg, "ds")
  # counts_row_order is derived, so it is not required to be in the original;
  # when it is present it must hold the same values as the counts.
  expect_true("counts_row_order" %in% SummarizedExperiment::assayNames(restored))
  expect_equal(dense(SummarizedExperiment::assay(restored, "counts_row_order")),
               dense(SummarizedExperiment::assay(restored, "counts")))
  expect_setequal(biological_assays(restored), biological_assays(cds))
})

test_that("unsupported count representations fail before anything is written", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  before <- file_state(pkg)
  counts <- cds_fixtures()$human$expected$counts
  fails <- function(cds, pattern) {
    expect_error(save_monocle_cds(cds, "ds", pkg), pattern,
                 class = "projectData.monocle3_save_error")
    expect_identical(file_state(pkg), before)
    expect_length(stage_dirs(pkg), 0L)
  }

  dense_cds <- fixture_memory_cds()
  SummarizedExperiment::assay(dense_cds, "counts") <- counts
  fails(dense_cds, "'matrix' matrix")

  h5_cds <- fixture_memory_cds()
  SummarizedExperiment::assay(h5_cds, "counts") <- BPCells::write_matrix_hdf5(
    BPCells::convert_matrix_type(as(as(counts, "dgCMatrix"), "IterableMatrix"), "double"),
    withr::local_tempfile(fileext = ".h5"), "m"
  )
  fails(h5_cds, "MatrixH5")

  skip_if_not_installed("DelayedArray")
  delayed_cds <- fixture_memory_cds()
  SummarizedExperiment::assay(delayed_cds, "counts") <- DelayedArray::DelayedArray(counts)
  fails(delayed_cds, "DelayedMatrix")
})

test_that("a failed conversion or save of an in-memory CDS leaves the package and tempdir alone", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  save_quiet(fixture_bpcells_cds("human"), "ds", pkg)
  before <- file_state(pkg)
  tmp_before <- list.files(tempdir(), pattern = "projectData.monocle3-convert")

  testthat::local_mocked_bindings(
    save_staged_cds = function(cds, directory) stop("disk full")
  )
  expect_error(save_monocle_cds(fixture_memory_cds("mouse"), "ds", pkg, overwrite = TRUE),
               "disk full")
  expect_identical(file_state(pkg), before)
  expect_length(stage_dirs(pkg), 0L)
  expect_identical(list.files(tempdir(), pattern = "projectData.monocle3-convert"), tmp_before)
})

test_that("overwrite protection and commit rollback are unchanged for in-memory CDS objects", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  save_quiet(fixture_memory_cds("human"), "ds", pkg)
  before <- file_state(pkg)

  expect_error(save_monocle_cds(fixture_memory_cds("mouse"), "ds", pkg), "overwrite = TRUE",
               class = "projectData.monocle3_save_error")
  expect_identical(file_state(pkg), before)

  testthat::local_mocked_bindings(
    write_planned_manifest = function(plan, manifest, root) stop("manifest not writable")
  )
  expect_error(save_monocle_cds(fixture_memory_cds("mouse"), "ds", pkg, overwrite = TRUE),
               "previous files were restored")
  expect_identical(file_state(pkg), before)
  expect_length(stage_dirs(pkg), 0L)
  expect_identical(dim(open_saved(pkg, "ds")), dim(fixture_memory_cds("human")))
})
