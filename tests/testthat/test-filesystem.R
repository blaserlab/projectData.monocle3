# Filesystem safety: symbolic links, containment, entry types, and the staging
# and commit protections. One rule (see R/filesystem.R): nothing inside a Monocle
# resource, or inside an external BPCells directory that is copied, may be a
# symbolic link; the directory a path starts from may be reached through links.
#
# Part 1 uses small synthetic trees (no monocle3 or BPCells needed). Part 2 runs
# save_monocle_cds() and the loader on real fixtures; a refusal must leave the
# package byte-identical (file_state() compares names, md5 sums and mtimes).

fs_descriptor <- function(source = "extdata/cds") {
  list(resource = "cds", loader = "projectData.monocle3::cds", source = source, objects = "cds")
}

fs_files <- function() {
  data.frame(
    cds_object = c("cds", "bpcells_matrix_dir", "reduce_dim_aux"),
    file_format = c("rds", "BPCells:MatrixDir", "umap_annoy_index"),
    file_path = c("cds_object.rds", "bpcells_matrix_dir", "umap.idx")
  )
}

# A synthetic saved directory below a library-like root; returns the root.
fs_saved_root <- function(env = parent.frame(), files = fs_files(), lib = "lib") {
  root <- withr::local_tempdir(.local_envir = env)
  dir <- file.path(root, lib, "extdata", "cds")
  dir.create(dir, recursive = TRUE)
  saveRDS(list(save_function = "save_monocle_objects", files = files),
          file.path(dir, "file_index.rds"))
  writeLines("x", file.path(dir, "cds_object.rds"))
  writeLines("x", file.path(dir, "umap.idx"))
  make_fake_matrix_dir(file.path(dir, "bpcells_matrix_dir"))
  file.path(root, lib)
}

fs_check <- function(root, source = "extdata/cds") {
  validate_monocle_cds(fs_descriptor(source), root, list())
}

# Non-ASCII names need a UTF-8 locale to be written and read back faithfully.
skip_if_not_utf8 <- function() skip_if_not(l10n_info()[["UTF-8"]], "not a UTF-8 locale")

# Part 1: tree walking and the shared rules -------------------------------------

test_that("1/2: a valid native resource with a valid BPCells directory validates", {
  skip_if_not_installed("withr")
  root <- fs_saved_root()
  expect_true(fs_check(root))
  dir <- file.path(root, "extdata", "cds")
  expect_length(saved_tree_problems(dir), 0L)
  expect_length(backing_dir_problems(file.path(dir, "bpcells_matrix_dir")), 0L)
})

test_that("2: BPCells directories are judged on required files, nesting and type", {
  skip_if_not_installed("withr")
  base <- withr::local_tempdir()
  ok <- make_fake_matrix_dir(file.path(base, "ok"))
  expect_length(backing_dir_problems(ok), 0L)

  # Compressed layouts have val_data instead of val.
  comp <- make_fake_matrix_dir(file.path(base, "comp"))
  file.rename(file.path(comp, "val"), file.path(comp, "val_data"))
  expect_length(backing_dir_problems(comp), 0L)

  gone <- make_fake_matrix_dir(file.path(base, "gone"))
  unlink(file.path(gone, c("storage_order", "val")))
  expect_match(backing_dir_problems(gone), "missing: storage_order, val", fixed = FALSE)

  nested <- make_fake_matrix_dir(file.path(base, "nested"))
  dir.create(file.path(nested, "extra"))
  expect_match(backing_dir_problems(nested), "'extra' is a nested directory")

  expect_match(backing_dir_problems(file.path(base, "nope")), "does not exist")
  file.create(file.path(base, "afile"))
  expect_match(backing_dir_problems(file.path(base, "afile")), "not a directory")
})

