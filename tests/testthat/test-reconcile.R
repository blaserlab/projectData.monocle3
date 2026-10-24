# Reconciliation of the manifest with the saved CDS directories and placeholders
# present in a package source tree. Synthetic trees, so monocle3 is not needed;
# everything happens in disposable directories.

own_entry <- function(resource) {
  c(paste0("Resource: ", resource), "Loader: projectData.monocle3::cds",
    paste0("Source: extdata/", resource), paste0("Objects: ", resource),
    "AdapterPackage: projectData.monocle3", "RecordedClass: cell_data_set",
    paste0("HelpTopic: ", resource))
}

# A package with registered, valid resources `resources`.
registered_pkg <- function(resources, env = parent.frame()) {
  pkg <- new_pkg_source(env = env)
  for (r in resources) add_resource(pkg, r)
  run_write(pkg)
  pkg
}

other_pkg_entry <- c("Resource: other_res", "Loader: other::loader",
                     "Source: extdata/other_thing", "Objects: other_obj",
                     "Title: Hand-written title", "Options: mode=fast;level=2",
                     "RecordedClass: some_class")

add_other_thing <- function(pkg) {
  dir.create(file.path(pkg, "inst", "extdata", "other_thing"), recursive = TRUE)
  writeLines("x", file.path(pkg, "inst", "extdata", "other_thing", "payload.txt"))
}

test_that("an entry whose saved directory was deleted is removed", {
  pkg <- registered_pkg(c("cds_a", "cds_b"))
  unlink(file.path(pkg, "inst", "extdata", "cds_a"), recursive = TRUE)

  out <- run_write(pkg)

  expect_identical(status_of(out$report, "cds_a"), "removed")
  expect_match(out$report$detail[out$report$resource == "cds_a"], "no saved CDS")
  expect_identical(status_of(out$report, "cds_b"), "unchanged")
  expect_true(attr(out$report, "written"))
  expect_length(out$warnings, 0L)
  expect_identical(manifest_resources(pkg), "cds_b")
  expect_no_error(projectData::data_manifest_validate(manifest_file(pkg), root = pkg))
  # The placeholder is not touched by the reconciliation.
  expect_true(file.exists(file.path(pkg, "data", "cds_a.rda")))
})

test_that("an entry whose placeholder was deleted is removed, and the directory is kept", {
  pkg <- registered_pkg(c("cds_a", "cds_b"))
  unlink(file.path(pkg, "data", "cds_b.rda"))
  saved <- file_state(file.path(pkg, "inst", "extdata", "cds_b"))

  out <- run_write(pkg)

  expect_identical(status_of(out$report, "cds_b"), "removed")
  expect_match(out$report$detail[out$report$resource == "cds_b"], "no placeholder")
  # Reported once, without a second "skipped" row or warning.
  expect_identical(sum(out$report$resource == "cds_b"), 1L)
  expect_length(out$warnings, 0L)
  expect_identical(manifest_resources(pkg), "cds_a")
  expect_identical(file_state(file.path(pkg, "inst", "extdata", "cds_b")), saved)
})

test_that("a directory without a placeholder and without an entry is still just skipped", {
  pkg <- registered_pkg("cds_a")
  add_fake_cds(pkg, "cds_new")

  out <- run_write(pkg)

  expect_identical(status_of(out$report, "cds_new"), "skipped")
  expect_true(any(vapply(out$warnings, inherits, NA, "projectData.monocle3_skipped")))
  expect_identical(manifest_resources(pkg), "cds_a")
})

test_that("stale entries are removed, new ones added and updated ones kept in one call", {
  pkg <- registered_pkg(c("cds_a", "cds_b"))
  unlink(file.path(pkg, "inst", "extdata", "cds_a"), recursive = TRUE)
  add_resource(pkg, "cds_c")

  out <- run_write(pkg)

  expect_identical(status_of(out$report, "cds_a"), "removed")
  expect_identical(status_of(out$report, "cds_c"), "added")
  expect_identical(manifest_resources(pkg), c("cds_b", "cds_c"))
})

