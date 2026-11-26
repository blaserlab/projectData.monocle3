# Self-contained end-to-end tests, part 2: installing the generated data package
# into isolated libraries, discovery and reconstruction through projectData, and
# the lifecycle of the restored backing files (helper-synthetic.R).

test_that("the package builds and installs into isolated libraries with valid resources", {
  skip_if_no_e2e()
  s <- synthetic_suite()
  expect_true(file.exists(s$tarball))
  expect_true(any(grepl(paste0("DONE (", s$pkg, ")"), s$install_log, fixed = TRUE)),
              info = paste(s$install_log, collapse = "\n"))

  # The user's libraries were not used.
  expect_false(s$lib_a %in% .libPaths())
  expect_false(s$lib_b %in% .libPaths())
  expect_identical(system.file(package = s$pkg), "")

  for (lib in c(s$lib_a, s$lib_b)) {
    installed <- file.path(lib, s$pkg)
    # inst/ is merged into the package root when installing.
    expect_false(dir.exists(file.path(installed, "inst")))
    expect_true(file.exists(file.path(installed, "projectData", "manifest.dcf")))
    for (name in c("cds_a", "cds_b")) {
      expect_true(validate_monocle_cds(
        list(source = paste0("extdata/", name), objects = name), installed, list()
      ))
    }
    # The resources are byte for byte what was authored.
    expect_identical(tree_checksums(file.path(installed, "extdata")),
                     tree_checksums(file.path(s$src, "inst", "extdata")))
  }
})

test_that("projectData discovers the package from its manifest without opening anything", {
  skip_if_no_e2e()
  local_clean_projectData()
  s <- synthetic_suite()
  counter <- local_open_counter()
  cwd <- withr::local_tempdir("pdm3-cwd-")
  withr::local_dir(cwd)
  installed <- file.path(s$lib_a, s$pkg)
  checksums <- tree_checksums(installed)
  work_before <- list.files(work_root(), recursive = TRUE)

  # data() still offers the informative placeholders ...
  env <- new.env()
  utils::data("cds_a", package = s$pkg, lib.loc = s$lib_a, envir = env)
  expect_s3_class(env$cds_a, "projectData_monocle3_placeholder")

  projectData::data_attach(s$pkg, lib.loc = s$lib_a)

  # ... but the catalog row comes from the manifest and names the adapter.
  cat <- projectData::data_catalog()
  cat <- cat[cat$package == s$pkg, , drop = FALSE]
  expect_setequal(cat$object, c("cds_a", "cds_b"))
  expect_true(all(cat$origin == "manifest"))
  expect_true(all(cat$loader == "projectData.monocle3::cds"))
  expect_setequal(cat$source, c("extdata/cds_a", "extdata/cds_b"))
  expect_true(all(cat$state == "unopened"))

  # Nothing was reconstructed or written.
  expect_length(counter$log, 0L)
  expect_identical(list.files(work_root(), recursive = TRUE), work_before)
  expect_length(list.files(cwd, all.files = TRUE, no.. = TRUE), 0L)
  expect_identical(tree_checksums(installed), checksums)
  expect_identical(normalizePath(getwd()), normalizePath(cwd))
})

test_that("data_get() restores both resources, with converted counts unchanged", {
  skip_if_no_e2e()
  local_clean_projectData()
  s <- synthetic_suite()

  a <- projectData::data_get("cds_a", package = s$pkg, lib.loc = s$lib_a)
  b <- projectData::data_get("cds_b", package = s$pkg, lib.loc = s$lib_a)

  # cds_a began with in-memory counts; both now read from BPCells directories.
  expect_identical(s$counts_before$cds_a, "dgCMatrix")
  expect_summary_matches_spec(cds_summary(a), s$spec$cds_a, "MatrixDir")
  expect_summary_matches_spec(cds_summary(b), s$spec$cds_b, "MatrixDir")
  expect_identical(dim(a), dim(s$spec$cds_a$counts))
  expect_identical(dim(b), dim(s$spec$cds_b$counts))

  # The adapter is resolved from the manifest; nothing is attached for the user.
  expect_true("projectData.monocle3::cds" %in% projectData::data_loaders()$id)
  expect_false("package:monocle3" %in% search())
  expect_false(identical(dim(a), dim(b)))
})

