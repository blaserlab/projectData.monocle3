# Overwrite authorization: which existing resources save_monocle_cds() may replace.
# See resource_ownership() in R/ownership.R.
#
# The first half judges ownership on small synthetic directories and needs
# neither monocle3 nor BPCells. The second half runs save_monocle_cds() end to
# end (real fixtures) and checks that a refusal leaves everything byte-identical.

own_fail <- function(..., class = NULL) {
  stop(structure(
    class = c(class, "projectData.monocle3_save_error", "error", "condition"),
    list(message = paste0(...), call = NULL)
  ))
}

# check_save_targets() with the manifest as the real save reads it.
targets <- function(pkg, name = "ds", overwrite = TRUE) {
  check_save_targets(pkg, name, overwrite, own_fail,
                     read_existing_manifest(manifest_path(pkg)))
}

own_manifest <- function(pkg, name = "ds", loader = "projectData.monocle3::cds",
                         source = paste0("extdata/", name), objects = name) {
  write_manifest_text(pkg, c(
    "ManifestVersion: 1", "", paste0("Resource: ", name), paste0("Loader: ", loader),
    paste0("Source: ", source), paste0("Objects: ", objects)
  ))
}

# A valid-looking native save (the loader's own validation passes).
own_valid <- function(pkg, name = "ds") add_fake_cds(pkg, name)

# Same, with the file index replaced by something that is not a Monocle index.
own_malformed_index <- function(pkg, name = "ds", value = list(whatever = 1)) {
  dir <- add_fake_cds(pkg, name, index = FALSE, create = FALSE)
  saveRDS(value, file.path(dir, "file_index.rds"))
  dir
}

expect_refused <- function(pkg, class, regexp = NULL, name = "ds", overwrite = TRUE) {
  before <- file_state(pkg)
  expect_error(targets(pkg, name, overwrite), regexp, class = class)
  expect_identical(file_state(pkg), before)
}

# Evidence rule -----------------------------------------------------------

test_that("a valid native save with a recognized placeholder is owned, legacy or classed", {
  for (placeholder in list(legacy_placeholder, make_placeholder("ds", "fakedata"))) {
    pkg <- new_pkg_source("fakedata")
    own_valid(pkg)
    add_placeholder(pkg, "ds", placeholder)
    t <- targets(pkg)
    expect_identical(t$state, "valid")
    expect_true(t$replaced)
    expect_identical(t$cds, file.path(pkg, "inst", "extdata", "ds"))
  }
})

test_that("a valid native save with only a manifest entry of this loader is owned", {
  pkg <- new_pkg_source()
  own_valid(pkg)
  own_manifest(pkg)
  expect_identical(targets(pkg)$state, "valid")
})

test_that("a valid native save with neither manifest entry nor placeholder is ambiguous", {
  pkg <- new_pkg_source()
  own_valid(pkg)
  expect_refused(pkg, "projectData.monocle3_ambiguous_ownership", "cannot be established")
  # An existing resource is never an invitation to use overwrite.
  err <- tryCatch(targets(pkg), error = identity)
  expect_false(grepl("overwrite = TRUE", conditionMessage(err), fixed = TRUE))
  expect_s3_class(err, "projectData.monocle3_save_error")
  expect_error(targets(pkg, overwrite = FALSE), class = "projectData.monocle3_ambiguous_ownership")
})

test_that("an unrelated directory with object.rds is refused", {
  pkg <- new_pkg_source()
  dir <- file.path(pkg, "inst", "extdata", "ds")
  dir.create(dir, recursive = TRUE)
  saveRDS(1:3, file.path(dir, "object.rds"))
  add_placeholder(pkg, "ds")
  own_manifest(pkg)
  # Even with a placeholder and a manifest entry: the directory holds an entry
  # that no Monocle save has.
  expect_refused(pkg, "projectData.monocle3_not_owned", "object.rds")
  unlink(c(file.path(pkg, "data", "ds.rda"), manifest_file(pkg)))
  expect_refused(pkg, "projectData.monocle3_not_owned", "not a saved Monocle directory")
})

test_that("a directory with only a BPCells marker is refused", {
  pkg <- new_pkg_source()
  dir <- file.path(pkg, "inst", "extdata", "ds")
  dir.create(file.path(dir, "bpcells_matrix_dir"), recursive = TRUE)
  writeLines("x", file.path(dir, "bpcells_matrix_dir", "val"))
  expect_refused(pkg, "projectData.monocle3_ambiguous_ownership", "cannot be established")
  add_placeholder(pkg, "ds")
  expect_refused(pkg, "projectData.monocle3_ambiguous_ownership", "cannot be established")
})