test_that("3: an internal symbolic link is refused, to a file or to a directory", {
  skip_if_not_installed("withr")
  skip_if_no_symlinks()
  root <- fs_saved_root()
  dir <- file.path(root, "extdata", "cds")
  file.rename(file.path(dir, "umap.idx"), file.path(dir, "real.idx"))
  make_link("real.idx", file.path(dir, "umap.idx"))
  expect_match(fs_check(root), "'umap.idx' is a symbolic link")
  expect_false(isTRUE(fs_check(root)))

  # A link inside the BPCells directory, pointing inside the resource.
  root <- fs_saved_root()
  mdir <- file.path(root, "extdata", "cds", "bpcells_matrix_dir")
  make_link("../cds_object.rds", file.path(mdir, "extra"))
  expect_match(fs_check(root), "bpcells_matrix_dir/extra' is a symbolic link")

  # A link to a directory of the resource is not entered, so a cycle ends.
  root <- fs_saved_root()
  dir <- file.path(root, "extdata", "cds")
  make_link(".", file.path(dir, "loop"))
  expect_match(fs_check(root), "'loop' is a symbolic link")
  expect_lt(nrow(tree_entries(dir)), 20L)
})

test_that("4: escaping symbolic links are refused wherever they sit", {
  skip_if_not_installed("withr")
  skip_if_no_symlinks()
  outside <- withr::local_tempfile()
  writeLines("secret", outside)
  outdir <- withr::local_tempdir()
  writeLines("x", file.path(outdir, "f"))

  root <- fs_saved_root()
  dir <- file.path(root, "extdata", "cds")
  unlink(file.path(dir, "umap.idx"))
  make_link(outside, file.path(dir, "umap.idx"))
  expect_match(fs_check(root), "'umap.idx' is a symbolic link that leaves the directory")

  # file_index.rds itself linked elsewhere is caught before it is read.
  root <- fs_saved_root()
  dir <- file.path(root, "extdata", "cds")
  unlink(file.path(dir, "file_index.rds"))
  saveRDS(list(save_function = "save_monocle_objects", files = fs_files()), outside)
  make_link(outside, file.path(dir, "file_index.rds"))
  expect_match(fs_check(root), "'file_index.rds' is a symbolic link that leaves")

  # The whole BPCells directory replaced by a link to a directory elsewhere.
  root <- fs_saved_root()
  dir <- file.path(root, "extdata", "cds")
  unlink(file.path(dir, "bpcells_matrix_dir"), recursive = TRUE)
  make_link(outdir, file.path(dir, "bpcells_matrix_dir"))
  expect_match(fs_check(root), "'bpcells_matrix_dir' is a symbolic link that leaves")

  # A file inside the BPCells directory.
  root <- fs_saved_root()
  mdir <- file.path(root, "extdata", "cds", "bpcells_matrix_dir")
  unlink(file.path(mdir, "col_names"))
  make_link(outside, file.path(mdir, "col_names"))
  expect_match(fs_check(root), "col_names' is a symbolic link that leaves")
  expect_match(backing_dir_problems(mdir), "col_names' is a symbolic link that leaves")

  # A sibling whose name merely starts with the resource's name is outside too.
  root <- fs_saved_root()
  dir <- file.path(root, "extdata", "cds")
  sibling <- paste0(dir, "2")
  dir.create(sibling)
  writeLines("x", file.path(sibling, "f"))
  unlink(file.path(dir, "umap.idx"))
  make_link(file.path(sibling, "f"), file.path(dir, "umap.idx"))
  expect_match(fs_check(root), "leaves the directory")
})

test_that("5: dangling symbolic links are refused, listed or not", {
  skip_if_not_installed("withr")
  skip_if_no_symlinks()
  root <- fs_saved_root()
  dir <- file.path(root, "extdata", "cds")
  unlink(file.path(dir, "umap.idx"))
  make_link("/nonexistent/target", file.path(dir, "umap.idx"))
  expect_match(fs_check(root), "'umap.idx' is a dangling symbolic link")

  # Unlisted entries are covered too: nothing in a resource may be a link.
  root <- fs_saved_root()
  dir <- file.path(root, "extdata", "cds")
  make_link("nowhere", file.path(dir, "stray"))
  expect_match(fs_check(root), "'stray' is a dangling symbolic link")
})

