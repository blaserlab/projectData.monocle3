# The adapter depends on interfaces of monocle3 and BPCells that neither package
# documents as a stable format: the layout written by save_monocle_objects(), the
# BPCells matrix directory, and the matrix_control interface of
# load_monocle_objects(). These tests state those assumptions on the installed
# versions, so a dependency upgrade that changes one of them fails here with a
# message that names the assumption, instead of surfacing as a confusing failure
# (or silent data loss) elsewhere. They add no behavior of their own.

contract_msg <- function(what) {
  paste0("Dependency contract changed: ", what, ". monocle3 ", utils::packageVersion("monocle3"),
         ", BPCells ", utils::packageVersion("BPCells"),
         ". Review R/loader.R and R/filesystem.R before supporting this version.")
}

test_that("contract: save_monocle_objects() writes a native index, an rds CDS and one BPCells directory", {
  skip_if_no_e2e()
  s <- synthetic_suite()
  for (name in c("cds_a", "cds_b")) {
    dir <- file.path(s$src, "inst", "extdata", name)
    index <- readRDS(file.path(dir, "file_index.rds"))
    expect_identical(index$save_function, "save_monocle_objects", info = contract_msg("file_index$save_function"))
    expect_null(file_index_listing_problem(index, name), info = contract_msg("file_index$files layout"))

    files <- index$files
    expect_identical(sum(files$cds_object == "cds" & files$file_format == "rds"), 1L,
                     info = contract_msg("exactly one CDS entry (cds_object cds, file_format rds)"))
    expect_identical(sum(files$cds_object == "bpcells_matrix_dir"), 1L,
                     info = contract_msg("exactly one bpcells_matrix_dir entry"))
    expect_true(all(file.exists(file.path(dir, files$file_path))), info = contract_msg("every listed file exists"))
    # No archive, nothing beyond the index and what it lists.
    expect_setequal(list.files(dir, all.files = TRUE, no.. = TRUE),
                    c("file_index.rds", unique(vapply(strsplit(files$file_path, "/", fixed = TRUE), `[`, "", 1L))))

    matrix_dir <- file.path(dir, files$file_path[files$cds_object == "bpcells_matrix_dir"])
    present <- list.files(matrix_dir)
    expect_true(all(bpcells_required_files %in% present),
                info = contract_msg(paste("BPCells directory lacks", paste(setdiff(bpcells_required_files, present), collapse = ", "))))
    expect_true(any(c("val", "val_data") %in% present), info = contract_msg("BPCells values file"))
    expect_identical(backing_dir_problems(matrix_dir), character(), info = contract_msg("BPCells directory check"))
  }
})

test_that("contract: the matrix_control interface of monocle3 is what the loader passes", {
  skip_if_no_e2e()
  expect_true(all(c("directory_path", "matrix_control") %in% names(formals(monocle3::load_monocle_objects))),
              info = contract_msg("load_monocle_objects(directory_path =, matrix_control =)"))
  control <- monocle3::set_matrix_control(list(matrix_class = "BPCells", matrix_mode = "dir",
                                               matrix_path = tempdir()))
  expect_identical(control$matrix_class, "BPCells", info = contract_msg("matrix_control$matrix_class"))
  expect_identical(control$matrix_mode, "dir", info = contract_msg("matrix_control$matrix_mode"))
  expect_identical(control$matrix_path, tempdir(), info = contract_msg("matrix_control$matrix_path"))
})

test_that("contract: BPCells exposes the matrix class and the inspection API the adapter uses", {
  skip_if_no_e2e()
  expect_true(exists("all_matrix_inputs", envir = asNamespace("BPCells"), inherits = FALSE),
              info = contract_msg("BPCells::all_matrix_inputs"))
  expect_true("all_matrix_inputs" %in% getNamespaceExports("BPCells"), info = contract_msg("all_matrix_inputs exported"))
  expect_true("dir" %in% names(methods::getClass("MatrixDir", where = asNamespace("BPCells"))@slots),
              info = contract_msg("MatrixDir@dir slot"))
  counts <- SummarizedExperiment::assay(synthetic_suite()$cds$cds_b, "counts")
  leaves <- vapply(BPCells::all_matrix_inputs(counts), function(m) class(m)[[1]], "")
  expect_true("MatrixDir" %in% leaves, info = contract_msg("all_matrix_inputs() reports the MatrixDir leaf"))
})

test_that("contract: a restored CDS keeps its content and puts every matrix copy under the work directory", {
  skip_if_no_e2e()
  s <- synthetic_suite()
  dir <- withr::local_tempdir("pdm3-contract-")
  control <- monocle3::set_matrix_control(list(matrix_class = "BPCells", matrix_mode = "dir", matrix_path = dir))
  cds <- with_attached("monocle3", suppressMessages(monocle3::load_monocle_objects(
    file.path(s$src, "inst", "extdata", "cds_b"), matrix_control = control)))
  expect_summary_matches_spec(cds_summary(cds), s$spec$cds_b, "MatrixDir")
  # Both the counts and the derived row-order copy are written below matrix_path.
  expect_true(in_tree(SummarizedExperiment::assay(cds, "counts")@dir, dir),
              info = contract_msg("restored counts directory is under matrix_path"))
  expect_true(in_tree(SummarizedExperiment::assay(cds, "counts_row_order")@dir, dir),
              info = contract_msg("counts_row_order directory is under matrix_path"))
  expect_false(in_tree(SummarizedExperiment::assay(cds, "counts")@dir, s$src),
               info = contract_msg("restored counts do not reference the saved source"))
})
