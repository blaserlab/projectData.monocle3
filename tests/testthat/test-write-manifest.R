# A manifest entry for a loader that is not registered, with hand-made fields.
other_entry <- c(
  "Resource: other_res",
  "Loader: other::loader",
  "Source: extdata/other_thing",
  "Objects: other_obj",
  "Title: Hand-written title",
  "Options: mode=fast;level=2",
  "RecordedClass: some_class"
)

add_other_source <- function(pkg) {
  dir.create(file.path(pkg, "inst", "extdata", "other_thing"), recursive = TRUE)
  writeLines("x", file.path(pkg, "inst", "extdata", "other_thing", "payload.txt"))
}

test_that("a manifest is generated when none exists", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  add_resource(pkg, "cds_b")
  add_rda(pkg, "ordinary_data", list(ordinary_data = data.frame(x = 1)))

  out <- run_write(pkg)

  expect_identical(out$report$status, c("added", "added"))
  expect_length(out$warnings, 0L)
  expect_true(attr(out$report, "written"))
  expect_identical(manifest_resources(pkg), c("cds_a", "cds_b"))

  descriptors <- projectData::data_manifest_validate(manifest_file(pkg), root = pkg)
  d <- descriptors[[1]]
  expect_identical(d$loader, "projectData.monocle3::cds")
  expect_identical(d$source, "extdata/cds_a")
  expect_identical(d$objects, "cds_a")
  expect_identical(d$recorded_class, "cell_data_set")
  expect_identical(d$help_topic, "cds_a")
  expect_identical(d$adapter, list(package = "projectData.monocle3",
                                   export = "projectData_loaders"))
})

test_that("manifest text uses installed-relative paths and no machine paths", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  run_write(pkg)

  text <- readLines(manifest_file(pkg))

  expect_true("Source: extdata/cds_a" %in% text)
  expect_false(any(grepl("inst/", text, fixed = TRUE)))
  expect_false(any(grepl(dirname(pkg), text, fixed = TRUE)))
  expect_false(any(grepl("^Source: /", text)))
})

test_that("ordinary data is never registered as a Monocle resource", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  add_rda(pkg, "ordinary_data", list(ordinary_data = data.frame(x = 1)))
  run_write(pkg)

  expect_false("ordinary_data" %in% manifest_resources(pkg))
})

test_that("nothing is written and no manifest is created when nothing is found", {
  pkg <- new_pkg_source()
  add_rda(pkg, "ordinary_data", list(ordinary_data = data.frame(x = 1)))

  out <- run_write(pkg)

  expect_identical(nrow(out$report), 0L)
  expect_false(attr(out$report, "written"))
  expect_false(file.exists(manifest_file(pkg)))
  expect_false(dir.exists(dirname(manifest_file(pkg))))
})

test_that("new resources are added to an existing manifest, preserving unrelated entries", {
  pkg <- new_pkg_source()
  add_other_source(pkg)
  write_manifest_text(pkg, c("ManifestVersion: 1", "", other_entry))
  add_resource(pkg, "cds_a")

  out <- run_write(pkg)

  expect_identical(status_of(out$report, "cds_a"), "added")
  expect_identical(manifest_resources(pkg), c("other_res", "cds_a"))
  kept <- projectData::data_manifest_validate(manifest_file(pkg), root = pkg)[[1]]
  expect_identical(kept$loader, "other::loader")
  expect_identical(kept$objects, "other_obj")
  expect_identical(kept$title, "Hand-written title")
  expect_identical(kept$options, list(mode = "fast", level = "2"))
  expect_identical(kept$recorded_class, "some_class")
})

test_that("existing order is kept when a resource is added before it alphabetically", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_z")
  run_write(pkg)
  add_resource(pkg, "cds_a")

  run_write(pkg)

  expect_identical(manifest_resources(pkg), c("cds_z", "cds_a"))
})

test_that("a resource assigned to another loader is a conflict and is left unchanged", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  add_resource(pkg, "cds_b")
  write_manifest_text(pkg, c(
    "ManifestVersion: 1", "",
    "Resource: cds_a", "Loader: other::loader", "Objects: cds_a", "Title: mine"
  ))
  before <- readLines(manifest_file(pkg))

  out <- run_write(pkg)

  expect_identical(status_of(out$report, "cds_a"), "conflict")
  expect_identical(status_of(out$report, "cds_b"), "added")
  expect_match(out$report$detail[out$report$resource == "cds_a"], "other::loader")
  expect_true(any(vapply(out$warnings, inherits, NA, "projectData.monocle3_conflict")))

  d <- projectData::data_manifest_validate(manifest_file(pkg), root = pkg)
  expect_identical(vapply(d, function(x) x$resource, ""), c("cds_a", "cds_b"))
  expect_identical(d[[1]]$loader, "other::loader")
  expect_identical(d[[1]]$title, "mine")
  expect_identical(d[[2]]$loader, "projectData.monocle3::cds")
  expect_identical(readLines(manifest_file(pkg))[seq_along(before)][1:4], before[1:4])
})