test_that("6: symlinked libraries and a symlinked resource directory still work", {
  skip_if_not_installed("withr")
  skip_if_no_symlinks()
  root <- fs_saved_root(lib = "realib")
  base <- dirname(root)

  # The library path is a link: the resource inside it is judged normally.
  make_link(root, file.path(base, "linked_lib"))
  expect_true(fs_check(file.path(base, "linked_lib")))

  # So is a link in the middle of the path (extdata -> elsewhere).
  moved <- file.path(base, "moved_extdata")
  file.rename(file.path(root, "extdata"), moved)
  make_link(moved, file.path(root, "extdata"))
  expect_true(fs_check(root))

  # And the resource directory itself.
  keep <- file.path(base, "keep")
  dir.create(keep)
  file.rename(file.path(moved, "cds"), file.path(keep, "cds"))
  make_link(file.path(keep, "cds"), file.path(moved, "cds"))
  expect_true(fs_check(root))
  # ... but a link inside the linked resource is still refused.
  make_link("cds_object.rds", file.path(keep, "cds", "alias"))
  expect_match(fs_check(root), "'alias' is a symbolic link")
})

test_that("7: a file where a directory is expected, and the reverse, is refused", {
  skip_if_not_installed("withr")
  root <- fs_saved_root()
  dir <- file.path(root, "extdata", "cds")
  unlink(file.path(dir, "bpcells_matrix_dir"), recursive = TRUE)
  file.create(file.path(dir, "bpcells_matrix_dir"))
  expect_match(fs_check(root), "is not a directory")

  # A directory where the index lists a file.
  root <- fs_saved_root()
  dir <- file.path(root, "extdata", "cds")
  unlink(file.path(dir, "umap.idx"))
  dir.create(file.path(dir, "umap.idx"))
  expect_match(fs_check(root), "directory where a file is expected: umap.idx")

  # The resource itself being a file.
  root <- fs_saved_root()
  dir <- file.path(root, "extdata", "cds")
  unlink(dir, recursive = TRUE)
  file.create(dir)
  expect_match(fs_check(root), "does not exist")
})

test_that("8: unexpected entries are reported, not silently copied", {
  skip_if_not_installed("withr")
  root <- fs_saved_root()
  mdir <- file.path(root, "extdata", "cds", "bpcells_matrix_dir")
  dir.create(file.path(mdir, "sub"))
  writeLines("x", file.path(mdir, "sub", "f"))
  expect_match(fs_check(root), "not usable.*'sub' is a nested directory")

  # Entries that are neither regular files nor directories.
  entries <- data.frame(path = c("a", "b"), kind = c("file", "other"))
  expect_match(entry_problems("/tmp", entries), "'b' is not a regular file or directory")

  # The walk is bounded.
  big <- withr::local_tempdir()
  for (i in 1:12) file.create(file.path(big, paste0("f", i)))
  expect_true(attr(tree_entries(big, max_entries = 5L), "truncated"))
  expect_false(attr(tree_entries(big), "truncated"))
})

test_that("9/10: paths with spaces and non-ASCII characters validate and are judged the same", {
  skip_if_not_installed("withr")
  skip_if_no_symlinks()
  skip_if_not_utf8()
  lib <- "my lib \u00e9\u4e2d"
  root <- fs_saved_root(lib = lib)
  expect_true(fs_check(root))
  expect_true(fs_check(root, "extdata/cds"))

  dir <- file.path(root, "extdata", "cds")
  file.rename(file.path(dir, "umap.idx"), file.path(dir, "real \u00fc.idx"))
  make_link("real \u00fc.idx", file.path(dir, "umap.idx"))
  expect_match(fs_check(root), "umap.idx' is a symbolic link")

  # A name with a space and non-ASCII characters inside the BPCells directory.
  root <- fs_saved_root(lib = lib)
  mdir <- file.path(root, "extdata", "cds", "bpcells_matrix_dir")
  outside <- withr::local_tempfile(pattern = "out side \u00e9")
  writeLines("x", outside)
  make_link(outside, file.path(mdir, "l\u00e4nk name"))
  expect_match(backing_dir_problems(mdir), "l\u00e4nk name' is a symbolic link that leaves")
})

test_that("11/12: `..` and absolute paths are refused in the index and in `Source`", {
  skip_if_not_installed("withr")
  root <- fs_saved_root()
  dir <- file.path(root, "extdata", "cds")
  rewrite <- function(path) {
    files <- fs_files()
    files$file_path[3] <- path
    saveRDS(list(save_function = "save_monocle_objects", files = files),
            file.path(dir, "file_index.rds"))
    fs_check(root)
  }
  for (bad in c("../umap.idx", "sub/../../umap.idx", "..", "a\\..\\b", "/etc/passwd",
                "\\\\server\\share\\f", "C:/Windows/f", "C:f", "~/f")) {
    expect_match(rewrite(bad), "not relative", info = bad)
  }
  expect_true(rewrite("umap.idx"))

  # A manifest `Source` that leaves the package never reaches the filesystem.
  expect_match(fs_check(root, "../outside"), "relative path inside the package")
  expect_match(fs_check(root, "extdata/../../x"), "relative path inside the package")
  expect_match(fs_check(root, "/abs/path"), "relative path inside the package")
})