test_that("a stale entry's object name is free again for a new resource", {
  pkg <- registered_pkg("cds_a")
  unlink(file.path(pkg, "inst", "extdata", "cds_a"), recursive = TRUE)
  write_manifest_text(pkg, c("ManifestVersion: 1", "",
                             "Resource: old", "Loader: projectData.monocle3::cds",
                             "Source: extdata/old", "Objects: cds_z"))
  add_resource(pkg, "cds_z")

  out <- run_write(pkg)

  expect_identical(status_of(out$report, "old"), "removed")
  expect_identical(status_of(out$report, "cds_z"), "added")
  expect_identical(manifest_resources(pkg), "cds_z")
})

test_that("entries of other adapters are preserved unchanged, even next to stale ones", {
  pkg <- new_pkg_source()
  add_other_thing(pkg)
  add_resource(pkg, "cds_a")
  write_manifest_text(pkg, c("ManifestVersion: 1", "", other_pkg_entry, "", own_entry("cds_a"),
                             "", own_entry("gone")))

  out <- run_write(pkg)

  expect_identical(status_of(out$report, "gone"), "removed")
  expect_identical(manifest_resources(pkg), c("other_res", "cds_a"))
  kept <- projectData::data_manifest_validate(manifest_file(pkg), root = pkg)[[1]]
  expect_identical(kept$loader, "other::loader")
  expect_identical(kept$objects, "other_obj")
  expect_identical(kept$title, "Hand-written title")
  expect_identical(kept$options, list(mode = "fast", level = "2"))
  expect_identical(kept$recorded_class, "some_class")
  expect_identical(kept$source, "extdata/other_thing")
})

test_that("an invalid entry of another adapter is reported, not repaired or removed", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  # other_thing does not exist, and cds_gone is stale.
  write_manifest_text(pkg, c("ManifestVersion: 1", "", other_pkg_entry, "", own_entry("cds_a"),
                             "", own_entry("cds_gone")))
  before <- file_state(pkg)

  expect_error(suppressMessages(write_monocle_manifest(pkg)),
               "other_res.*other_thing|other_thing.*other_res")
  expect_error(suppressMessages(write_monocle_manifest(pkg)), "fix other entries by hand")
  expect_identical(file_state(pkg), before)
})

test_that("an unchanged manifest with an invalid unrelated entry is reported as an error", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  write_manifest_text(pkg, c("ManifestVersion: 1", "", other_pkg_entry, "", own_entry("cds_a")))
  before <- file_state(pkg)

  expect_error(suppressMessages(write_monocle_manifest(pkg)), "other_thing")
  expect_identical(file_state(pkg), before)
})

test_that("a resource owned by another adapter is never taken over, and stale entries still go", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  add_resource(pkg, "cds_b")
  write_manifest_text(pkg, c(
    "ManifestVersion: 1", "",
    "Resource: cds_a", "Loader: other::loader", "Objects: cds_a", "Title: mine", "",
    own_entry("cds_old")
  ))

  out <- run_write(pkg)

  expect_identical(status_of(out$report, "cds_a"), "conflict")
  expect_identical(status_of(out$report, "cds_old"), "removed")
  expect_identical(status_of(out$report, "cds_b"), "added")
  d <- projectData::data_manifest_validate(manifest_file(pkg), root = pkg)
  expect_identical(vapply(d, function(x) x$resource, ""), c("cds_a", "cds_b"))
  expect_identical(d[[1]]$loader, "other::loader")
  expect_identical(d[[1]]$title, "mine")
})

