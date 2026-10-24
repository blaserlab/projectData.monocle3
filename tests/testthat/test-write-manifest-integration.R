# End to end: generate a manifest for a disposable copy of the
# projectData.monocle3.testdata source, install it into a temporary library
# and use it through projectData. The source tree is found through the
# PDM3_TESTDATA_SOURCE environment variable, or as a sibling directory of this
# package; the test skips if neither exists. The installed copy of the fixture
# package is never modified.

testdata_source <- function() {
  candidates <- c(
    Sys.getenv("PDM3_TESTDATA_SOURCE", unset = NA),
    file.path(dirname(normalizePath(test_path("..", ".."))), testdata_pkg)
  )
  for (path in candidates[!is.na(candidates)]) {
    desc <- file.path(path, "DESCRIPTION")
    if (file.exists(desc) && identical(read.dcf(desc, "Package")[[1]], testdata_pkg) &&
        dir.exists(file.path(path, "inst", "extdata"))) {
      return(normalizePath(path))
    }
  }
  NULL
}

disposable_testdata_copy <- function(env = parent.frame()) {
  src <- testdata_source()
  if (is.null(src)) skip("projectData.monocle3.testdata source tree not available")
  root <- withr::local_tempdir(.local_envir = env)
  keep <- setdiff(list.files(src, all.files = TRUE, no.. = TRUE),
                  c(".git", ".Rproj.user", ".Rhistory", "library_catalogs"))
  dest <- file.path(root, testdata_pkg)
  dir.create(dest)
  file.copy(file.path(src, keep), dest, recursive = TRUE)
  dest
}

test_that("a generated manifest makes the test data package work through projectData", {
  skip_if_no_testdata()
  pkg <- disposable_testdata_copy()
  source_snapshot <- file_state(file.path(pkg, "inst", "extdata"))
  placeholders <- file_state(file.path(pkg, "data"))
  unlink(manifest_file(pkg))
  expect_false(file.exists(manifest_file(pkg)))
  expected <- list.files(file.path(pkg, "inst", "extdata"))
  has_ordinary <- file.exists(file.path(pkg, "data", "ordinary_data.rda"))
  first <- expected[[1]]

  out <- run_write(pkg)

  expect_setequal(out$report$resource, expected)
  expect_true(all(out$report$status == "added"))
  expect_length(out$warnings, 0L)
  expect_identical(file_state(file.path(pkg, "inst", "extdata")), source_snapshot)
  expect_identical(file_state(file.path(pkg, "data")), placeholders)

  expect_setequal(manifest_resources(pkg), expected)
  expect_false("ordinary_data" %in% manifest_resources(pkg))
  expect_no_error(projectData::data_manifest_validate(manifest_file(pkg), root = pkg))

  # Re-running changes nothing.
  manifest_before <- file_state(dirname(manifest_file(pkg)))
  expect_false(attr(run_write(pkg)$report, "written"))
  expect_identical(file_state(dirname(manifest_file(pkg))), manifest_before)

  lib <- withr::local_tempdir()
  installed <- system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "INSTALL", "--no-test-load", "-l", shQuote(lib), shQuote(pkg)),
    stdout = TRUE, stderr = TRUE
  )
  expect_true(file.exists(file.path(lib, testdata_pkg, "DESCRIPTION")),
              info = paste(installed, collapse = "\n"))
  fixture_before <- snapshot_installed()

  local_testdata_session()
  projectData::data_attach(testdata_pkg, lib.loc = lib)

  cat <- testdata_catalog()
  expect_true(all(expected %in% cat$object))
  loader <- stats::setNames(cat$loader, cat$object)
  origin <- stats::setNames(cat$origin, cat$object)
  expect_true(all(loader[expected] == "projectData.monocle3::cds"))
  expect_true(all(origin[expected] == "manifest"))
  expect_identical(stats::setNames(cat$source, cat$object)[expected],
                   stats::setNames(paste0("extdata/", expected), expected))
  # Nothing has been opened by registration.
  expect_true(all(cat$state[cat$object %in% expected] == "unopened"))

  if (has_ordinary) {
    expect_identical(loader[["ordinary_data"]], "projectData::dataset")
    expect_identical(origin[["ordinary_data"]], "index")
    expect_identical(projectData::data_get("ordinary_data"), data.frame(letters = letters[1:10]))
  }

  cds <- projectData::data_get(first)
  expect_s4_class(cds, "cell_data_set")
  counts <- SummarizedExperiment::assay(cds, "counts")
  expect_true(methods::is(counts, "MatrixDir"))
  block <- dense_block(counts)
  expect_identical(dim(block), c(5L, 5L))
  expect_true(all(is.finite(block)))
  expect_identical(catalog_row(first)$loader_status, "registered")

  expect_identical(snapshot_installed(), fixture_before)
})

test_that("deleting a saved directory from the test data source is repaired by reconciliation", {
  pkg <- disposable_testdata_copy()
  resources <- manifest_resources(pkg)
  skip_if(length(resources) < 2L, "test data source has fewer than two registered resources")
  gone <- resources[[1]]
  unlink(file.path(pkg, "inst", "extdata", gone), recursive = TRUE)
  placeholders <- file_state(file.path(pkg, "data"))
  remaining <- file_state(file.path(pkg, "inst", "extdata"))

  out <- run_write(pkg)

  expect_identical(status_of(out$report, gone), "removed")
  expect_identical(manifest_resources(pkg), setdiff(resources, gone))
  expect_no_error(projectData::data_manifest_validate(manifest_file(pkg), root = pkg))
  expect_identical(file_state(file.path(pkg, "data")), placeholders)
  expect_identical(file_state(file.path(pkg, "inst", "extdata")), remaining)

  manifest_before <- file_state(dirname(manifest_file(pkg)))
  expect_false(attr(run_write(pkg)$report, "written"))
  expect_identical(file_state(dirname(manifest_file(pkg))), manifest_before)
})