test_that("the loader's open() repeats the check and never copies from an unsafe tree", {
  skip_if_not_installed("withr")
  skip_if_no_symlinks()
  root <- fs_saved_root()
  dir <- file.path(root, "extdata", "cds")
  outside <- withr::local_tempfile()
  writeLines("secret", outside)
  unlink(file.path(dir, "bpcells_matrix_dir", "col_names"))
  make_link(outside, file.path(dir, "bpcells_matrix_dir", "col_names"))
  work <- withr::local_tempdir()
  before <- file_state(work)
  expect_error(
    open_monocle_cds(list(resource = "cds", source = "extdata/cds", objects = "cds"),
                     list(source = dir, work_dir = work), list()),
    "Cannot open Monocle resource 'cds'.*symbolic link that leaves"
  )
  expect_identical(file_state(work), before)
  expect_identical(readLines(outside), "secret")

  # A work directory inside the installed resource is refused outright.
  root <- fs_saved_root()
  dir <- file.path(root, "extdata", "cds")
  inner <- file.path(dir, "work")
  dir.create(inner)
  expect_error(
    open_monocle_cds(list(resource = "cds", source = "extdata/cds", objects = "cds"),
                     list(source = dir, work_dir = inner), list()),
    "lies inside the installed resource"
  )
  expect_error(
    open_monocle_cds(list(resource = "cds", source = "extdata/cds", objects = "cds"),
                     list(source = dir, work_dir = dir), list()),
    "lies inside the installed resource"
  )
})

test_that("remove_tree() never follows a link and leaves what is outside alone", {
  skip_if_not_installed("withr")
  skip_if_no_symlinks()
  base <- withr::local_tempdir()
  outside <- file.path(base, "outside")
  dir.create(outside)
  writeLines("keep", file.path(outside, "f"))
  tree <- file.path(base, "tree")
  dir.create(file.path(tree, "sub"), recursive = TRUE)
  make_link(outside, file.path(tree, "sub", "lnk"))
  make_link("nowhere", file.path(tree, "dangling"))
  expect_true(remove_tree(tree))
  expect_false(file.exists(tree))
  expect_true(file.exists(file.path(outside, "f")))

  # A link given directly is removed, its target is not.
  make_link(outside, file.path(base, "direct"))
  expect_true(remove_tree(file.path(base, "direct")))
  expect_false(is_symlink(file.path(base, "direct")))
  expect_true(file.exists(file.path(outside, "f")))

  # `within` refuses what resolves elsewhere.
  other <- withr::local_tempdir()
  expect_false(remove_tree(outside, within = other))
  expect_true(file.exists(file.path(outside, "f")))
})

# Ownership with links ----------------------------------------------------------

fs_targets <- function(pkg, name = "ds") {
  check_save_targets(
    pkg, name, TRUE,
    function(..., class = NULL) {
      stop(structure(class = c(class, "projectData.monocle3_save_error", "error", "condition"),
                     list(message = paste0(...), call = NULL)))
    },
    read_existing_manifest(manifest_path(pkg))
  )
}

fs_refusal <- function(pkg, regexp, class = "projectData.monocle3_not_owned", name = "ds") {
  before <- file_state(pkg)
  expect_error(fs_targets(pkg, name), regexp, class = class)
  expect_identical(file_state(pkg), before)
}

