# save_monocle_cds(): validation, saving, overwrite and failure behavior, and
# round trips through the adapter. Destructive work happens in temporary
# package source trees; the installed fixture package is never touched.

test_that("invalid inputs fail before anything is written", {
  skip_if_no_monocle()
  cds <- fixture_bpcells_cds()
  pkg <- new_save_pkg()
  before <- file_state(pkg)
  fails <- function(...) expect_error(save_monocle_cds(...), class = "projectData.monocle3_save_error")

  fails("not a cds", "ok_name", pkg)
  fails(cds, NA_character_, pkg)
  fails(cds, "", pkg)
  fails(cds, c("a", "b"), pkg)
  fails(cds, 1, pkg)
  fails(cds, "1abc", pkg)
  fails(cds, "has space", pkg)
  fails(cds, "a/b", pkg)
  fails(cds, "..", pkg)
  fails(cds, ".hidden", pkg)
  fails(cds, "if", pkg)
  fails(cds, "ok_name", pkg, overwrite = "yes")
  expect_error(save_monocle_cds(cds, "ok_name", file.path(pkg, "missing")),
               class = "projectData.monocle3_package_dir_error")
  expect_error(save_monocle_cds(cds, "ok_name", tempdir()),
               class = "projectData.monocle3_package_dir_error")

  expect_identical(file_state(pkg), before)
  expect_length(stage_dirs(pkg), 0L)
})

test_that("convert_to_bpcells is no longer part of the interface", {
  expect_named(formals(save_monocle_cds), c("cds", "name", "package_dir", "overwrite"))
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  before <- file_state(pkg)
  expect_error(save_monocle_cds(fixture_bpcells_cds(), "ds", pkg, convert_to_bpcells = TRUE),
               "unused argument")
  expect_identical(file_state(pkg), before)
})

test_that("a BPCells-backed CDS is saved with a native directory, placeholder and manifest entry", {
  skip_if_no_monocle()
  cds <- fixture_bpcells_cds()
  pkg <- new_save_pkg()
  ordinary_before <- file_state(file.path(pkg, "data"))
  cwd <- getwd()
  cwd_before <- list.files(cwd, all.files = TRUE)

  out <- save_quiet(cds, "cds_main_adults", pkg)

  expect_length(out$warnings, 0L)
  expect_identical(getwd(), cwd)
  expect_identical(list.files(cwd, all.files = TRUE), cwd_before)
  expect_length(stage_dirs(pkg), 0L)
  expect_identical(out$result$manifest_status, "added")
  expect_false(out$result$replaced)

  # Native Monocle layout, no archive.
  dir <- file.path(pkg, "inst", "extdata", "cds_main_adults")
  expect_true(all(c("file_index.rds", "cds_object.rds", "bpcells_matrix_dir") %in% list.files(dir)))
  expect_false(any(grepl("\\.tar", list.files(dir))))
  expect_true(dir.exists(file.path(dir, "bpcells_matrix_dir")))
  expect_identical(readRDS(file.path(dir, "file_index.rds"))$save_function, "save_monocle_objects")
  expect_true(validate_monocle_cds(
    list(source = "extdata/cds_main_adults", objects = "cds_main_adults"),
    file.path(pkg, "inst"), list()
  ))

  # Placeholder: one object, right name, class and metadata.
  loaded <- load_placeholder(pkg, "cds_main_adults")
  expect_identical(loaded$names, "cds_main_adults")
  expect_s3_class(loaded$object, "projectData_monocle3_placeholder")
  expect_identical(attr(loaded$object, "object_name"), "cds_main_adults")
  expect_identical(attr(loaded$object, "package"), "savedata")
  expect_true(is_recognized_placeholder(
    inspect_rda(file.path(pkg, "data", "cds_main_adults.rda")), "cds_main_adults"))

  # Manifest entry with the expected descriptor.
  d <- projectData::data_manifest_validate(manifest_file(pkg), root = pkg)
  expect_length(d, 1L)
  expect_identical(d[[1]]$resource, "cds_main_adults")
  expect_identical(d[[1]]$loader, "projectData.monocle3::cds")
  expect_identical(d[[1]]$source, "extdata/cds_main_adults")
  expect_identical(d[[1]]$objects, "cds_main_adults")
  expect_identical(d[[1]]$adapter$package, "projectData.monocle3")
  expect_identical(d[[1]]$adapter$export, "projectData_loaders")
  expect_identical(d[[1]]$recorded_class, "cell_data_set")
  expect_identical(d[[1]]$help_topic, "cds_main_adults")

  # Unrelated ordinary data are untouched.
  after <- file_state(file.path(pkg, "data"))
  keep <- grepl("ordinary_data", ordinary_before$files)
  expect_identical(after$md5[match(ordinary_before$files[keep], after$files)],
                   ordinary_before$md5[keep])
})

