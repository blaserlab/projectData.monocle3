test_that("one valid saved CDS with a legacy placeholder is discovered", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_one")

  found <- discover_monocle_resources(pkg)

  expect_identical(found$resource, "cds_one")
  expect_identical(found$status, "discovered")
  expect_identical(found$source, "extdata/cds_one")
  expect_true(file.exists(found$placeholder))
})

test_that("several valid CDS resources are discovered, sorted by name", {
  pkg <- new_pkg_source()
  for (nm in c("cds_b", "cds_a", "cds_c")) add_resource(pkg, nm)

  found <- discover_monocle_resources(pkg)

  expect_identical(found$resource, c("cds_a", "cds_b", "cds_c"))
  expect_true(all(found$status == "discovered"))
})

test_that("an ordinary .rda dataset is ignored", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_one")
  add_rda(pkg, "ordinary_data", list(ordinary_data = data.frame(x = 1:3)))

  found <- discover_monocle_resources(pkg)

  expect_identical(found$resource, "cds_one")
})

test_that("unrelated directories under inst/extdata are ignored", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_one")
  dir.create(file.path(pkg, "inst", "extdata", "other_stuff", "nested"), recursive = TRUE)
  writeLines("a,b", file.path(pkg, "inst", "extdata", "other_stuff", "table.csv"))
  dir.create(file.path(pkg, "inst", "extdata", ".hidden"))
  writeLines("x", file.path(pkg, "inst", "extdata", "loose_file.txt"))

  found <- discover_monocle_resources(pkg)

  expect_identical(found$resource, "cds_one")
})

test_that("a directory is not identified by bpcells_matrix_dir alone", {
  pkg <- new_pkg_source()
  add_placeholder(pkg, "just_matrix")
  dir.create(file.path(pkg, "inst", "extdata", "just_matrix", "bpcells_matrix_dir"),
             recursive = TRUE)

  found <- discover_monocle_resources(pkg)

  expect_identical(found$status, "invalid_cds")
  expect_match(found$reason, "file_index.rds")
})

test_that("incomplete or malformed Monocle directories are rejected with a reason", {
  pkg <- new_pkg_source()
  for (nm in c("m_missing_file", "m_bad_index", "m_wrong_function", "m_memory", "m_tar_only")) {
    add_placeholder(pkg, nm)
  }
  add_fake_cds(pkg, "m_missing_file", create = FALSE)

  bad <- add_fake_cds(pkg, "m_bad_index")
  writeLines("not rds", file.path(bad, "file_index.rds"))

  add_fake_cds(pkg, "m_wrong_function", save_function = "something_else")

  memory_files <- fake_files()[1, ]
  add_fake_cds(pkg, "m_memory", files = memory_files)

  dir.create(file.path(pkg, "inst", "extdata", "m_tar_only"), recursive = TRUE)
  file.create(file.path(pkg, "inst", "extdata", "m_tar_only", "cds_object.rds"))

  found <- discover_monocle_resources(pkg)

  expect_true(all(found$status == "invalid_cds"))
  expect_setequal(found$resource,
                  c("m_missing_file", "m_bad_index", "m_wrong_function", "m_memory", "m_tar_only"))
  reason <- stats::setNames(found$reason, found$resource)
  expect_match(reason[["m_missing_file"]], "missing saved file")
  expect_match(reason[["m_bad_index"]], "cannot read")
  expect_match(reason[["m_wrong_function"]], "save_monocle_objects")
  expect_match(reason[["m_memory"]], "BPCells matrix")
  expect_match(reason[["m_tar_only"]], "file_index.rds")
})

test_that("a directory name that is not a valid object name is rejected", {
  pkg <- new_pkg_source()
  add_fake_cds(pkg, "my-cds")

  found <- discover_monocle_resources(pkg)

  expect_identical(found$status, "invalid_cds")
  expect_match(found$reason, "valid R object name")
})

test_that("a CDS without a matching placeholder is skipped with a reason", {
  pkg <- new_pkg_source()
  add_fake_cds(pkg, "no_placeholder")
  add_rda(pkg, "unrelated", list(unrelated = 1))

  found <- discover_monocle_resources(pkg)

  expect_identical(found$status, "no_placeholder")
  expect_match(found$reason, "data/no_placeholder.rda")
  expect_true(is.na(found$placeholder))
})

test_that("an .rda holding a real dataset is not accepted as a placeholder", {
  pkg <- new_pkg_source()
  for (nm in c("real_df", "wrong_name", "two_objects", "other_text", "classed", "empty_vec")) {
    add_fake_cds(pkg, nm)
  }
  add_placeholder(pkg, "real_df", data.frame(a = 1:3))
  add_rda(pkg, "wrong_name", list(something_else = legacy_placeholder))
  add_rda(pkg, "two_objects", list(two_objects = legacy_placeholder, extra = 1))
  add_placeholder(pkg, "other_text", "some real label")
  add_placeholder(pkg, "classed", structure(legacy_placeholder, class = "mystery"))
  add_placeholder(pkg, "empty_vec", character())

  found <- discover_monocle_resources(pkg)

  expect_true(all(found$status == "not_placeholder"))
  expect_equal(nrow(found), 6L)
  reason <- stats::setNames(found$reason, found$resource)
  expect_match(reason[["wrong_name"]], "something_else")
  expect_match(reason[["two_objects"]], "more than one object")
  expect_match(reason[["real_df"]], "not a recognized placeholder")
})