test_that("a malformed file index alone is refused; independent evidence allows recovery", {
  for (bad in list(list(whatever = 1), "text", list(save_function = "save_monocle_objects"))) {
    pkg <- new_pkg_source()
    own_malformed_index(pkg, value = bad)
    expect_refused(pkg, "projectData.monocle3_ambiguous_ownership", "cannot be established")
    add_placeholder(pkg, "ds")
    expect_refused(pkg, "projectData.monocle3_ambiguous_ownership")
    unlink(file.path(pkg, "data", "ds.rda"))
    own_manifest(pkg)
    expect_refused(pkg, "projectData.monocle3_ambiguous_ownership")
    # The manifest and the placeholder agree with each other: recoverable.
    add_placeholder(pkg, "ds")
    t <- targets(pkg)
    expect_identical(t$state, "damaged")
    expect_setequal(t$evidence, c("a manifest entry of this loader", "a recognized placeholder"))
  }
  # An index that is not even an rds file.
  pkg <- new_pkg_source()
  dir <- add_fake_cds(pkg, "ds", index = FALSE, create = FALSE)
  writeLines("not rds", file.path(dir, "file_index.rds"))
  expect_refused(pkg, "projectData.monocle3_ambiguous_ownership")
})

test_that("a damaged owned save (listed files missing) is recoverable only with overwrite", {
  pkg <- new_pkg_source()
  own_valid(pkg)
  add_placeholder(pkg, "ds")
  unlink(file.path(pkg, "inst", "extdata", "ds", "cds_object.rds"))
  t <- targets(pkg)
  expect_identical(t$state, "damaged")
  expect_match(t$reason, "missing saved file")
  expect_true(t$replaced)

  before <- file_state(pkg)
  expect_error(targets(pkg, overwrite = FALSE), "damaged", class = "projectData.monocle3_damaged")
  expect_error(targets(pkg, overwrite = FALSE), class = "projectData.monocle3_exists")
  expect_identical(file_state(pkg), before)
})

test_that("evidence from the index alone is not enough, however complete the save", {
  pkg <- new_pkg_source()
  own_valid(pkg)
  unlink(file.path(pkg, "inst", "extdata", "ds", "cds_object.rds"))
  expect_refused(pkg, "projectData.monocle3_ambiguous_ownership")
})

test_that("entries that neither the index nor Monocle account for are refused", {
  pkg <- new_pkg_source()
  own_valid(pkg)
  add_placeholder(pkg, "ds")
  writeLines("mine", file.path(pkg, "inst", "extdata", "ds", "notes.txt"))
  expect_refused(pkg, "projectData.monocle3_not_owned", "notes.txt")
  unlink(file.path(pkg, "inst", "extdata", "ds", "notes.txt"))
  dir.create(file.path(pkg, "inst", "extdata", "ds", "empty_subdir"))
  expect_refused(pkg, "projectData.monocle3_not_owned", "empty_subdir")
})

test_that("files listed in the index (such as reduction models) are accounted for", {
  pkg <- new_pkg_source()
  files <- rbind(fake_files(), data.frame(
    cds_object = "reduction", file_format = "annoy", file_path = "rdd_umap_model.idx",
    stringsAsFactors = FALSE))
  add_fake_cds(pkg, "ds", files = files)
  add_placeholder(pkg, "ds")
  expect_identical(targets(pkg)$state, "valid")
})

test_that("a manifest entry of another loader is never overwritten", {
  pkg <- new_pkg_source()
  own_valid(pkg)
  add_placeholder(pkg, "ds")
  own_manifest(pkg, loader = "other::loader")
  expect_refused(pkg, "projectData.monocle3_conflict", "other::loader")
  expect_refused(pkg, "projectData.monocle3_conflict", "other::loader", overwrite = FALSE)

  # Also for an empty directory.
  unlink(file.path(pkg, "inst", "extdata", "ds"), recursive = TRUE)
  dir.create(file.path(pkg, "inst", "extdata", "ds"))
  expect_refused(pkg, "projectData.monocle3_conflict", "other::loader")
})

test_that("a manifest entry of this loader that disagrees with the directory is ambiguous", {
  pkg <- new_pkg_source()
  own_valid(pkg)
  add_placeholder(pkg, "ds")
  own_manifest(pkg, source = "extdata/elsewhere")
  expect_refused(pkg, "projectData.monocle3_ambiguous_ownership", "does not agree")
})

