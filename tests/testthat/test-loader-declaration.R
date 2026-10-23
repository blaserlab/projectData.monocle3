test_that("projectData_loaders() declares a valid version-1 disk-backed loader", {
  loader <- projectData_loaders()
  expect_s3_class(loader, "projectData_loader")
  expect_identical(loader$id, "projectData.monocle3::cds")
  expect_identical(loader$storage, "disk-backed")
  expect_true(loader$needs_work_dir)
  expect_null(loader$discover)
  expect_true(is.function(loader$validate))
  expect_true(is.function(loader$open))
})

test_that("the declaration can be registered explicitly and atomically", {
  local_clean_projectData()
  ids <- projectData::data_loader_adapter("projectData.monocle3")
  expect_identical(ids, "projectData.monocle3::cds")
  expect_true("projectData.monocle3::cds" %in% projectData::data_loaders()$id)
})