test_that("the legacy placeholder is recognized under every .rda compression", {
  skip_if_not_installed("withr")
  for (compress in list(TRUE, FALSE, "bzip2", "xz")) {
    pkg <- new_pkg_source()
    add_fake_cds(pkg, "cds_one")
    add_placeholder(pkg, "cds_one", compress = compress)
    expect_identical(discover_monocle_resources(pkg)$status, "discovered",
                     info = format(compress))
  }
})

test_that(".RData and .rdata placeholders also match", {
  for (ext in c("RData", "rdata")) {
    pkg <- new_pkg_source()
    add_fake_cds(pkg, "cds_one")
    add_placeholder(pkg, "cds_one")
    file.rename(file.path(pkg, "data", "cds_one.rda"),
                file.path(pkg, "data", paste0("cds_one.", ext)))
    expect_identical(discover_monocle_resources(pkg)$status, "discovered", info = ext)
  }
})

test_that("an unreadable or ambiguous placeholder is reported, never accepted", {
  pkg <- new_pkg_source()
  for (nm in c("garbage", "empty", "ambiguous")) add_fake_cds(pkg, nm)
  dir.create(file.path(pkg, "data"))
  writeLines("this is not an rda file", file.path(pkg, "data", "garbage.rda"))
  file.create(file.path(pkg, "data", "empty.rda"))
  add_placeholder(pkg, "ambiguous")
  file.copy(file.path(pkg, "data", "ambiguous.rda"), file.path(pkg, "data", "ambiguous.RData"))

  found <- discover_monocle_resources(pkg)

  expect_true(all(found$status == "bad_placeholder"))
  expect_equal(nrow(found), 3L)
  expect_match(found$reason[found$resource == "ambiguous"], "more than one data file")
})

test_that("placeholder inspection reads the name, value and attributes without evaluating", {
  skip_if_not_installed("withr")
  path <- withr::local_tempfile(fileext = ".rda")
  obj <- structure(c("a", "b"), class = c("pdm_placeholder", "character"))
  save(obj, file = path)

  info <- inspect_rda(path)

  expect_true(info$readable)
  expect_identical(info$names, "obj")
  expect_true(info$single)
  expect_identical(info$kind, "character")
  expect_identical(info$value, c("a", "b"))
  expect_identical(info$attributes$class, c("pdm_placeholder", "character"))

  save(obj, file = path, ascii = TRUE)
  expect_false(inspect_rda(path)$readable)
})

test_that("a new placeholder representation only needs a new recognizer", {
  pkg <- new_pkg_source()
  add_fake_cds(pkg, "cds_one")
  add_placeholder(pkg, "cds_one",
                  structure(c("line 1", "line 2"), class = "future_placeholder"))
  expect_identical(discover_monocle_resources(pkg)$status, "not_placeholder")

  local_mocked_bindings(placeholder_recognizers = function() {
    c(list(future = function(info, name) {
      identical(info$kind, "character") && "future_placeholder" %in% info$attributes$class
    }), list(legacy = function(info, name) FALSE))
  })
  expect_identical(discover_monocle_resources(pkg)$status, "discovered")
})

test_that("missing inst/extdata and data are handled", {
  pkg <- new_pkg_source()
  expect_identical(nrow(discover_monocle_resources(pkg)), 0L)

  add_fake_cds(pkg, "cds_one")
  expect_identical(discover_monocle_resources(pkg)$status, "no_placeholder")

  pkg2 <- new_pkg_source()
  add_placeholder(pkg2, "cds_one")
  expect_identical(nrow(discover_monocle_resources(pkg2)), 0L)
})

test_that("discovery never modifies the file system", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_one")
  add_fake_cds(pkg, "broken", create = FALSE)
  before <- file_state(pkg)
  cwd_before <- list.files(getwd(), all.files = TRUE)

  discover_monocle_resources(pkg)

  expect_identical(file_state(pkg), before)
  expect_identical(list.files(getwd(), all.files = TRUE), cwd_before)
})

test_that("invalid package directories give clear errors", {
  expect_error(discover_monocle_resources(file.path(tempdir(), "no-such-dir")),
               "not an existing directory")
  expect_error(discover_monocle_resources(NA_character_), "single path")
  expect_error(discover_monocle_resources(c("a", "b")), "single path")
  expect_error(discover_monocle_resources(1), "single path")

  skip_if_not_installed("withr")
  empty <- withr::local_tempdir()
  expect_error(discover_monocle_resources(empty), "not an R package source")

  file <- withr::local_tempfile()
  writeLines("x", file)
  expect_error(discover_monocle_resources(file), "not an existing directory")

  expect_error(discover_monocle_resources(system.file(package = "projectData")),
               "installed package")
})

test_that("discovery does not load a CDS or create BPCells working files", {
  skip_if_no_monocle()
  fx <- cds_fixtures()
  pkg <- new_pkg_source()
  copy_dir_to(fx$human$saved)(file.path(pkg, "inst", "extdata", "human_cds"))
  add_placeholder(pkg, "human_cds")

  before <- file_state(pkg)
  namespaces <- loadedNamespaces()
  temp_before <- list.files(tempdir(), recursive = TRUE, include.dirs = TRUE)
  cwd_before <- list.files(getwd(), all.files = TRUE)

  found <- discover_monocle_resources(pkg)

  expect_identical(found$status, "discovered")
  expect_identical(file_state(pkg), before)
  expect_setequal(loadedNamespaces(), namespaces)
  expect_identical(list.files(tempdir(), recursive = TRUE, include.dirs = TRUE), temp_before)
  expect_identical(list.files(getwd(), all.files = TRUE), cwd_before)
})