test_that("a real data file is never replaced as a placeholder", {
  pkg <- new_pkg_source()
  own_valid(pkg)
  own_manifest(pkg)
  add_rda(pkg, "ds", list(ds = data.frame(a = 1:3)))
  expect_refused(pkg, "projectData.monocle3_placeholder_not_recognized", "real dataset")
  # Also without any saved directory.
  unlink(file.path(pkg, "inst"), recursive = TRUE)
  expect_refused(pkg, "projectData.monocle3_placeholder_not_recognized")
  # A placeholder of the right class for another dataset is not this one's.
  add_placeholder(pkg, "ds", make_placeholder("other", "fakedata"))
  expect_refused(pkg, "projectData.monocle3_placeholder_not_recognized")
})

test_that("an empty directory may be replaced, but only with overwrite", {
  pkg <- new_pkg_source()
  dir.create(file.path(pkg, "inst", "extdata", "ds"), recursive = TRUE)
  t <- targets(pkg)
  expect_identical(t$state, "empty")
  expect_true(t$replaced)
  expect_error(targets(pkg, overwrite = FALSE), class = "projectData.monocle3_exists")
})

test_that("a file where the directory should be is refused", {
  pkg <- new_pkg_source()
  dir.create(file.path(pkg, "inst", "extdata"), recursive = TRUE)
  writeLines("x", file.path(pkg, "inst", "extdata", "ds"))
  expect_refused(pkg, "projectData.monocle3_not_owned", "not a directory")
})

test_that("nothing existing means a normal save, and a placeholder alone is replaceable", {
  pkg <- new_pkg_source()
  t <- targets(pkg)
  expect_false(t$replaced)
  expect_identical(t$state, "none")
  add_placeholder(pkg, "ds")
  expect_true(targets(pkg)$replaced)
})

test_that("discovery is unchanged: any marker still makes a candidate", {
  dir <- withr::local_tempdir()
  for (marker in c("file_index.rds", "cds_object.rds", "bpcells_matrix_dir")) {
    d <- file.path(dir, marker)
    dir.create(d)
    file.create(file.path(d, marker))
    expect_true(looks_like_monocle_save(d))
  }
})

test_that("the index structure check agrees with the loader's validation", {
  expect_null(file_index_listing_problem(list(save_function = "save_monocle_objects",
                                              files = fake_files()), "extdata/ds"))
  # Judges the listing only: an hdf5 save is a native index the loader rejects.
  hdf5 <- fake_files()
  hdf5$file_format[1] <- "hdf5"
  index <- list(save_function = "save_monocle_objects", files = hdf5)
  expect_null(file_index_listing_problem(index, "extdata/ds"))
  expect_match(validate_file_index(index, tempdir(), "extdata/ds"), "rds format")
})

# End to end ------------------------------------------------------------------

# A package with a saved resource "ds", for the human fixture.
saved_pkg <- function(name = "ds", env = parent.frame()) {
  pkg <- new_save_pkg(env = env)
  save_quiet(fixture_bpcells_cds("human"), name, pkg)
  pkg
}

test_that("rejected overwrites change nothing, leave no stage and do not touch the CDS", {
  skip_if_no_monocle()
  cds <- fixture_bpcells_cds("mouse")
  snapshot <- cds
  backing <- file_state(cds_fixtures()$mouse$saved)

  cases <- list(
    unrelated = function(pkg) {
      dir.create(file.path(pkg, "inst", "extdata", "ds"), recursive = TRUE)
      saveRDS(1, file.path(pkg, "inst", "extdata", "ds", "object.rds"))
    },
    bpcells_only = function(pkg) {
      dir.create(file.path(pkg, "inst", "extdata", "ds", "bpcells_matrix_dir"), recursive = TRUE)
    },
    malformed_index = function(pkg) own_malformed_index(pkg),
    valid_unclaimed = function(pkg) own_valid(pkg),
    other_loader = function(pkg) {
      own_valid(pkg)
      add_placeholder(pkg, "ds")
      own_manifest(pkg, loader = "other::loader")
    },
    real_rda = function(pkg) add_rda(pkg, "ds", list(ds = data.frame(a = 1)))
  )
  for (case in names(cases)) {
    pkg <- new_save_pkg()
    cases[[case]](pkg)
    before <- file_state(pkg)
    expect_error(save_monocle_cds(cds, "ds", pkg, overwrite = TRUE),
                 class = "projectData.monocle3_save_error", info = case)
    expect_identical(file_state(pkg), before, info = case)
    expect_length(stage_dirs(pkg), 0L)
  }
  expect_identical(cds, snapshot)
  expect_identical(file_state(cds_fixtures()$mouse$saved), backing)
})