test_that("two datasets can be saved into one package, and an unrelated manifest entry is kept", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  dir.create(file.path(pkg, "inst", "extdata", "other_thing"), recursive = TRUE)
  writeLines("x", file.path(pkg, "inst", "extdata", "other_thing", "payload.txt"))
  write_manifest_text(pkg, c("ManifestVersion: 1", "", save_other_entry))

  save_quiet(fixture_bpcells_cds("human"), "human_cds", pkg)
  second <- save_quiet(fixture_bpcells_cds("mouse"), "mouse_cds", pkg)
  expect_identical(second$result$manifest_status, "added")

  expect_identical(manifest_resources(pkg), c("other_res", "human_cds", "mouse_cds"))
  d <- projectData::data_manifest_validate(manifest_file(pkg), root = pkg)
  expect_identical(d[[1]]$loader, "other::loader")
  expect_identical(d[[1]]$title, "Hand-written title")

  human <- open_saved(pkg, "human_cds")
  mouse <- open_saved(pkg, "mouse_cds")
  expect_identical(dim(human), dim(fixture_bpcells_cds("human")))
  expect_identical(dim(mouse), dim(fixture_bpcells_cds("mouse")))
  expect_false(identical(dim(human), dim(mouse)))
})

test_that("existing targets are rejected without overwrite, leaving all files alone", {
  skip_if_no_monocle()
  cds <- fixture_bpcells_cds()
  pkg <- new_save_pkg()
  save_quiet(cds, "cds_a", pkg)
  before <- file_state(pkg)

  expect_error(save_monocle_cds(cds, "cds_a", pkg), "overwrite = TRUE",
               class = "projectData.monocle3_save_error")
  expect_identical(file_state(pkg), before)
  expect_length(stage_dirs(pkg), 0L)

  # A placeholder alone also counts as an existing target.
  file.copy(file.path(pkg, "data", "cds_a.rda"), file.path(pkg, "data", "cds_b.rda"))
  # (object name inside differs, so it is not a placeholder for cds_b)
  expect_error(save_monocle_cds(cds, "cds_b", pkg), class = "projectData.monocle3_save_error")
  unlink(file.path(pkg, "data", "cds_b.rda"))
  add_placeholder(pkg, "cds_c", make_placeholder("cds_c", "savedata"))
  expect_error(save_monocle_cds(cds, "cds_c", pkg), "overwrite = TRUE",
               class = "projectData.monocle3_save_error")
})

test_that("real datasets and foreign directories are never replaced, even with overwrite", {
  skip_if_no_monocle()
  cds <- fixture_bpcells_cds()
  pkg <- new_save_pkg()
  add_rda(pkg, "real", list(real = data.frame(a = 1)))
  dir.create(file.path(pkg, "inst", "extdata", "stuff"), recursive = TRUE)
  writeLines("x", file.path(pkg, "inst", "extdata", "stuff", "payload.txt"))
  before <- file_state(pkg)

  expect_error(save_monocle_cds(cds, "real", pkg, overwrite = TRUE), "real dataset",
               class = "projectData.monocle3_save_error")
  expect_error(save_monocle_cds(cds, "stuff", pkg, overwrite = TRUE), "not a saved Monocle",
               class = "projectData.monocle3_save_error")
  expect_identical(file_state(pkg), before)
})

test_that("overwrite = TRUE replaces the dataset and placeholder and keeps manual manifest fields", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  save_quiet(fixture_bpcells_cds("human"), "ds", pkg)
  expect_identical(dim(open_saved(pkg, "ds")), dim(fixture_bpcells_cds("human")))

  # A hand-added Title survives a replacement.
  text <- readLines(manifest_file(pkg))
  writeLines(append(text, "Title: Keep me", after = length(text)), manifest_file(pkg))

  out <- save_quiet(fixture_bpcells_cds("mouse"), "ds", pkg, overwrite = TRUE)

  expect_true(out$result$replaced)
  expect_identical(out$result$manifest_status, "unchanged")
  expect_identical(dim(open_saved(pkg, "ds")), dim(fixture_bpcells_cds("mouse")))
  expect_identical(manifest_resources(pkg), "ds")
  d <- projectData::data_manifest_validate(manifest_file(pkg), root = pkg)
  expect_identical(d[[1]]$title, "Keep me")
  expect_length(stage_dirs(pkg), 0L)
  expect_identical(list.files(file.path(pkg, "data")), c("ds.rda", "ordinary_data.rda"))
  expect_identical(list.files(file.path(pkg, "inst", "extdata")), "ds")
  expect_identical(load_placeholder(pkg, "ds")$names, "ds")
})

