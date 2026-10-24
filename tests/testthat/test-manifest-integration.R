# Fixture package: projectData.monocle3.testdata (see helper-integration.R).

test_that("A: the .rda placeholder is not a CDS and needs neither projectData nor the adapter", {
  skip_if_no_testdata()
  env <- new.env()
  search_before <- search()

  loaded <- utils::data("cds_bpcells_a", package = testdata_pkg, envir = env)

  expect_identical(loaded, "cds_bpcells_a")
  placeholder <- get("cds_bpcells_a", envir = env)
  expect_type(placeholder, "character")
  expect_false(methods::is(placeholder, "cell_data_set"))
  expect_identical(search(), search_before)

  # A fresh process shows no other package is needed to read the placeholder.
  out <- rscript_output(c(
    sprintf("e <- new.env(); utils::data('cds_bpcells_a', package = '%s', envir = e)", testdata_pkg),
    "p <- get('cds_bpcells_a', envir = e)",
    "cat('character:', is.character(p), '\\n')",
    "cat('projectData loaded:', 'projectData' %in% loadedNamespaces(), '\\n')",
    "cat('adapter loaded:', 'projectData.monocle3' %in% loadedNamespaces(), '\\n')",
    "cat('monocle3 loaded:', 'monocle3' %in% loadedNamespaces(), '\\n')"
  ))
  expect_identical(
    out,
    c("character: TRUE ", "projectData loaded: FALSE ",
      "adapter loaded: FALSE ", "monocle3 loaded: FALSE ")
  )
})

test_that("A: a placeholder in a test environment does not affect manifest resolution", {
  local_testdata_session()
  env <- new.env()
  utils::data("cds_bpcells_a", package = testdata_pkg, envir = env)
  expect_false(methods::is(get("cds_bpcells_a", envir = env), "cell_data_set"))

  rm("cds_bpcells_a", envir = env)
  cds <- projectData::data_get("cds_bpcells_a", package = testdata_pkg)

  expect_s4_class(cds, "cell_data_set")
  expect_identical(dim(cds), testdata_dims$cds_bpcells_a)
  expect_false(exists("cds_bpcells_a", envir = env, inherits = FALSE))
})

test_that("B: the CDS resources resolve from the manifest through the adapter, not the dataset loader", {
  local_testdata_session()
  projectData::data_attach(testdata_pkg)

  cat <- testdata_catalog()
  expect_setequal(cat$object, c(testdata_cds, "ordinary_data"))
  origin <- stats::setNames(cat$origin, cat$object)
  expect_identical(origin[["cds_bpcells_a"]], "manifest")
  expect_identical(origin[["cds_bpcells_b"]], "manifest")
  expect_identical(origin[["cds_multiassay"]], "manifest")
  expect_identical(origin[["ordinary_data"]], "index")

  loader <- stats::setNames(cat$loader, cat$object)
  expect_identical(loader[["cds_bpcells_a"]], "projectData.monocle3::cds")
  expect_identical(loader[["cds_bpcells_b"]], "projectData.monocle3::cds")
  expect_identical(loader[["cds_multiassay"]], "projectData.monocle3::cds")
  expect_identical(loader[["ordinary_data"]], "projectData::dataset")
  expect_identical(
    stats::setNames(cat$source, cat$object)[testdata_cds],
    stats::setNames(paste0("extdata/", testdata_cds), testdata_cds)
  )
  expect_identical(
    stats::setNames(cat$recorded_class, cat$object)[testdata_cds],
    stats::setNames(rep("cell_data_set", 3), testdata_cds)
  )
})

test_that("B: opening a CDS through the catalog's loader yields a CDS, and the catalog then reports it disk-backed", {
  local_testdata_session()
  projectData::data_attach(testdata_pkg)

  cds <- projectData::data_get("cds_bpcells_a")

  # A dataset-loader resolution would have returned the placeholder string.
  expect_s4_class(cds, "cell_data_set")
  row <- catalog_row("cds_bpcells_a")
  expect_identical(row$loader_status, "registered")
  expect_identical(row$storage, "disk-backed")
  expect_identical(row$state, "ready")
  expect_identical(catalog_row("cds_bpcells_b")$state, "unopened")
})

test_that("H: ordinary_data still loads through the standard dataset loader", {
  local_testdata_session()
  counter <- local_open_counter()
  expected <- data.frame(letters = letters[1:10])

  projectData::data_attach(testdata_pkg)
  expect_identical(catalog_row("ordinary_data")$loader, "projectData::dataset")
  expect_identical(projectData::data_get("ordinary_data"), expected)
  expect_identical(
    get("ordinary_data", envir = as.environment("projectData:data")),
    expected
  )
  # Only the dataset was opened, and no CDS was touched.
  expect_identical(counter$log, paste(testdata_pkg, "ordinary_data", sep = "/"))

  env <- new.env()
  utils::data("ordinary_data", package = testdata_pkg, envir = env)
  expect_identical(get("ordinary_data", envir = env), expected)
})

test_that("I: cds_multiassay keeps its extra assays and alternative experiments through the adapter", {
  local_testdata_session()

  cds <- projectData::data_get("cds_multiassay", package = testdata_pkg)

  expect_s4_class(cds, "cell_data_set")
  expect_identical(dim(cds), testdata_dims$cds_multiassay)
  expect_s4_class(SummarizedExperiment::assay(cds, "counts"), "MatrixDir")
  assays <- SummarizedExperiment::assayNames(cds)
  expect_true(all(c("counts", "logcounts", "spliced") %in% assays))
  expect_setequal(SingleCellExperiment::altExpNames(cds), c("ADT", "CRISPR"))

  counts <- dense_block(SummarizedExperiment::assay(cds, "counts"), 1:10, 1:10)
  for (nm in c("logcounts", "spliced")) {
    a <- SummarizedExperiment::assay(cds, nm)
    expect_identical(dim(a), dim(cds))
    expect_identical(dimnames(a), dimnames(cds))
    expect_true(all(is.finite(as.matrix(a[1:10, 1:10]))))
  }
  if ("counts_row_order" %in% assays) {
    expect_equal(dense_block(SummarizedExperiment::assay(cds, "counts_row_order"), 1:10, 1:10),
                 counts)
  }
  for (nm in SingleCellExperiment::altExpNames(cds)) {
    alt <- SingleCellExperiment::altExp(cds, nm)
    expect_identical(colnames(alt), colnames(cds))
    expect_gt(nrow(alt), 0L)
    expect_gt(length(SummarizedExperiment::assayNames(alt)), 0L)
    expect_equal(nrow(SummarizedExperiment::rowData(alt)), nrow(alt))
  }
})