test_that("a link in place of the resource directory, or inside it, is not owned", {
  skip_if_not_installed("withr")
  skip_if_no_symlinks()

  # Link to a valid resource, with evidence that would otherwise own it.
  pkg <- new_pkg_source("fakedata")
  add_fake_cds(pkg, "real")
  add_placeholder(pkg, "ds")
  make_link(file.path(pkg, "inst", "extdata", "real"), file.path(pkg, "inst", "extdata", "ds"))
  fs_refusal(pkg, "symbolic link")

  # Dangling link.
  pkg <- new_pkg_source("fakedata")
  dir.create(file.path(pkg, "inst", "extdata"), recursive = TRUE)
  make_link("nowhere", file.path(pkg, "inst", "extdata", "ds"))
  fs_refusal(pkg, "dangling symbolic link")

  # Link inside an otherwise owned resource.
  pkg <- new_pkg_source("fakedata")
  dir <- add_fake_cds(pkg, "ds")
  add_placeholder(pkg, "ds")
  make_link("cds_object.rds", file.path(dir, "alias"))
  fs_refusal(pkg, "alias' is a symbolic link")

  # A dangling link where the placeholder would go: never silently replaced.
  pkg <- new_pkg_source("fakedata")
  add_fake_cds(pkg, "ds")
  dir.create(file.path(pkg, "data"))
  make_link("nowhere", file.path(pkg, "data", "ds.rda"))
  fs_refusal(pkg, "does not hold a CDS placeholder", class = "projectData.monocle3_placeholder_not_recognized")

  # Links in *parents* are fine: inst/extdata elsewhere, owned resource inside.
  pkg <- new_pkg_source("fakedata")
  add_fake_cds(pkg, "ds")
  add_placeholder(pkg, "ds")
  moved <- file.path(dirname(pkg), "shared_extdata")
  file.rename(file.path(pkg, "inst", "extdata"), moved)
  make_link(moved, file.path(pkg, "inst", "extdata"))
  expect_identical(fs_targets(pkg)$state, "valid")
})

test_that("a link cycle in an existing resource neither hangs ownership nor is accepted", {
  skip_if_not_installed("withr")
  skip_if_no_symlinks()
  pkg <- new_pkg_source("fakedata")
  dir <- add_fake_cds(pkg, "ds")
  add_placeholder(pkg, "ds")
  make_link(".", file.path(dir, "loop"))
  fs_refusal(pkg, "loop' is a symbolic link")
})

# Part 2: real fixtures ---------------------------------------------------------

# One saved package per test run, copied for each test that needs a starting point.
saved_pkg_template <- function() {
  if (is.null(fixture_cache$fs_template)) {
    pkg <- new_save_pkg("fsdata", env = testthat::teardown_env())
    save_quiet(fixture_bpcells_cds("human"), "ds", pkg)
    fixture_cache$fs_template <- pkg
  }
  fixture_cache$fs_template
}

copy_saved_pkg <- function(env = parent.frame()) {
  base <- withr::local_tempdir(.local_envir = env)
  file.copy(saved_pkg_template(), base, recursive = TRUE)
  file.path(base, basename(saved_pkg_template()))
}

# A CDS whose counts are an on-disk matrix in a directory of its own, which
# `inject` may then damage (the matrix is opened first, so dimnames are read).
cds_with_external_counts <- function(inject = function(dir) NULL, env = parent.frame()) {
  dir <- file.path(withr::local_tempdir(.local_envir = env), "my counts")
  dir.create(dir)
  src <- file.path(cds_fixtures()$human$saved, "bpcells_matrix_dir")
  file.copy(list.files(src, full.names = TRUE), dir)
  cds <- fixture_bpcells_cds("human")
  SummarizedExperiment::assay(cds, "counts", withDimnames = FALSE) <- BPCells::open_matrix_dir(dir)
  inject(dir)
  list(cds = cds, dir = dir)
}

expect_unsafe_backing <- function(inject, regexp) {
  skip_if_no_monocle()
  skip_if_no_symlinks()
  pkg <- copy_saved_pkg()
  x <- cds_with_external_counts(inject)
  before <- file_state(pkg)
  expect_error(
    save_monocle_cds(x$cds, "ds", pkg, overwrite = TRUE),
    regexp, class = "projectData.monocle3_unsafe_backing"
  )
  expect_error(save_monocle_cds(x$cds, "fresh", pkg), regexp, class = "projectData.monocle3_save_error")
  expect_identical(file_state(pkg), before)
  expect_length(stage_dirs(pkg), 0L)
  expect_false(file.exists(file.path(pkg, "data", "fresh.rda")))
}