test_that("when everything conflicts the manifest file is not touched", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  write_manifest_text(pkg, c("ManifestVersion: 1", "",
                             "Resource: cds_a", "Loader: other::loader", "Objects: cds_a"))
  before <- file_state(pkg)

  out <- run_write(pkg)

  expect_identical(out$report$status, "conflict")
  expect_false(attr(out$report, "written"))
  expect_identical(file_state(pkg), before)
})

test_that("an object name already declared by another resource is a conflict", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  write_manifest_text(pkg, c("ManifestVersion: 1", "",
                             "Resource: elsewhere", "Loader: other::loader", "Objects: cds_a"))

  out <- run_write(pkg)

  expect_identical(out$report$status, "conflict")
  expect_match(out$report$detail, "already declared by resource 'elsewhere'")
  expect_identical(manifest_resources(pkg), "elsewhere")
})

test_that("an existing Monocle entry is updated where needed, keeping manual fields", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  write_manifest_text(pkg, c(
    "ManifestVersion: 1", "",
    "Resource: cds_a", "Loader: projectData.monocle3::cds", "Source: extdata/cds_a",
    "Objects: cds_a", "Title: Keep me", "Options: k=v"
  ))

  out <- run_write(pkg)

  expect_identical(out$report$status, "updated")
  d <- projectData::data_manifest_validate(manifest_file(pkg), root = pkg)
  expect_length(d, 1L)
  expect_identical(d[[1]]$title, "Keep me")
  expect_identical(d[[1]]$options, list(k = "v"))
  expect_identical(d[[1]]$recorded_class, "cell_data_set")
  expect_identical(d[[1]]$help_topic, "cds_a")
  expect_identical(d[[1]]$adapter$package, "projectData.monocle3")
})

test_that("a hand-written HelpTopic on a Monocle entry is kept", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  write_manifest_text(pkg, c(
    "ManifestVersion: 1", "",
    "Resource: cds_a", "Loader: projectData.monocle3::cds", "Source: extdata/cds_a",
    "Objects: cds_a", "HelpTopic: my_docs", "AdapterPackage: wrong.pkg"
  ))

  run_write(pkg)

  d <- projectData::data_manifest_validate(manifest_file(pkg), root = pkg)[[1]]
  expect_identical(d$help_topic, "my_docs")
  expect_identical(d$adapter$package, "projectData.monocle3")
})

test_that("a Monocle entry already in the desired form is reported unchanged", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  # AdapterExport written out explicitly, as older hand-written manifests do.
  write_manifest_text(pkg, c(
    "ManifestVersion: 1", "",
    "Resource: cds_a", "Loader: projectData.monocle3::cds", "Source: extdata/cds_a",
    "Objects: cds_a", "AdapterPackage: projectData.monocle3",
    "AdapterExport: projectData_loaders", "RecordedClass: cell_data_set",
    "HelpTopic: cds_a"
  ))
  before <- file_state(pkg)

  out <- run_write(pkg)

  expect_identical(out$report$status, "unchanged")
  expect_identical(file_state(pkg), before)
})

test_that("running twice adds no duplicates and does not rewrite the manifest", {
  pkg <- new_pkg_source()
  add_other_source(pkg)
  write_manifest_text(pkg, c("ManifestVersion: 1", "", other_entry))
  add_resource(pkg, "cds_a")
  add_resource(pkg, "cds_b")

  first <- run_write(pkg)
  after_first <- file_state(pkg)
  second <- run_write(pkg)

  expect_true(attr(first$report, "written"))
  expect_false(attr(second$report, "written"))
  expect_identical(second$report$status, c("unchanged", "unchanged"))
  expect_identical(file_state(pkg), after_first)
  expect_identical(manifest_resources(pkg), c("other_res", "cds_a", "cds_b"))
  expect_false(anyDuplicated(manifest_resources(pkg)) > 0L)
})

