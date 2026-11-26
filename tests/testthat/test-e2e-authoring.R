# Self-contained end-to-end tests, part 1: the synthetic CDS and the data package
# authored from it with save_monocle_cds(). Nothing here needs
# projectData.monocle3.testdata (see helper-synthetic.R).

test_that("the synthetic spec is deterministic, small and realistic", {
  skip_if_not_installed("Matrix")
  a <- synthetic_spec(4217L, 24L, 16L, "a")
  expect_identical(a, synthetic_spec(4217L, 24L, 16L, "a"))
  expect_false(identical(a$counts, synthetic_spec(8093L, 24L, 16L, "a")$counts))

  expect_s4_class(a$counts, "dgCMatrix")
  expect_identical(dim(a$counts), c(24L, 16L))
  expect_true(all(a$counts@x == round(a$counts@x)))
  expect_lt(length(a$counts@x), prod(dim(a$counts)))          # genuinely sparse
  expect_false(anyDuplicated(c(a$genes, a$cells)) > 0)
  expect_false(any(a$genes %in% a$cells))
  expect_identical(rownames(a$cell_md), a$cells)
  expect_identical(rownames(a$gene_md), a$genes)
  expect_lt(prod(dim(a$counts)), 1000)

  # Two specs never share identifiers.
  b <- synthetic_spec(8093L, 30L, 12L, "b")
  expect_length(intersect(c(a$genes, a$cells), c(b$genes, b$cells)), 0L)
})

test_that("synthetic CDS objects have both counts storages and the secondary content", {
  skip_if_no_e2e()
  s <- synthetic_suite()
  expect_identical(s$counts_before, list(cds_a = "dgCMatrix", cds_b = "MatrixDir"))
  expect_summary_matches_spec(cds_summary(s$cds$cds_a), s$spec$cds_a, counts_backing = "dgCMatrix")
  expect_summary_matches_spec(cds_summary(s$cds$cds_b), s$spec$cds_b, counts_backing = "MatrixDir")
})

test_that("saving did not change the caller's CDS objects", {
  skip_if_no_e2e()
  s <- synthetic_suite()
  # Automatic conversion happens on a copy: the author's counts are still in memory.
  expect_s4_class(SummarizedExperiment::assay(s$cds$cds_a, "counts"), "dgCMatrix")
  expect_s4_class(SummarizedExperiment::assay(s$cds$cds_b, "counts"), "MatrixDir")
  expect_setequal(SummarizedExperiment::assayNames(s$cds$cds_a), c("counts", "logcounts", "spliced"))
})

test_that("the generated package has the conventional layout and valid native saves", {
  skip_if_no_e2e()
  s <- synthetic_suite()
  files <- list.files(s$src, recursive = TRUE, all.files = TRUE)
  expect_true(all(c("DESCRIPTION", "NAMESPACE", "R/data.R", "data/cds_a.rda", "data/cds_b.rda",
                    "inst/projectData/manifest.dcf") %in% files))
  expect_setequal(list.files(file.path(s$src, "inst", "extdata")), c("cds_a", "cds_b"))
  expect_setequal(list.files(file.path(s$src, "data")), c("cds_a.rda", "cds_b.rda"))
  expect_length(stage_dirs(s$src), 0L)

  for (name in c("cds_a", "cds_b")) {
    dir <- file.path(s$src, "inst", "extdata", name)
    expect_true(all(c("file_index.rds", "cds_object.rds", "bpcells_matrix_dir") %in% list.files(dir)))
    expect_false(any(grepl("\\.tar", list.files(dir))))
    expect_identical(readRDS(file.path(dir, "file_index.rds"))$save_function, "save_monocle_objects")
    expect_true(validate_monocle_cds(
      list(source = paste0("extdata/", name), objects = name), file.path(s$src, "inst"), list()
    ))

    # The placeholder is recognized, classed, and not a CDS.
    rda <- file.path(s$src, "data", paste0(name, ".rda"))
    expect_true(is_recognized_placeholder(inspect_rda(rda), name))
    loaded <- load_placeholder(s$src, name)
    expect_identical(loaded$names, name)
    expect_s3_class(loaded$object, "projectData_monocle3_placeholder")
    expect_false(methods::is(loaded$object, "cell_data_set"))
    expect_identical(attr(loaded$object, "package"), s$pkg)
  }
})

test_that("the manifest names the loader and adapter with installed-layout source paths", {
  skip_if_no_e2e()
  s <- synthetic_suite()
  manifest <- manifest_file(s$src)
  entries <- as.data.frame(read.dcf(manifest), stringsAsFactors = FALSE)
  entries <- entries[!is.na(entries$Resource), , drop = FALSE]
  expect_setequal(entries$Resource, c("cds_a", "cds_b"))
  expect_true(all(entries$Loader == "projectData.monocle3::cds"))
  expect_true(all(entries$AdapterPackage == "projectData.monocle3"))
  expect_identical(entries$Source[match(c("cds_a", "cds_b"), entries$Resource)],
                   c("extdata/cds_a", "extdata/cds_b"))
  expect_false(any(grepl("inst/", entries$Source, fixed = TRUE)))
  expect_false(any(grepl("^(/|[A-Za-z]:)", entries$Source)))
  expect_false(grepl(s$base, paste(readLines(manifest), collapse = "\n"), fixed = TRUE))

  # projectData accepts it against the installed layout (inst/ merged into the root).
  descriptors <- projectData::data_manifest_validate(manifest, root = file.path(s$src, "inst"))
  expect_length(descriptors, 2L)
  expect_true(all(vapply(descriptors, \(d) d$recorded_class, "") == "cell_data_set"))
})

test_that("write_monocle_manifest() is idempotent on the generated package", {
  skip_if_no_e2e()
  s <- synthetic_suite()
  manifest <- manifest_file(s$src)
  before <- file_state(dirname(manifest))
  data_before <- file_state(file.path(s$src, "data"))

  first <- suppressMessages(write_monocle_manifest(s$src))
  second <- suppressMessages(write_monocle_manifest(s$src))

  expect_setequal(first$resource, c("cds_a", "cds_b"))
  expect_true(all(first$status == "unchanged"))
  expect_true(all(second$status == "unchanged"))
  expect_false(attr(second, "written"))
  # Same bytes and untouched timestamps: the file is not rewritten.
  expect_identical(file_state(dirname(manifest)), before)
  expect_identical(file_state(file.path(s$src, "data")), data_before)
})

test_that("an unsupported external secondary assay fails before anything is written", {
  skip_if_no_e2e()
  s <- synthetic_suite()
  work <- withr::local_tempdir("pdm3-external-")
  src <- synthetic_package_source("externalData", "cds_ext", file.path(work, "src"))
  cds <- synthetic_cds_with_external_assay(s$spec$cds_a, work)
  before <- file_state(src)

  err <- expect_error(
    suppressMessages(save_monocle_cds(cds, "cds_ext", src)),
    class = "projectData.monocle3_external_assay"
  )
  expect_s3_class(err, "projectData.monocle3_save_error")
  expect_match(conditionMessage(err), "EXT", fixed = TRUE)
  expect_identical(file_state(src), before)
  expect_length(stage_dirs(src), 0L)
  expect_false(dir.exists(file.path(src, "inst")))
})