test_that("3/4/5: saving refuses an author's counts directory holding internal, escaping or dangling links", {
  outside <- withr::local_tempfile()
  writeLines("outside the package and the matrix", outside)
  expect_unsafe_backing(function(dir) {
    file.rename(file.path(dir, "col_names"), file.path(dir, "real_col_names"))
    file.symlink("real_col_names", file.path(dir, "col_names"))
  }, "col_names' is a symbolic link")
  expect_unsafe_backing(function(dir) {
    unlink(file.path(dir, "row_names"))
    file.symlink(outside, file.path(dir, "row_names"))
  }, "row_names' is a symbolic link that leaves the directory")
  expect_unsafe_backing(function(dir) {
    unlink(file.path(dir, "val"))
    file.symlink("/nonexistent/val", file.path(dir, "val"))
  }, "val' is a dangling symbolic link")
  expect_identical(readLines(outside), "outside the package and the matrix")
})

test_that("7/8: saving refuses a counts directory with a missing file, a nested directory or a missing directory", {
  expect_unsafe_backing(function(dir) unlink(file.path(dir, "storage_order")),
                        "required file\\(s\\) missing: storage_order")
  expect_unsafe_backing(function(dir) dir.create(file.path(dir, "nested")),
                        "'nested' is a nested directory")
  expect_unsafe_backing(function(dir) unlink(dir, recursive = TRUE), "does not exist")
})

test_that("a counts directory reached through links, with spaces, is fine", {
  skip_if_no_monocle()
  skip_if_no_symlinks()
  pkg <- new_save_pkg()
  x <- cds_with_external_counts()
  # The directory ("my counts") has a space; reach it through a link as well.
  via <- file.path(dirname(x$dir), "via link")
  make_link(x$dir, via)
  SummarizedExperiment::assay(x$cds, "counts", withDimnames = FALSE) <- BPCells::open_matrix_dir(via)
  expect_no_error(save_quiet(x$cds, "ds", pkg))
  expect_true(validate_monocle_cds(list(source = "extdata/ds", objects = "ds"),
                                   file.path(pkg, "inst"), list()))
  expect_length(saved_tree_problems(file.path(pkg, "inst", "extdata", "ds")), 0L)
})

test_that("an overwrite is refused, byte for byte, when the existing resource holds a link", {
  skip_if_no_monocle()
  skip_if_no_symlinks()
  cds <- fixture_bpcells_cds("mouse")
  for (damage in c("inside", "directory", "dangling")) {
    pkg <- copy_saved_pkg()
    extdata <- file.path(pkg, "inst", "extdata")
    dir <- file.path(extdata, "ds")
    if (damage == "inside") {
      file.symlink("cds_object.rds", file.path(dir, "alias"))
    } else if (damage == "directory") {
      file.rename(dir, file.path(extdata, "real_ds"))
      file.symlink(file.path(extdata, "real_ds"), dir)
    } else {
      unlink(dir, recursive = TRUE)
      file.symlink("/nonexistent", dir)
    }
    before <- file_state(pkg)
    link_before <- Sys.readlink(dir)
    expect_error(save_monocle_cds(cds, "ds", pkg, overwrite = TRUE),
                 class = "projectData.monocle3_not_owned")
    expect_identical(file_state(pkg), before)
    expect_identical(Sys.readlink(dir), link_before)
    expect_length(stage_dirs(pkg), 0L)
  }
})

test_that("saving works through a symlinked package directory and a symlinked inst/extdata", {
  skip_if_no_monocle()
  skip_if_no_symlinks()
  pkg <- new_save_pkg()
  base <- dirname(pkg)

  # package_dir reached through a link.
  linked <- file.path(base, "linked pkg")
  make_link(pkg, linked)
  out <- save_quiet(fixture_bpcells_cds("human"), "ds_a", linked)
  expect_true(file.exists(file.path(pkg, "inst", "extdata", "ds_a", "file_index.rds")))
  expect_length(stage_dirs(pkg), 0L)

  # inst/extdata is a link to shared storage.
  shared <- file.path(base, "shared_extdata")
  file.rename(file.path(pkg, "inst", "extdata"), shared)
  make_link(shared, file.path(pkg, "inst", "extdata"))
  save_quiet(fixture_bpcells_cds("mouse"), "ds_b", pkg)
  expect_true(file.exists(file.path(shared, "ds_b", "file_index.rds")))
  expect_true(is_symlink(file.path(pkg, "inst", "extdata")))

  # Overwriting through the linked parent still works, and so does a rollback.
  save_quiet(fixture_bpcells_cds("mouse"), "ds_a", pkg, overwrite = TRUE)
  expect_equal(dim(open_saved(pkg, "ds_a")), dim(fixture_bpcells_cds("mouse")))
  before <- file_state(pkg)
  before_shared <- file_state(shared)
  testthat::local_mocked_bindings(
    write_planned_manifest = function(plan, manifest, root) stop("manifest not writable")
  )
  expect_error(save_monocle_cds(fixture_bpcells_cds("human"), "ds_a", pkg, overwrite = TRUE),
               "previous files were restored")
  expect_identical(file_state(pkg), before)
  expect_identical(file_state(shared), before_shared)
  expect_true(is_symlink(file.path(pkg, "inst", "extdata")))
  expect_length(stage_dirs(pkg), 0L)
})