test_that("saving is idempotent for the manifest", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  cds <- fixture_bpcells_cds()
  save_quiet(cds, "ds", pkg)
  manifest_before <- file_state(dirname(manifest_file(pkg)))
  out <- save_quiet(cds, "ds", pkg, overwrite = TRUE)
  expect_identical(out$result$manifest_status, "unchanged")
  expect_identical(file_state(dirname(manifest_file(pkg)))$md5, manifest_before$md5)
  expect_identical(manifest_resources(pkg), "ds")
})

test_that("a conflict with another loader's manifest entry is rejected before writing", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  write_manifest_text(pkg, c("ManifestVersion: 1", "",
                             "Resource: ds", "Loader: other::loader", "Objects: ds"))
  before <- file_state(pkg)
  expect_error(save_monocle_cds(fixture_bpcells_cds(), "ds", pkg),
               "other::loader", class = "projectData.monocle3_conflict")
  expect_identical(file_state(pkg), before)

  write_manifest_text(pkg, c("ManifestVersion: 1", "",
                             "Resource: elsewhere", "Loader: other::loader", "Objects: ds"))
  before <- file_state(pkg)
  expect_error(save_monocle_cds(fixture_bpcells_cds(), "ds", pkg),
               class = "projectData.monocle3_conflict")
  expect_identical(file_state(pkg), before)
})

test_that("an invalid existing manifest stops the save and is left untouched", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  write_manifest_text(pkg, c("ManifestVersion: 1", "", "Resource: dup", "Loader: x::y",
                             "Objects: o", "", "Resource: dup", "Loader: x::y"))
  before <- file_state(pkg)
  expect_error(save_monocle_cds(fixture_bpcells_cds(), "ds", pkg), "manifest")
  expect_identical(file_state(pkg), before)
})

test_that("a failed save step preserves existing resources and leaves no staging directory", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  save_quiet(fixture_bpcells_cds("human"), "ds", pkg)
  before <- file_state(pkg)

  testthat::local_mocked_bindings(
    save_staged_cds = function(cds, directory) {
      dir.create(directory, recursive = TRUE)
      writeLines("partial", file.path(directory, "cds_object.rds"))
      stop("disk full")
    }
  )
  expect_error(save_monocle_cds(fixture_bpcells_cds("mouse"), "ds", pkg, overwrite = TRUE),
               "disk full")
  expect_identical(file_state(pkg), before)
  expect_length(stage_dirs(pkg), 0L)

  # A fresh target is not left half-written either.
  expect_error(save_monocle_cds(fixture_bpcells_cds("mouse"), "fresh", pkg), "disk full")
  expect_false(dir.exists(file.path(pkg, "inst", "extdata", "fresh")))
  expect_false(file.exists(file.path(pkg, "data", "fresh.rda")))
  expect_identical(file_state(pkg), before)
})

test_that("a failure while committing restores the previous files", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  save_quiet(fixture_bpcells_cds("human"), "ds", pkg)
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
  expect_identical(dim(open_saved(pkg, "ds")), dim(fixture_bpcells_cds("human")))

  # For a new resource, directories created for it are removed again.
  fresh <- new_save_pkg()
  fresh_before <- file_state(fresh)
  expect_error(save_monocle_cds(fixture_bpcells_cds("mouse"), "ds", fresh), "manifest not writable")
  expect_identical(file_state(fresh), fresh_before)
  expect_false(dir.exists(file.path(fresh, "inst")))
})

