# Fixture package: projectData.monocle3.testdata (see helper-integration.R).

test_that("C: attaching does not open any CDS; first access opens exactly once", {
  local_testdata_session()
  counter <- local_open_counter()
  before <- list.files(work_root(), recursive = TRUE)

  projectData::data_attach(testdata_pkg)

  expect_length(counter$log, 0)
  expect_identical(list.files(work_root(), recursive = TRUE), before)
  expect_true(all(testdata_catalog()$state == "unopened"))

  # Reading the catalog above must not have forced any binding.
  expect_length(counter$log, 0)

  cds <- get("cds_bpcells_a", envir = as.environment("projectData:data"))

  expect_identical(counter$log, paste(testdata_pkg, "cds_bpcells_a", sep = "/"))
  expect_s4_class(cds, "cell_data_set")
  expect_true(inherits(cds, "cell_data_set"))
  expect_identical(dim(cds), c(100L, 40L))
  expect_identical(catalog_row("cds_bpcells_a")$state, "ready")
  expect_identical(catalog_row("cds_bpcells_b")$state, "unopened")
  expect_gt(length(list.files(work_root(), recursive = TRUE)), length(before))
})

test_that("C: repeated access reuses the opened resource", {
  local_testdata_session()
  counter <- local_open_counter()
  projectData::data_attach(testdata_pkg)

  first <- get("cds_bpcells_a", envir = as.environment("projectData:data"))
  files_after_first <- list.files(work_root(), recursive = TRUE)
  second <- projectData::data_get("cds_bpcells_a")
  third <- get("cds_bpcells_a", envir = as.environment("projectData:data"))

  expect_length(counter$log, 1)
  expect_identical(bpcells_dir(first), bpcells_dir(second))
  expect_identical(bpcells_dir(first), bpcells_dir(third))
  expect_identical(list.files(work_root(), recursive = TRUE), files_after_first)
})

test_that("D: both CDS objects keep genuine BPCells on-disk counts that can be read", {
  local_testdata_session()
  projectData::data_attach(testdata_pkg)

  for (name in testdata_cds) {
    cds <- projectData::data_get(name)
    mat <- SummarizedExperiment::assay(cds, "counts")
    dims <- testdata_dims[[name]]

    expect_s4_class(mat, "MatrixDir")
    expect_true(methods::is(mat, "IterableMatrix"))
    expect_false(methods::is(mat, "Matrix"))
    expect_identical(dim(mat), dims)
    expect_identical(dim(cds), dims)

    # Identifiers: present, unique, and the same on the matrix and the CDS.
    expect_length(rownames(mat), dims[[1]])
    expect_length(colnames(mat), dims[[2]])
    expect_false(anyNA(c(rownames(mat), colnames(mat))))
    expect_false(anyDuplicated(rownames(mat)) > 0)
    expect_false(anyDuplicated(colnames(mat)) > 0)
    expect_identical(rownames(mat), rownames(cds))
    expect_identical(colnames(mat), colnames(cds))

    block <- dense_block(mat, 1:10, 1:10)
    expect_true(is.numeric(block))
    expect_identical(dim(block), c(10L, 10L))
    expect_true(all(is.finite(block)))
    expect_true(all(block >= 0))
    expect_identical(dimnames(block), list(rownames(mat)[1:10], colnames(mat)[1:10]))
    expect_true(all(is.finite(Matrix::colSums(mat))))
  }
})

test_that("E: restored BPCells files live under the allocated work_dir in the session tempdir", {
  local_testdata_session()
  spy <- local_path_spy()
  cwd <- withr::local_tempdir("pdm3-cwd-")
  withr::local_dir(cwd)
  installed_before <- snapshot_installed()

  a <- projectData::data_get("cds_bpcells_a", package = testdata_pkg)
  b <- projectData::data_get("cds_bpcells_b", package = testdata_pkg)

  # Nothing written to the working directory; installation untouched.
  expect_identical(normalizePath(getwd()), normalizePath(cwd))
  expect_length(list.files(cwd, all.files = TRUE, no.. = TRUE), 0)
  expect_identical(snapshot_installed(), installed_before)

  wd <- list(a = spy$paths$cds_bpcells_a$work_dir, b = spy$paths$cds_bpcells_b$work_dir)
  expect_true(all(lengths(wd) == 1))
  for (w in wd) {
    expect_true(in_dir(w, work_root()))
    expect_true(in_dir(w, tempdir()))
    expect_identical(basename(dirname(w)), testdata_pkg)
  }
  expect_identical(basename(work_root()), "projectData-work")

  # Backing directories are inside the matching work_dir and outside the
  # installed package.
  installed <- system.file(package = testdata_pkg)
  expect_true(in_dir(bpcells_dir(a), wd$a))
  expect_true(in_dir(bpcells_dir(b), wd$b))
  expect_false(in_dir(bpcells_dir(a), installed))
  expect_false(in_dir(bpcells_dir(b), installed))
  expect_true(dir.exists(bpcells_dir(a)))
  expect_true(dir.exists(bpcells_dir(b)))

  # Separate, non-nested directories for the two resources.
  expect_false(identical(wd$a, wd$b))
  expect_false(in_dir(wd$a, wd$b) || in_dir(wd$b, wd$a))
  expect_false(identical(bpcells_dir(a), bpcells_dir(b)))
  expect_false(in_dir(bpcells_dir(a), wd$b))
  expect_false(in_dir(bpcells_dir(b), wd$a))

  # monocle3 also writes a row-ordered copy of the counts; it is in work_dir.
  row_order <- SummarizedExperiment::assay(a, "counts_row_order")
  expect_true(in_dir(row_order@dir, wd$a))
})