test_that("9/10: saving works in a package path with spaces and non-ASCII characters", {
  skip_if_no_monocle()
  skip_if_not_utf8()
  base <- withr::local_tempdir(pattern = "pk g \u00e9\u4e2d ")
  pkg <- file.path(base, "data pkg \u00fc")
  dir.create(pkg)
  writeLines(c("Package: spacedata", "Version: 0.0.1", "Title: T", "Description: D.",
               "License: MIT"), file.path(pkg, "DESCRIPTION"))
  expect_no_error(save_quiet(fixture_bpcells_cds("human"), "ds", pkg))
  expect_length(stage_dirs(pkg), 0L)
  expect_true(validate_monocle_cds(list(source = "extdata/ds", objects = "ds"),
                                   file.path(pkg, "inst"), list()))
  restored <- open_saved(pkg, "ds")
  expect_equal(unname(cds_counts(restored)), unname(cds_fixtures()$human$expected$counts))
})

test_that("13/14: failed serialization or commit leaves no stage and restores byte for byte", {
  skip_if_no_monocle()
  cds <- fixture_bpcells_cds("mouse")

  # Serialization fails after writing part of the output.
  pkg <- copy_saved_pkg()
  before <- file_state(pkg)
  testthat::local_mocked_bindings(
    save_staged_cds = function(cds, directory) {
      dir.create(directory, recursive = TRUE)
      writeLines("partial", file.path(directory, "cds_object.rds"))
      stop("disk full")
    }
  )
  expect_error(save_monocle_cds(cds, "ds", pkg, overwrite = TRUE), "disk full")
  expect_identical(file_state(pkg), before)
  expect_length(stage_dirs(pkg), 0L)
})

test_that("14: when the rename into place fails the previous files come back", {
  skip_if_no_monocle()
  cds <- fixture_bpcells_cds("mouse")
  pkg <- copy_saved_pkg()
  before <- file_state(pkg)
  calls <- 0L
  real <- move_path
  testthat::local_mocked_bindings(
    # Moves 1 and 2 put the old resource and placeholder aside; 3 is the new one.
    move_path = function(from, to) {
      calls <<- calls + 1L
      if (calls == 3L) FALSE else real(from, to)
    }
  )
  expect_error(save_monocle_cds(cds, "ds", pkg, overwrite = TRUE),
               "could not move.*previous files were restored")
  expect_identical(file_state(pkg), before)
  expect_length(stage_dirs(pkg), 0L)
  expect_equal(dim(open_saved(pkg, "ds")), dim(fixture_bpcells_cds("human")))
})

test_that("14: when restoring also fails, the backup is kept and named", {
  skip_if_no_monocle()
  cds <- fixture_bpcells_cds("mouse")
  pkg <- copy_saved_pkg()
  old_index <- tools::md5sum(file.path(pkg, "inst", "extdata", "ds", "file_index.rds"))
  calls <- 0L
  real <- move_path
  testthat::local_mocked_bindings(
    move_path = function(from, to) {
      calls <<- calls + 1L
      if (calls >= 3L) FALSE else real(from, to)
    }
  )
  err <- expect_error(save_monocle_cds(cds, "ds", pkg, overwrite = TRUE),
                      "Restoring the previous files also failed; they are kept in")
  stage <- stage_dirs(pkg)
  expect_length(stage, 1L)
  backup <- file.path(pkg, stage, "backup")
  expect_match(conditionMessage(err), backup, fixed = TRUE)
  kept <- file.path(backup, "1_ds", "file_index.rds")
  expect_true(file.exists(kept))
  expect_identical(unname(tools::md5sum(kept)), unname(old_index))
})