test_that("a valid resource whose manifest is absent is replaced and re-registered", {
  skip_if_no_monocle()
  pkg <- saved_pkg()
  unlink(dirname(manifest_file(pkg)), recursive = TRUE)
  out <- save_quiet(fixture_bpcells_cds("mouse"), "ds", pkg, overwrite = TRUE)
  expect_true(out$result$replaced)
  expect_identical(out$result$manifest_status, "added")
  expect_identical(manifest_resources(pkg), "ds")
  expect_identical(dim(open_saved(pkg, "ds")), dim(fixture_bpcells_cds("mouse")))
})

test_that("a valid resource whose placeholder is missing but whose manifest entry exists is replaced", {
  skip_if_no_monocle()
  pkg <- saved_pkg()
  unlink(file.path(pkg, "data", "ds.rda"))
  out <- save_quiet(fixture_bpcells_cds("mouse"), "ds", pkg, overwrite = TRUE)
  expect_true(out$result$replaced)
  expect_true(file.exists(file.path(pkg, "data", "ds.rda")))
  expect_identical(dim(open_saved(pkg, "ds")), dim(fixture_bpcells_cds("mouse")))
})

test_that("a resource with a historical placeholder is replaced and gets a classed one", {
  skip_if_no_monocle()
  pkg <- saved_pkg()
  unlink(dirname(manifest_file(pkg)), recursive = TRUE)
  add_placeholder(pkg, "ds")
  out <- save_quiet(fixture_bpcells_cds("mouse"), "ds", pkg, overwrite = TRUE)
  expect_true(out$result$replaced)
  expect_s3_class(load_placeholder(pkg, "ds")$object, "projectData_monocle3_placeholder")
})

test_that("a corrupted owned resource is recovered, and overwrite = FALSE still refuses", {
  skip_if_no_monocle()
  pkg <- saved_pkg()
  unlink(file.path(pkg, "inst", "extdata", "ds", "cds_object.rds"))
  before <- file_state(pkg)

  expect_error(save_monocle_cds(fixture_bpcells_cds("mouse"), "ds", pkg),
               class = "projectData.monocle3_damaged")
  expect_identical(file_state(pkg), before)

  msgs <- testthat::capture_messages(
    save_monocle_cds(fixture_bpcells_cds("mouse"), "ds", pkg, overwrite = TRUE)
  )
  expect_match(paste(msgs, collapse = ""), "was damaged")
  expect_identical(dim(open_saved(pkg, "ds")), dim(fixture_bpcells_cds("mouse")))
  expect_length(stage_dirs(pkg), 0L)
})

test_that("a failed recovery of a damaged resource restores it exactly as it was", {
  skip_if_no_monocle()
  pkg <- saved_pkg()
  unlink(file.path(pkg, "inst", "extdata", "ds", "cds_object.rds"))
  before <- file_state(pkg)

  testthat::local_mocked_bindings(
    write_planned_manifest = function(plan, manifest, root) stop("manifest not writable")
  )
  expect_error(
    save_monocle_cds(fixture_bpcells_cds("mouse"), "ds", pkg, overwrite = TRUE),
    "manifest not writable.*previous files were restored"
  )
  expect_identical(file_state(pkg), before)
  expect_length(stage_dirs(pkg), 0L)
})

test_that("records of other adapters survive an authorized overwrite unchanged", {
  skip_if_no_monocle()
  pkg <- saved_pkg()
  other <- c("", "Resource: other_res", "Loader: other::loader",
             "Source: extdata/other_thing", "Objects: other_obj", "Title: Hand-written title")
  dir.create(file.path(pkg, "inst", "extdata", "other_thing"))
  writeLines("x", file.path(pkg, "inst", "extdata", "other_thing", "f.txt"))
  text <- readLines(manifest_file(pkg))
  writeLines(c(text, other), manifest_file(pkg))
  keep <- function() {
    d <- read_existing_manifest(manifest_file(pkg))
    d[vapply(d, function(x) identical(x$resource, "other_res"), NA)]
  }
  before <- keep()
  expect_length(before, 1L)

  save_quiet(fixture_bpcells_cds("mouse"), "ds", pkg, overwrite = TRUE)

  expect_identical(keep(), before)
  expect_setequal(manifest_resources(pkg), c("ds", "other_res"))
})

test_that("overwrite = FALSE rejects an existing owned resource and changes nothing", {
  skip_if_no_monocle()
  pkg <- saved_pkg()
  before <- file_state(pkg)
  expect_error(save_monocle_cds(fixture_bpcells_cds("mouse"), "ds", pkg), "overwrite = TRUE",
               class = "projectData.monocle3_exists")
  expect_identical(file_state(pkg), before)
})
