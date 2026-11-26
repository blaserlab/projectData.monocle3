# Self-contained end-to-end tests, part 3: the same built package installed into
# two independent libraries (and reached through a symbolic link), each loaded in
# a fresh R process, and independence from the authoring location
# (helper-synthetic.R). Fresh processes make sure no namespace or projectData
# state from this session, or from the other installation, can hide a dependency.

expect_fresh_load_ok <- function(probe, s, lib) {
  expect_false(inherits(probe, "probe_error"), info = if (inherits(probe, "probe_error")) probe$message)
  expect_identical(names(probe$summaries), c("cds_a", "cds_b"))
  for (name in c("cds_a", "cds_b")) {
    expect_summary_matches_spec(probe$summaries[[name]], s$spec[[name]], "MatrixDir")
    # The object kept working after the package was detached in the child.
    expect_summary_matches_spec(probe$retained[[name]], s$spec[[name]], "MatrixDir")
  }

  # Registration: resolved from the manifest, nothing opened or written.
  expect_true(all(probe$catalog_before$state == "unopened"))
  expect_true(all(probe$catalog_before$origin == "manifest"))
  expect_true(all(probe$catalog_before$loader == "projectData.monocle3::cds"))
  expect_true(all(probe$catalog_opened$state == "ready"))
  expect_length(probe$work_after_attach, 0L)
  expect_true(probe$cwd_unchanged)
  expect_true(probe$search_unchanged)
  expect_true(probe$installed_unchanged)
  expect_false(probe$namespaces$monocle3_attached)

  # Each reconstruction used this library's copy and its own work directory.
  installed <- normalizePath(file.path(lib, s$pkg), winslash = "/")
  work <- vapply(probe$paths, \(p) p$work_dir, "")
  expect_length(unique(work), 2L)
  for (name in c("cds_a", "cds_b")) {
    p <- probe$paths[[name]]
    expect_true(in_tree(p$source, installed))
    expect_identical(p$root, installed)
    expect_true(in_tree(work[[name]], probe$work_root))
    expect_false(in_tree(work[[name]], installed))
    sm <- probe$summaries[[name]]
    expect_true(in_tree(sm$counts_dir, work[[name]]))
    expect_false(in_tree(sm$counts_dir, installed))
  }
}

test_that("each of two libraries loads the same package independently in a fresh process", {
  skip_if_no_e2e()
  s <- synthetic_suite()
  args <- list(pkg = s$pkg, resources = c("cds_a", "cds_b"), spy = TRUE)

  in_a <- run_child("probe_load", c(args, list(lib = s$lib_a)))
  in_b <- run_child("probe_load", c(args, list(lib = s$lib_b)))
  expect_fresh_load_ok(in_a, s, s$lib_a)
  expect_fresh_load_ok(in_b, s, s$lib_b)

  # Each used its own installation, never the other one.
  expect_false(in_tree(in_a$paths$cds_a$source, s$lib_b))
  expect_false(in_tree(in_b$paths$cds_a$source, s$lib_a))
  expect_false(identical(in_a$installed, in_b$installed))
  # Both restore identical content.
  expect_identical(in_a$summaries$cds_a[c("assays", "col_data", "reduced", "alt")],
                   in_b$summaries$cds_a[c("assays", "col_data", "reduced", "alt")])
})

test_that("the adapter is resolved from the manifest in a fresh process, with no loader registered", {
  skip_if_no_e2e()
  s <- synthetic_suite()
  probe <- run_child("probe_load", list(lib = s$lib_b, pkg = s$pkg, resources = "cds_b", spy = FALSE))
  expect_false(inherits(probe, "probe_error"), info = if (inherits(probe, "probe_error")) probe$message)
  expect_summary_matches_spec(probe$summaries$cds_b, s$spec$cds_b, "MatrixDir")
  expect_false("projectData.monocle3::cds" %in% probe$loaders_after_attach)
  expect_true("projectData.monocle3::cds" %in% probe$loaders_after_open)
  expect_true(probe$namespaces$adapter)
  expect_false(probe$namespaces$monocle3_attached)
})

test_that("a symbolic link to a library loads in a fresh process", {
  skip_if_no_e2e()
  skip_if_no_symlinks()
  s <- synthetic_suite()
  link <- file.path(withr::local_tempdir("pdm3-link-"), "linked library")
  make_link(s$lib_a, link)

  probe <- run_child("probe_load", list(lib = link, pkg = s$pkg, resources = c("cds_a", "cds_b"), spy = TRUE))
  expect_false(inherits(probe, "probe_error"), info = if (inherits(probe, "probe_error")) probe$message)
  for (name in c("cds_a", "cds_b")) {
    expect_summary_matches_spec(probe$summaries[[name]], s$spec[[name]], "MatrixDir")
  }
  expect_true(probe$installed_unchanged)
  expect_true(probe$cwd_unchanged)
})

test_that("an installation does not need the authoring directory or the author's original files", {
  skip_if_no_e2e()
  s <- synthetic_suite()
  work <- withr::local_tempdir("pdm3 independence ")
  spec <- s$spec$cds_b

  # Author a fresh package from BPCells-backed counts, build, install ...
  originals <- file.path(work, "originals")
  dir.create(originals)
  cds <- synthetic_cds(spec, "bpcells", originals)
  src <- synthetic_package_source("pdm3Independent", c("cds_b"), file.path(work, "src"))
  save_quiet(cds, "cds_b", src)
  tarball <- build_source_package(src, file.path(work, "tarball"))
  lib <- install_tarball(tarball, file.path(work, "lib"))
  checksums <- tree_checksums(file.path(lib, "pdm3Independent", "extdata"))

  # ... then remove everything the author had.
  rm(cds)
  invisible(gc())
  unlink(c(src, originals, tarball), recursive = TRUE)
  expect_false(dir.exists(src))
  expect_false(dir.exists(file.path(originals, "counts")))
  expect_false(file.exists(tarball))

  probe <- run_child("probe_load", list(lib = lib, pkg = "pdm3Independent", resources = "cds_b", spy = TRUE))
  expect_false(inherits(probe, "probe_error"), info = if (inherits(probe, "probe_error")) probe$message)
  expect_summary_matches_spec(probe$summaries$cds_b, spec, "MatrixDir")
  expect_true(in_tree(probe$summaries$cds_b$counts_dir, probe$work_root))
  expect_identical(tree_checksums(file.path(lib, "pdm3Independent", "extdata")), checksums)
})