# Loader, work directory and lifecycle, through a symlinked library -------------

test_that("6/15/16: a symlinked library loads two independent CDS, writes nowhere else, and survives detach", {
  skip_if_no_monocle()
  skip_if_no_symlinks()
  local_clean_projectData()
  fx <- cds_fixtures()
  real_lib <- install_cds_package(list(human_cds = fx$human$saved, mouse_cds = fx$mouse$saved),
                                  pkg = "pdlinkdata")
  linked <- file.path(withr::local_tempdir(), "lib link")
  make_link(real_lib, linked)

  installed <- file.path(real_lib, "pdlinkdata", "extdata")
  tree_before <- file_state(installed)
  cwd <- getwd()
  cwd_before <- list.files(cwd, all.files = TRUE)
  work_before <- list.files(work_root(), recursive = TRUE)

  # Read-only installed resource: nothing may need to write there.
  files <- list.files(installed, recursive = TRUE, full.names = TRUE, include.dirs = TRUE)
  dirs <- c(installed, files[dir.exists(files)])
  Sys.chmod(files[!dir.exists(files)], "0444")
  Sys.chmod(dirs, "0555")
  withr::defer({
    Sys.chmod(dirs, "0755")
    Sys.chmod(files[!dir.exists(files)], "0644")
  })

  spy <- local_path_spy()
  withr::with_libpaths(linked, action = "prefix", {
    projectData::data_attach("pdlinkdata")
    human <- projectData::data_get("human_cds", package = "pdlinkdata")
    mouse <- projectData::data_get("mouse_cds", package = "pdlinkdata")
  })

  expect_identical(dim(human), dim(fx$human$expected$counts))
  expect_identical(dim(mouse), dim(fx$mouse$expected$counts))
  # Distinct, isolated work directories under the session work root.
  work <- vapply(spy$paths[c("human_cds", "mouse_cds")], function(p) p$work_dir, "")
  expect_false(anyDuplicated(work) > 0L)
  expect_true(all(in_dir(work, work_root())))
  expect_false(any(in_dir(work, installed)))
  expect_true(in_dir(counts_dir(human), work[["human_cds"]]))
  expect_true(in_dir(counts_dir(mouse), work[["mouse_cds"]]))
  expect_false(identical(counts_dir(human), counts_dir(mouse)))
  expect_false(any(c(in_dir(counts_dir(human), installed), in_dir(counts_dir(mouse), installed))))

  # Nothing written to the installed resource or the working directory.
  expect_identical(getwd(), cwd)
  expect_identical(list.files(cwd, all.files = TRUE), cwd_before)
  expect_identical(file_state(installed), tree_before)

  # Retained objects keep working after detaching, with their files intact.
  expected_h <- unname(fx$human$expected$counts)
  projectData::data_detach()
  expect_equal(unname(cds_counts(human)), expected_h)
  expect_equal(unname(cds_counts(mouse)), unname(fx$mouse$expected$counts))
  expect_true(dir.exists(counts_dir(human)))
  expect_true(dir.exists(counts_dir(mouse)))
})

test_that("an installed resource that was tampered with is refused at open, naming the problem", {
  skip_if_no_monocle()
  skip_if_no_symlinks()
  local_clean_projectData()
  lib <- install_cds_package(list(tampered = cds_fixtures()$human$saved), pkg = "pdtamper")
  outside <- withr::local_tempfile()
  writeLines("secret", outside)
  mdir <- file.path(lib, "pdtamper", "extdata", "tampered", "bpcells_matrix_dir")
  unlink(file.path(mdir, "col_names"))
  make_link(outside, file.path(mdir, "col_names"))
  work_before <- list.files(work_root(), recursive = TRUE)

  withr::with_libpaths(lib, action = "prefix", {
    expect_error(
      suppressWarnings(projectData::data_get("tampered", package = "pdtamper")),
      "symbolic link that leaves the directory"
    )
  })
  expect_identical(list.files(work_root(), recursive = TRUE), work_before)
  expect_identical(readLines(outside), "secret")
})