test_that("the caller's CDS is unchanged by saving, converted or not", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  for (cds in list(fixture_bpcells_cds(), fixture_memory_cds())) {
    snapshot <- cds
    counts_before <- SummarizedExperiment::assay(cds, "counts")
    bp_dir <- if (methods::is(counts_before, "IterableMatrix")) counts_dir(cds)
    bp_state <- if (!is.null(bp_dir)) file_state(bp_dir)
    cwd_before <- list.files(getwd(), all.files = TRUE)

    save_quiet(cds, paste0("ds", if (is.null(bp_dir)) "_mem" else "_bp"), pkg)

    expect_identical(cds, snapshot)
    expect_identical(class(SummarizedExperiment::assay(cds, "counts")), class(counts_before))
    if (!is.null(bp_dir)) expect_identical(file_state(bp_dir), bp_state)
    expect_identical(list.files(getwd(), all.files = TRUE), cwd_before)
  }
})

test_that("counts that are already BPCells-backed are not converted again", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  testthat::local_mocked_bindings(
    convert_counts_to_bpcells = function(cds, fail) stop("conversion must not be called")
  )
  expect_no_error(save_quiet(fixture_bpcells_cds(), "ds", pkg))
  restored <- open_saved(pkg, "ds")
  expect_s4_class(SummarizedExperiment::assay(restored, "counts"), "MatrixDir")
  expect_equal(unname(cds_counts(restored)), unname(cds_fixtures()$human$expected$counts))
  expect_identical(dimnames(restored), dimnames(cds_fixtures()$human$expected$counts))
})

test_that("in-memory counts are converted automatically, on a copy, preserving identifiers, metadata and reductions", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  cds <- fixture_memory_cds()
  expect_false(methods::is(SummarizedExperiment::assay(cds, "counts"), "IterableMatrix"))
  expected <- cds_fixtures()$human$expected
  tmp_before <- list.files(tempdir(), pattern = "projectData.monocle3-convert")

  out <- save_quiet(cds, "ds_conv", pkg)
  expect_length(out$warnings, 0L)
  # The intermediate matrix directory does not outlive the call.
  expect_identical(list.files(tempdir(), pattern = "projectData.monocle3-convert"), tmp_before)
  expect_false(methods::is(SummarizedExperiment::assay(cds, "counts"), "IterableMatrix"))

  restored <- open_saved(pkg, "ds_conv")
  expect_s4_class(SummarizedExperiment::assay(restored, "counts"), "MatrixDir")
  expect_identical(dimnames(restored), dimnames(expected$counts))
  expect_equal(unname(cds_counts(restored)), unname(expected$counts))
  expect_equal(as.data.frame(SummarizedExperiment::colData(restored))[, c("group", "n")],
               expected$cell_md, ignore_attr = TRUE)
  expect_equal(as.data.frame(SummarizedExperiment::rowData(restored))$gene_short_name,
               expected$gene_md$gene_short_name)
  expect_equal(SingleCellExperiment::reducedDims(restored)$UMAP, expected$umap, ignore_attr = TRUE)
  expect_equal(SingleCellExperiment::reducedDims(restored)$PCA, expected$pca, ignore_attr = TRUE)
})

test_that("an in-memory alternative assay survives, and is not converted", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  cds <- fixture_bpcells_cds()
  alt <- Matrix::Matrix(cds_fixtures()$human$expected$counts * 2, sparse = TRUE)
  SummarizedExperiment::assay(cds, "alt_mem") <- alt

  out <- save_quiet(cds, "ds", pkg)
  expect_length(out$warnings, 0L)
  restored <- open_saved(pkg, "ds")

  expect_true("alt_mem" %in% SummarizedExperiment::assayNames(restored))
  got <- SummarizedExperiment::assay(restored, "alt_mem")
  expect_false(methods::is(got, "IterableMatrix"))
  expect_equal(unname(as.matrix(got)), unname(as.matrix(alt)))
  expect_equal(unname(cds_counts(restored)), unname(cds_fixtures()$human$expected$counts))

  # Also when counts are converted automatically: the alternative assay stays in memory.
  mem <- fixture_memory_cds()
  SummarizedExperiment::assay(mem, "alt_mem") <- alt
  save_quiet(mem, "ds_conv", pkg)
  conv <- open_saved(pkg, "ds_conv")
  expect_false(methods::is(SummarizedExperiment::assay(conv, "alt_mem"), "IterableMatrix"))
  expect_equal(unname(as.matrix(SummarizedExperiment::assay(conv, "alt_mem"))), unname(as.matrix(alt)))
})

