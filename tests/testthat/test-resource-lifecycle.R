# Fixture package: projectData.monocle3.testdata (see helper-integration.R).

test_that("F: a retained CDS keeps working after data_detach()", {
  local_testdata_session()
  cds <- projectData::data_get("cds_bpcells_a", package = testdata_pkg)
  mat <- SummarizedExperiment::assay(cds, "counts")
  before <- dense_block(mat, 1:5, 1:5)
  dir <- bpcells_dir(cds)
  expect_true(NROW(projectData::data_collections()) > 0)

  projectData::data_detach()

  expect_identical(NROW(projectData::data_collections()), 0L)
  expect_false("projectData:data" %in% search())
  expect_false(any(testdata_cds %in% projectData::data_catalog()$object))

  mat <- SummarizedExperiment::assay(cds, "counts")
  result <- dense_block(mat, 1:5, 1:5)
  expect_true(is.matrix(result))
  expect_true(is.numeric(result))
  expect_identical(dim(result), c(5L, 5L))
  expect_true(all(is.finite(result)))
  expect_identical(result, before)
  expect_true(dir.exists(dir))
  expect_s4_class(cds, "cell_data_set")
  expect_identical(dim(cds), c(100L, 40L))
})

test_that("F: detaching with an attached binding leaves the retained object valid", {
  local_testdata_session()
  projectData::data_attach(testdata_pkg)
  env <- as.environment("projectData:data")
  retained <- get("cds_bpcells_b", envir = env)

  projectData::data_detach()

  expect_false("projectData:data" %in% search())
  expect_true(validObject(retained))
  expect_identical(dim(retained), c(80L, 30L))
  expect_true(all(is.finite(dense_block(SummarizedExperiment::assay(retained, "counts"), 1:3, 1:3))))
})

test_that("G: the test package can be detached and attached again", {
  local_testdata_session()
  check_both <- function() {
    for (name in testdata_cds) {
      cds <- get(name, envir = as.environment("projectData:data"))
      expect_s4_class(cds, "cell_data_set")
      expect_identical(dim(cds), testdata_dims[[name]])
      expect_s4_class(SummarizedExperiment::assay(cds, "counts"), "MatrixDir")
    }
  }

  projectData::data_attach(testdata_pkg)
  expect_true("projectData:data" %in% search())
  check_both()
  first <- projectData::data_get("cds_bpcells_a")

  projectData::data_detach()
  expect_false("projectData:data" %in% search())

  projectData::data_attach(testdata_pkg)
  expect_true("projectData:data" %in% search())
  check_both()

  # The object retained from the first attachment is still usable.
  expect_true(all(is.finite(dense_block(SummarizedExperiment::assay(first, "counts"), 1:5, 1:5))))
})