test_that("the data_attach() and data_detach() workflow works and leaves the search path as it was", {
  skip_if_no_e2e()
  local_clean_projectData()
  s <- synthetic_suite()
  counter <- local_open_counter()
  search_before <- search()

  projectData::data_attach(s$pkg, lib.loc = s$lib_a)
  expect_true("projectData:data" %in% search())
  env <- as.environment("projectData:data")
  expect_setequal(ls(env), c("cds_a", "cds_b"))
  expect_length(counter$log, 0L)

  a <- get("cds_a", envir = env)
  expect_identical(counter$log, paste(s$pkg, "cds_a", sep = "/"))
  expect_summary_matches_spec(cds_summary(a), s$spec$cds_a, "MatrixDir")
  expect_identical(get("cds_a", envir = env), a)         # cached, not reopened
  expect_length(counter$log, 1L)

  projectData::data_detach()
  expect_identical(search(), search_before)
  expect_false("cds_a" %in% projectData::data_catalog()$object)
  # The object retained from the attachment is still complete.
  expect_summary_matches_spec(cds_summary(a), s$spec$cds_a, "MatrixDir")

  # Attaching again works and opens the resource again.
  projectData::data_attach(s$pkg, lib.loc = s$lib_a)
  b <- get("cds_b", envir = as.environment("projectData:data"))
  expect_summary_matches_spec(cds_summary(b), s$spec$cds_b, "MatrixDir")
})

# Backing-file lifecycle ------------------------------------------------------

test_that("restored counts live in the work directory projectData allocated, not in the package", {
  skip_if_no_e2e()
  local_clean_projectData()
  s <- synthetic_suite()
  spy <- local_path_spy()
  cwd <- withr::local_tempdir("pdm3-cwd-")
  withr::local_dir(cwd)
  installed <- file.path(s$lib_a, s$pkg)
  checksums <- tree_checksums(installed)

  a <- projectData::data_get("cds_a", package = s$pkg, lib.loc = s$lib_a)
  work <- spy$paths$cds_a$work_dir

  # 1-3: the work directory is the one projectData allocated; the matrices were
  # restored there; it is neither the installed resource nor under the package.
  expect_length(spy$paths, 1L)
  expect_true(in_dir(work, work_root()))
  expect_identical(basename(dirname(work)), encode_path_component(s$pkg))
  expect_true(in_dir(counts_dir(a), work))
  expect_true(in_dir(SummarizedExperiment::assay(a, "counts_row_order")@dir, work))
  expect_false(in_tree(work, installed))
  expect_false(in_tree(counts_dir(a), installed))
  expect_false(identical(normalizePath(work), normalizePath(spy$paths$cds_a$source)))
  expect_true(in_tree(spy$paths$cds_a$source, installed))

  # 4-5: nothing was written to the package or to the working directory.
  expect_identical(tree_checksums(installed), checksums)
  expect_identical(normalizePath(getwd()), normalizePath(cwd))
  expect_length(list.files(cwd, all.files = TRUE, no.. = TRUE), 0L)
})

test_that("two resources use isolated work directories and do not affect each other", {
  skip_if_no_e2e()
  local_clean_projectData()
  s <- synthetic_suite()
  spy <- local_path_spy()

  a <- projectData::data_get("cds_a", package = s$pkg, lib.loc = s$lib_a)
  work_a <- spy$paths$cds_a$work_dir
  a_before <- tree_checksums(work_a)
  a_counts_before <- cds_counts(a)

  b <- projectData::data_get("cds_b", package = s$pkg)
  work_b <- spy$paths$cds_b$work_dir

  expect_false(identical(work_a, work_b))
  expect_false(in_dir(work_a, work_b) || in_dir(work_b, work_a))
  expect_true(in_dir(counts_dir(b), work_b))
  expect_false(in_dir(counts_dir(b), work_a))
  expect_false(in_dir(counts_dir(a), work_b))
  # Loading the second resource left the first untouched.
  expect_identical(tree_checksums(work_a), a_before)
  expect_identical(cds_counts(a), a_counts_before)
  expect_equal(unname(cds_counts(b)), unname(as.matrix(s$spec$cds_b$counts)))
})

test_that("detaching the package neither invalidates a retained CDS nor removes its backing files", {
  skip_if_no_e2e()
  local_clean_projectData()
  s <- synthetic_suite()
  spy <- local_path_spy()
  projectData::data_attach(s$pkg, lib.loc = s$lib_a)
  a <- projectData::data_get("cds_a")
  b <- projectData::data_get("cds_b")
  dirs <- c(counts_dir(a), SummarizedExperiment::assay(a, "counts_row_order")@dir, counts_dir(b))
  work <- c(spy$paths$cds_a$work_dir, spy$paths$cds_b$work_dir)

  projectData::data_detach()
  invisible(gc())

  expect_true(all(dir.exists(dirs)))
  expect_true(all(dir.exists(work)))
  expect_summary_matches_spec(cds_summary(a), s$spec$cds_a, "MatrixDir")
  expect_summary_matches_spec(cds_summary(b), s$spec$cds_b, "MatrixDir")
  # Attaching again must not clean up the files the retained objects use.
  projectData::data_attach(s$pkg, lib.loc = s$lib_a)
  expect_true(all(dir.exists(dirs)))
  expect_summary_matches_spec(cds_summary(a), s$spec$cds_a, "MatrixDir")
})