test_that("a reminder is printed when no documentation topic exists", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  msgs <- testthat::capture_messages(save_monocle_cds(fixture_bpcells_cds(), "ds", pkg))
  expect_true(any(grepl("No documentation topic", msgs)))
  dir.create(file.path(pkg, "R"))
  writeLines(c("#' Title", "\"ds\""), file.path(pkg, "R", "data.R"))
  msgs <- testthat::capture_messages(save_monocle_cds(fixture_bpcells_cds(), "ds", pkg, overwrite = TRUE))
  expect_false(any(grepl("No documentation topic", msgs)))
  expect_false(file.exists(file.path(pkg, "R", "data.R")) &&
                 length(readLines(file.path(pkg, "R", "data.R"))) != 2L)
})

test_that("a saved package installs and works through projectData, also after data_detach()", {
  skip_if_no_monocle()
  local_clean_projectData()
  pkg <- new_save_pkg("savedpkg")
  expected <- cds_fixtures()$human$expected
  save_quiet(fixture_bpcells_cds("human"), "cds_human", pkg)
  save_quiet(fixture_memory_cds("mouse"), "cds_mouse", pkg)
  lib <- install_source_pkg(pkg)

  # data() gives only the informative placeholder.
  env <- new.env()
  utils::data("cds_human", package = "savedpkg", lib.loc = lib, envir = env)
  expect_s3_class(env$cds_human, "projectData_monocle3_placeholder")

  projectData::data_attach("savedpkg", lib.loc = lib)
  cat <- projectData::data_catalog()
  expect_true(all(cat$state[cat$object %in% c("cds_human", "cds_mouse")] == "unopened"))

  human <- projectData::data_get("cds_human")
  expect_s4_class(human, "cell_data_set")
  expect_identical(dim(human), dim(expected$counts))
  expect_identical(dimnames(human), dimnames(expected$counts))
  expect_equal(unname(cds_counts(human)), unname(expected$counts))
  expect_equal(as.data.frame(SummarizedExperiment::colData(human))[, c("group", "n")],
               expected$cell_md, ignore_attr = TRUE)
  expect_equal(SingleCellExperiment::reducedDims(human)$UMAP, expected$umap, ignore_attr = TRUE)
  expect_true(in_dir(counts_dir(human), work_root()))

  mouse <- projectData::data_get("cds_mouse")
  expect_identical(dim(mouse), dim(cds_fixtures()$mouse$expected$counts))
  expect_equal(unname(cds_counts(mouse)), unname(cds_fixtures()$mouse$expected$counts))

  projectData::data_detach()
  expect_equal(unname(cds_counts(human)), unname(expected$counts))
  expect_true(dir.exists(counts_dir(human)))
  expect_identical(stage_dirs(pkg), character())
})

test_that("a manifest entry takes precedence over the classed placeholder in data_catalog()", {
  skip_if_no_monocle()
  local_clean_projectData()
  pkg <- new_save_pkg("precpkg")
  save_quiet(fixture_bpcells_cds("human"), "cds_prec", pkg)
  expect_true(file.exists(file.path(pkg, "data", "cds_prec.rda")))
  lib <- install_source_pkg(pkg)

  # Without its manifest, the same package resolves the placeholder as a plain dataset.
  bare <- new_save_pkg("barepkg")
  save_quiet(fixture_bpcells_cds("human"), "cds_prec", bare)
  unlink(file.path(bare, "inst", "projectData"), recursive = TRUE)
  bare_lib <- install_source_pkg(bare)

  rows <- function(package, lib) {
    projectData::data_attach(package, lib.loc = lib)
    withr::defer(projectData::data_detach())
    cat <- projectData::data_catalog()
    cat[cat$package == package, , drop = FALSE]
  }

  with_manifest <- rows("precpkg", lib)
  row <- with_manifest[with_manifest$object == "cds_prec", , drop = FALSE]
  expect_identical(nrow(row), 1L)
  expect_identical(row$origin, "manifest")
  expect_identical(row$loader, "projectData.monocle3::cds")
  expect_identical(row$source, "extdata/cds_prec")
  expect_identical(row$state, "unopened")
  expect_identical(with_manifest$loader[with_manifest$object == "ordinary_data"],
                   "projectData::dataset")

  without <- rows("barepkg", bare_lib)
  row <- without[without$object == "cds_prec", , drop = FALSE]
  expect_identical(row$origin, "index")
  expect_identical(row$loader, "projectData::dataset")
})

