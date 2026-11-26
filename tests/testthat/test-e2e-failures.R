# Self-contained end-to-end tests, part 4: damaged installations fail with
# classed, actionable errors, never leave a half-opened object behind, do not
# affect other resources, and recover through data_retry(). Every test damages a
# disposable copy of the installed package in its own library; the suite's
# libraries are never modified (helper-synthetic.R).

installed_resource <- function(lib, name, ...) {
  file.path(lib, synthetic_pkg, "extdata", name, ...)
}

row_state <- function(object) {
  cat <- projectData::data_catalog()
  cat$state[cat$package == synthetic_pkg & cat$object == object]
}

# Opening `name` must fail as an opening failure whose message matches
# `regexp`, mark the resource failed, and leave no object behind.
expect_opening_fails <- function(name, regexp) {
  err <- expect_error(projectData::data_get(name), regexp, class = "projectData_opening_failed")
  expect_identical(row_state(name), "failed")
  # Asking again fails again, without a new attempt: no partially valid object
  # was cached, and the failure is sticky until data_retry().
  expect_error(projectData::data_get(name), class = "projectData_opening_failed")
  expect_identical(row_state(name), "failed")
  invisible(err)
}

# The other resource is unaffected, and still equals its spec.
expect_sibling_opens <- function(s, name) {
  cds <- projectData::data_get(name)
  expect_summary_matches_spec(cds_summary(cds), s$spec[[name]], "MatrixDir")
  expect_identical(row_state(name), "ready")
}

test_that("a missing native resource directory fails the whole attach, registers nothing, and recovers", {
  skip_if_no_e2e()
  local_clean_projectData()
  s <- synthetic_suite()
  lib <- local_package_copy()
  parked <- withr::local_tempdir("pdm3-parked-")
  expect_true(file.rename(installed_resource(lib, "cds_a"), file.path(parked, "cds_a")))

  # The manifest is checked as a whole when the package is attached.
  expect_error(projectData::data_attach(synthetic_pkg, lib.loc = lib), "extdata/cds_a",
               class = "projectData_manifest_error")
  expect_false("projectData:data" %in% search())
  expect_false(any(projectData::data_catalog()$package == synthetic_pkg))

  expect_true(file.rename(file.path(parked, "cds_a"), installed_resource(lib, "cds_a")))
  projectData::data_attach(synthetic_pkg, lib.loc = lib)
  expect_summary_matches_spec(cds_summary(projectData::data_get("cds_a")), s$spec$cds_a, "MatrixDir")
  expect_summary_matches_spec(cds_summary(projectData::data_get("cds_b")), s$spec$cds_b, "MatrixDir")
})

test_that("a missing file_index.rds is reported by name and recovers", {
  skip_if_no_e2e()
  local_clean_projectData()
  s <- synthetic_suite()
  lib <- local_package_copy()
  index <- installed_resource(lib, "cds_a", "file_index.rds")
  backup <- withr::local_tempfile(fileext = ".rds")
  expect_true(file.copy(index, backup))
  expect_true(file.remove(index))
  counter <- local_open_counter()
  projectData::data_attach(synthetic_pkg, lib.loc = lib)

  expect_opening_fails("cds_a", "file_index\\.rds")
  # Rejected by validate(): the loader's open() never ran.
  expect_length(counter$log, 0L)
  expect_sibling_opens(s, "cds_b")

  expect_true(file.copy(backup, index))
  projectData::data_retry(synthetic_pkg, "cds_a")
  expect_summary_matches_spec(cds_summary(projectData::data_get("cds_a")), s$spec$cds_a, "MatrixDir")
})

test_that("a missing BPCells backing file is reported and recovers", {
  skip_if_no_e2e()
  local_clean_projectData()
  s <- synthetic_suite()
  lib <- local_package_copy()
  victim <- installed_resource(lib, "cds_b", "bpcells_matrix_dir", "idxptr")
  backup <- withr::local_tempfile()
  expect_true(file.copy(victim, backup))
  expect_true(file.remove(victim))
  counter <- local_open_counter()
  projectData::data_attach(synthetic_pkg, lib.loc = lib)

  expect_opening_fails("cds_b", "idxptr")
  expect_length(counter$log, 0L)
  expect_sibling_opens(s, "cds_a")

  expect_true(file.copy(backup, victim))
  projectData::data_retry(synthetic_pkg, "cds_b")
  expect_summary_matches_spec(cds_summary(projectData::data_get("cds_b")), s$spec$cds_b, "MatrixDir")
})