test_that("an object name held by another adapter blocks only that resource", {
  pkg <- new_pkg_source()
  add_resource(pkg, "cds_a")
  write_manifest_text(pkg, c("ManifestVersion: 1", "",
                             "Resource: elsewhere", "Loader: other::loader", "Objects: cds_a"))
  before <- file_state(pkg)

  out <- run_write(pkg)

  expect_identical(out$report$status, "conflict")
  expect_identical(file_state(pkg), before)
})

test_that("malformed manifests are never overwritten", {
  malformed <- list(
    "not a manifest" = "not: a: manifest",
    "empty file" = "",
    "no version" = c("Resource: a", "Loader: x::y"),
    "unsupported version" = c("ManifestVersion: 2", "", "Resource: a", "Loader: x::y"),
    "unknown field" = c("ManifestVersion: 1", "", "Resource: a", "Loader: x::y", "Bogus: 1"),
    "no loader" = c("ManifestVersion: 1", "", "Resource: a"),
    "no resource" = c("ManifestVersion: 1", "", "Loader: x::y"),
    "duplicate resource" = c("ManifestVersion: 1", "", "Resource: a", "Loader: x::y",
                             "", "Resource: a", "Loader: x::y"),
    "bad options" = c("ManifestVersion: 1", "", "Resource: a", "Loader: x::y", "Options: nokey")
  )
  for (case in names(malformed)) {
    pkg <- registered_pkg("cds_a")
    add_resource(pkg, "cds_b")
    write_manifest_text(pkg, malformed[[case]])
    before <- file_state(pkg)
    expect_error(suppressMessages(write_monocle_manifest(pkg)), "was not modified", info = case)
    expect_identical(file_state(pkg), before, info = case)
  }
})

test_that("a binary manifest is not overwritten", {
  pkg <- registered_pkg("cds_a")
  writeBin(as.raw(c(0:255, 0:255)), manifest_file(pkg))
  before <- file_state(pkg)
  expect_error(suppressMessages(write_monocle_manifest(pkg)))
  expect_identical(file_state(pkg), before)
})

test_that("reconciliation is idempotent and leaves unchanged files and times alone", {
  pkg <- new_pkg_source()
  add_other_thing(pkg)
  write_manifest_text(pkg, c("ManifestVersion: 1", "", other_pkg_entry, "", own_entry("gone")))
  add_resource(pkg, "cds_a")

  first <- run_write(pkg)
  after_first <- file_state(pkg)
  second <- run_write(pkg)
  third <- run_write(pkg)

  expect_true(attr(first$report, "written"))
  expect_false(attr(second$report, "written"))
  expect_false(attr(third$report, "written"))
  expect_identical(second$report$status, "unchanged")
  expect_identical(file_state(pkg), after_first)
  expect_identical(manifest_resources(pkg), c("other_res", "cds_a"))
})

test_that("nothing is said when nothing changes, and a concise summary when something does", {
  pkg <- new_pkg_source()
  add_other_thing(pkg)
  write_manifest_text(pkg, c("ManifestVersion: 1", "", other_pkg_entry, "", own_entry("cds_b"),
                             "", own_entry("cds_old")))
  add_resource(pkg, "cds_a")
  add_resource(pkg, "cds_b")

  msgs <- testthat::capture_messages(write_monocle_manifest(pkg))
  text <- paste(msgs, collapse = "")
  expect_match(text, "projectData.monocle3: manifest updated", fixed = TRUE)
  expect_match(text, "  Added: cds_a", fixed = TRUE)
  expect_match(text, "  Removed stale: cds_old", fixed = TRUE)
  expect_match(text, "  Preserved: 1 unrelated resource\n?$")
  expect_no_match(text, "Updated")

  expect_silent(write_monocle_manifest(pkg))
  expect_silent(write_monocle_manifest(pkg))
})