test_that("saving repairs a manifest whose registered directories were deleted", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  cds <- fixture_bpcells_cds()
  save_quiet(cds, "cds_a", pkg)
  save_quiet(cds, "cds_b", pkg)
  save_quiet(cds, "cds_keep", pkg)
  unlink(file.path(pkg, "inst", "extdata", c("cds_a", "cds_b")), recursive = TRUE)
  placeholders <- file_state(file.path(pkg, "data"))

  expect_error(projectData::data_manifest_validate(manifest_file(pkg), root = pkg),
               "does not exist")
  out <- save_quiet(cds, "cds_a", pkg, overwrite = TRUE)

  expect_identical(out$result$manifest_status, "unchanged")
  expect_identical(out$result$removed_stale, "cds_b")
  expect_identical(manifest_resources(pkg), c("cds_a", "cds_keep"))
  expect_no_error(projectData::data_manifest_validate(manifest_file(pkg), root = pkg))
  expect_identical(dim(open_saved(pkg, "cds_a")), dim(cds))
  # The repair deleted no placeholder and no other saved directory.
  after <- file_state(file.path(pkg, "data"))
  expect_identical(after$files, placeholders$files)
  expect_true(dir.exists(file.path(pkg, "inst", "extdata", "cds_keep")))
  expect_false(dir.exists(file.path(pkg, "inst", "extdata", "cds_b")))
})

test_that("saving a new resource when the manifest holds only stale entries leaves a valid manifest", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  write_manifest_text(pkg, c("ManifestVersion: 1", "",
                             "Resource: old_a", "Loader: projectData.monocle3::cds",
                             "Source: extdata/old_a", "Objects: old_a", "",
                             "Resource: old_b", "Loader: projectData.monocle3::cds",
                             "Source: extdata/old_b", "Objects: old_b"))

  msgs <- testthat::capture_messages(save_monocle_cds(fixture_bpcells_cds(), "fresh", pkg))

  expect_identical(manifest_resources(pkg), "fresh")
  expect_match(paste(msgs, collapse = ""), "Removed stale: old_a, old_b", fixed = TRUE)
  expect_no_error(projectData::data_manifest_validate(manifest_file(pkg), root = pkg))
})

test_that("saving keeps entries of other adapters, and refuses when one of them is invalid", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  dir.create(file.path(pkg, "inst", "extdata", "other_thing"), recursive = TRUE)
  writeLines("x", file.path(pkg, "inst", "extdata", "other_thing", "payload.txt"))
  write_manifest_text(pkg, c("ManifestVersion: 1", "", save_other_entry, "",
                             "Resource: stale", "Loader: projectData.monocle3::cds",
                             "Source: extdata/stale", "Objects: stale"))

  save_quiet(fixture_bpcells_cds(), "ds", pkg)

  expect_identical(manifest_resources(pkg), c("other_res", "ds"))
  d <- projectData::data_manifest_validate(manifest_file(pkg), root = pkg)
  expect_identical(d[[1]]$title, "Hand-written title")

  # Another adapter's entry that does not validate is never repaired; nothing is saved.
  unlink(file.path(pkg, "inst", "extdata", "other_thing"), recursive = TRUE)
  before <- file_state(pkg)
  expect_error(save_monocle_cds(fixture_bpcells_cds(), "ds2", pkg),
               "other_res.*other_thing|other_thing.*other_res",
               class = "projectData.monocle3_manifest_error")
  expect_identical(file_state(pkg), before)
  expect_length(stage_dirs(pkg), 0L)
})

test_that("a malformed manifest stops the save without being touched", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  write_manifest_text(pkg, "not: a: manifest")
  before <- file_state(pkg)
  expect_error(save_monocle_cds(fixture_bpcells_cds(), "ds", pkg), "was not modified")
  expect_identical(file_state(pkg), before)
  expect_length(stage_dirs(pkg), 0L)
})

test_that("a failed commit leaves stale manifest entries and files exactly as they were", {
  skip_if_no_monocle()
  pkg <- new_save_pkg()
  write_manifest_text(pkg, c("ManifestVersion: 1", "",
                             "Resource: stale", "Loader: projectData.monocle3::cds",
                             "Source: extdata/stale", "Objects: stale"))
  before <- file_state(pkg)
  testthat::local_mocked_bindings(
    write_planned_manifest = function(plan, manifest, root) stop("manifest not writable")
  )

  expect_error(save_monocle_cds(fixture_bpcells_cds(), "ds", pkg), "previous files were restored")
  expect_identical(file_state(pkg), before)
  expect_identical(manifest_resources(pkg), "stale")
})