test_that("skipped directories are reported with a warning and not registered", {
  pkg <- new_pkg_source()
  add_resource(pkg, "good")
  add_fake_cds(pkg, "no_placeholder")
  add_fake_cds(pkg, "real_data")
  add_placeholder(pkg, "real_data", data.frame(a = 1))
  data_before <- tools::md5sum(file.path(pkg, "data", "real_data.rda"))

  out <- run_write(pkg)

  expect_identical(status_of(out$report, "good"), "added")
  expect_identical(status_of(out$report, "no_placeholder"), "skipped")
  expect_identical(status_of(out$report, "real_data"), "skipped")
  skipped <- Filter(function(w) inherits(w, "projectData.monocle3_skipped"), out$warnings)
  expect_length(skipped, 1L)
  expect_match(conditionMessage(skipped[[1]]), "no_placeholder")
  expect_identical(manifest_resources(pkg), "good")
  expect_identical(tools::md5sum(file.path(pkg, "data", "real_data.rda")), data_before)
})

test_that("a skipped CDS leaves its existing manifest entry alone", {
  pkg <- new_pkg_source()
  add_fake_cds(pkg, "cds_a")
  write_manifest_text(pkg, c(
    "ManifestVersion: 1", "",
    "Resource: cds_a", "Loader: projectData.monocle3::cds", "Source: extdata/cds_a",
    "Objects: cds_a", "Title: custom"
  ))
  before <- file_state(pkg)

  out <- run_write(pkg)

  expect_identical(out$report$status, "skipped")
  expect_identical(file_state(pkg), before)
})

test_that("serialized CDS directories and placeholders are never modified", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  add_resource(pkg, "cds_b")
  inputs <- function() file_state(file.path(pkg, "inst", "extdata"))
  data <- function() file_state(file.path(pkg, "data"))
  inputs_before <- inputs()
  data_before <- data()

  run_write(pkg)

  expect_identical(inputs(), inputs_before)
  expect_identical(data(), data_before)
})

test_that("an invalid existing manifest stops the call and is left untouched", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  write_manifest_text(pkg, c("ManifestVersion: 1", "",
                             "Resource: dup", "Loader: other::loader",
                             "", "Resource: dup", "Loader: other::loader"))
  before <- file_state(pkg)

  expect_error(suppressMessages(write_monocle_manifest(pkg)),
               "existing manifest cannot be used.*duplicate Resource")
  expect_identical(file_state(pkg), before)

  writeLines("not: a: manifest", manifest_file(pkg))
  before <- file_state(pkg)
  expect_error(suppressMessages(write_monocle_manifest(pkg)), "was not modified")
  expect_identical(file_state(pkg), before)
})

test_that("a Monocle entry whose directory is invalid stops the write and keeps the old manifest", {
  pkg <- new_pkg_source()
  add_fake_cds(pkg, "cds_a", create = FALSE)
  add_placeholder(pkg, "cds_a")
  write_manifest_text(pkg, c(
    "ManifestVersion: 1", "",
    "Resource: cds_a", "Loader: projectData.monocle3::cds", "Source: extdata/cds_a",
    "Objects: cds_a"
  ))
  before <- file_state(pkg)

  expect_error(suppressMessages(write_monocle_manifest(pkg)), "missing saved file")
  expect_identical(file_state(pkg), before)
})

test_that("no staging files are left behind", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  run_write(pkg)

  expect_identical(list.files(dirname(manifest_file(pkg)), all.files = TRUE, no.. = TRUE),
                   "manifest.dcf")
})

test_that("the loader registry is restored, and a registered loader is left registered", {
  local_clean_projectData()
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  id <- "projectData.monocle3::cds"

  run_write(pkg)
  expect_false(id %in% projectData::data_loaders()$id)

  projectData::data_loader_add(projectData_loaders())
  add_resource(pkg, "cds_b")
  run_write(pkg)
  expect_true(id %in% projectData::data_loaders()$id)
})

test_that("write_monocle_manifest() rejects invalid package directories", {
  expect_error(write_monocle_manifest(file.path(tempdir(), "no-such-package")),
               "not an existing directory")
  expect_error(write_monocle_manifest(NULL), "single path")
  expect_error(write_monocle_manifest(c("a", "b")), "single path")
  skip_if_not_installed("withr")
  expect_error(write_monocle_manifest(withr::local_tempdir()), "not an R package source")
  expect_error(write_monocle_manifest(system.file(package = "projectData")),
               "installed package")
})

test_that("a package with no inst/extdata and no data/ is handled", {
  pkg <- new_pkg_source()
  out <- run_write(pkg)
  expect_identical(nrow(out$report), 0L)
  expect_false(file.exists(manifest_file(pkg)))
})

test_that("a generated manifest registers the resources with projectData's own validation", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  run_write(pkg)

  local_clean_projectData()
  projectData::data_loader_adapter("projectData.monocle3")
  expect_no_error(projectData::data_manifest_validate(manifest_file(pkg), root = pkg))
})