test_that("only unrelated entries remain when every Monocle resource is gone", {
  pkg <- new_pkg_source()
  add_other_thing(pkg)
  add_resource(pkg, "cds_a")
  write_manifest_text(pkg, c("ManifestVersion: 1", "", other_pkg_entry, "", own_entry("cds_a")))
  run_write(pkg)
  unlink(file.path(pkg, "inst", "extdata", "cds_a"), recursive = TRUE)

  out <- run_write(pkg)

  expect_identical(status_of(out$report, "cds_a"), "removed")
  expect_identical(manifest_resources(pkg), "other_res")
  expect_no_error(projectData::data_manifest_validate(manifest_file(pkg), root = pkg))
})

test_that("the manifest is removed when no entry at all remains", {
  pkg <- registered_pkg(c("cds_a", "cds_b"))
  unlink(file.path(pkg, "inst", "extdata", c("cds_a", "cds_b")), recursive = TRUE)
  placeholders <- file_state(file.path(pkg, "data"))

  msgs <- testthat::capture_messages(out <- write_monocle_manifest(pkg))

  expect_identical(sort(out$resource), c("cds_a", "cds_b"))
  expect_true(all(out$status == "removed"))
  expect_true(attr(out, "written"))
  expect_false(file.exists(manifest_file(pkg)))
  expect_false(dir.exists(dirname(manifest_file(pkg))))
  expect_match(paste(msgs, collapse = ""), "manifest file was removed")
  # Placeholders stay: reconciliation deletes no data files.
  expect_identical(file_state(file.path(pkg, "data")), placeholders)

  # Running again has nothing to do.
  expect_silent(write_monocle_manifest(pkg))
  expect_false(file.exists(manifest_file(pkg)))
})

test_that("the directory of a removed manifest is kept when it holds other files", {
  pkg <- registered_pkg("cds_a")
  writeLines("keep", file.path(dirname(manifest_file(pkg)), "notes.txt"))
  unlink(file.path(pkg, "inst", "extdata", "cds_a"), recursive = TRUE)

  run_write(pkg)

  expect_false(file.exists(manifest_file(pkg)))
  expect_true(file.exists(file.path(dirname(manifest_file(pkg)), "notes.txt")))
})

test_that("reconciliation never deletes saved directories or placeholders", {
  pkg <- registered_pkg(c("cds_a", "cds_b", "cds_c"))
  unlink(file.path(pkg, "inst", "extdata", "cds_a"), recursive = TRUE)
  unlink(file.path(pkg, "data", "cds_b.rda"))
  extdata <- file_state(file.path(pkg, "inst", "extdata"))
  data <- file_state(file.path(pkg, "data"))

  run_write(pkg)

  expect_identical(file_state(file.path(pkg, "inst", "extdata")), extdata)
  expect_identical(file_state(file.path(pkg, "data")), data)
  expect_identical(manifest_resources(pkg), "cds_c")
})

test_that("the structural reader agrees with projectData's reader on valid manifests", {
  pkg <- new_pkg_source()
  add_other_thing(pkg)
  add_resource(pkg, "cds_a")
  write_manifest_text(pkg, c(
    "ManifestVersion: 1", "", other_pkg_entry, "", own_entry("cds_a"), "",
    "Resource: multi", "Loader: other::loader", "Source: extdata/other_thing",
    "Objects: o1, o2", "Title: T", "HelpTopic: h", "AdapterPackage: some.pkg",
    "AdapterExport: some_export", "", "Resource: bare", "Loader: other::loader"
  ))

  expect_identical(
    read_existing_manifest(manifest_file(pkg)),
    unclass(projectData::data_manifest_validate(manifest_file(pkg), root = pkg))
  )
})

test_that("a manifest is created when the package has none and reconciled when only stale entries exist", {
  pkg <- new_pkg_source()
  expect_identical(read_existing_manifest(manifest_file(pkg)), list())
  write_manifest_text(pkg, c("ManifestVersion: 1", "", own_entry("ghost")))

  out <- run_write(pkg)

  expect_identical(out$report$status, "removed")
  expect_false(file.exists(manifest_file(pkg)))
})