test_that("an invalid manifest source path is refused at attach, naming the resource", {
  skip_if_no_e2e()
  local_clean_projectData()
  s <- synthetic_suite()
  lib <- local_package_copy()
  manifest <- file.path(lib, synthetic_pkg, "projectData", "manifest.dcf")
  original <- readLines(manifest)

  for (bad in c("extdata/does_not_exist", "extdata/../../outside", "inst/extdata/cds_a")) {
    writeLines(sub("^Source: extdata/cds_a$", paste("Source:", bad), original), manifest)
    err <- expect_error(projectData::data_attach(synthetic_pkg, lib.loc = lib),
                        class = "projectData_manifest_error", info = bad)
    expect_match(conditionMessage(err), "cds_a", info = bad)
    expect_false("projectData:data" %in% search())
    expect_false(any(projectData::data_catalog()$package == synthetic_pkg))
  }

  # Restoring the manifest recovers.
  writeLines(original, manifest)
  expect_summary_matches_spec(
    cds_summary(projectData::data_get("cds_a", package = synthetic_pkg, lib.loc = lib)),
    s$spec$cds_a, "MatrixDir"
  )
})

test_that("a failure while restoring the CDS is classed and recovers", {
  skip_if_no_e2e()
  local_clean_projectData()
  s <- synthetic_suite()
  lib <- local_package_copy()
  object_file <- installed_resource(lib, "cds_a", "cds_object.rds")
  backup <- withr::local_tempfile(fileext = ".rds")
  expect_true(file.copy(object_file, backup))
  # Same size and a valid file, but not a CDS: validate() passes, restoration fails.
  saveRDS("not a cell_data_set", object_file)
  counter <- local_open_counter()
  projectData::data_attach(synthetic_pkg, lib.loc = lib)
  expect_identical(row_state("cds_a"), "unopened")

  expect_opening_fails("cds_a", "")
  expect_identical(counter$log, paste(synthetic_pkg, "cds_a", sep = "/"))
  expect_sibling_opens(s, "cds_b")

  expect_true(file.copy(backup, object_file, overwrite = TRUE))
  projectData::data_retry(synthetic_pkg, "cds_a")
  expect_summary_matches_spec(cds_summary(projectData::data_get("cds_a")), s$spec$cds_a, "MatrixDir")
})

test_that("a missing optional runtime dependency gives an actionable error and recovers", {
  skip_if_no_e2e()
  s <- synthetic_suite()
  stub_lib <- local_stub_library("monocle3")

  probe <- run_child("probe_missing_dependency", list(
    lib = s$lib_a, pkg = s$pkg, resource = "cds_a", stub_lib = stub_lib
  ))
  expect_false(inherits(probe, "probe_error"), info = if (inherits(probe, "probe_error")) probe$message)
  expect_true("projectData_opening_failed" %in% probe$failed$class)
  expect_match(probe$failed$message, "monocle3")
  expect_match(probe$failed$message, "required")
  expect_match(probe$failed$message, "README")
  expect_identical(probe$failed$state, "failed")
  expect_identical(probe$state_after_retry, "ready")
  expect_summary_matches_spec(probe$recovered, s$spec$cds_a, "MatrixDir")
})

test_that("authoring recovers after an unsupported external assay is corrected", {
  skip_if_no_e2e()
  s <- synthetic_suite()
  work <- withr::local_tempdir("pdm3-recover-")
  src <- synthetic_package_source("recoverData", "cds_fix", file.path(work, "src"))
  bad <- synthetic_cds_with_external_assay(s$spec$cds_a, work)
  expect_error(suppressMessages(save_monocle_cds(bad, "cds_fix", src)),
               class = "projectData.monocle3_external_assay")

  # Dropping the external alternative experiment makes the same CDS savable.
  SingleCellExperiment::altExp(bad, "EXT") <- NULL
  out <- save_quiet(bad, "cds_fix", src)
  expect_identical(out$result$manifest_status, "added")
  expect_true(validate_monocle_cds(list(source = "extdata/cds_fix", objects = "cds_fix"),
                                   file.path(src, "inst"), list()))
  expect_length(stage_dirs(src), 0L)
})

test_that("the suite's own libraries were not modified by the failure tests", {
  skip_if_no_e2e()
  s <- synthetic_suite()
  for (lib in c(s$lib_a, s$lib_b)) {
    expect_identical(tree_checksums(file.path(lib, s$pkg, "extdata")),
                     tree_checksums(file.path(s$src, "inst", "extdata")))
    expect_identical(tree_checksums(file.path(lib, s$pkg, "projectData")),
                     tree_checksums(file.path(s$src, "inst", "projectData")))
  }
})
