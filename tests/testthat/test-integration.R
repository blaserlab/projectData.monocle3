# End-to-end tests with real monocle3 and BPCells objects. The adapter is
# resolved by projectData from the manifest; these tests never call
# library(projectData.monocle3).

test_that("registration does not open or allocate anything, before or after the loader is registered", {
  skip_if_no_monocle()
  local_clean_projectData()
  lib <- shared_cds_lib()
  counter <- local_open_counter()
  before <- list.files(work_root(), recursive = TRUE)

  projectData::data_attach("pdcdsdata", lib.loc = lib)
  expect_length(counter$log, 0)
  expect_identical(list.files(work_root(), recursive = TRUE), before)
  cat <- projectData::data_catalog()
  expect_true(all(cat$state[cat$object %in% c("human_cds", "mouse_cds")] != "ready"))

  projectData::data_detach()
  # With the loader registered, validate runs at registration; still no open.
  projectData::data_loader_adapter("projectData.monocle3")
  projectData::data_attach("pdcdsdata", lib.loc = lib)
  expect_length(counter$log, 0)
  expect_identical(list.files(work_root(), recursive = TRUE), before)
  cat <- projectData::data_catalog()
  cds_rows <- cat$object %in% c("human_cds", "mouse_cds")
  expect_true(all(cat$state[cds_rows] == "unopened"))
  expect_true(all(cat$storage[cds_rows] == "disk-backed"))
})

test_that("first access through an attached binding resolves the adapter, opens once, and leaves the search path alone", {
  skip_if_no_monocle()
  local_clean_projectData()
  lib <- shared_cds_lib()
  counter <- local_open_counter()
  projectData::data_attach("pdcdsdata", lib.loc = lib)
  search_before <- search()

  cds <- get("human_cds", envir = as.environment("projectData:data"))
  expect_identical(counter$log, "pdcdsdata/human_cds")
  expect_s4_class(cds, "cell_data_set")
  expect_true(validObject(cds))
  expect_true(isNamespaceLoaded("projectData.monocle3"))
  # Neither monocle3 nor its dependencies stay attached after opening.
  expect_identical(search(), search_before)
  expect_false("package:monocle3" %in% search())
})

test_that("data_get() restores counts, metadata and reductions faithfully", {
  skip_if_no_monocle()
  local_clean_projectData()
  lib <- shared_cds_lib()
  expected <- cds_fixtures()$human$expected

  cds <- projectData::data_get("human_cds", package = "pdcdsdata", lib.loc = lib)

  expect_s4_class(SummarizedExperiment::assay(cds, "counts"), "MatrixDir")
  expect_equal(unname(cds_counts(cds)), unname(expected$counts))
  expect_identical(dimnames(cds), dimnames(expected$counts))
  expect_equal(as.data.frame(SummarizedExperiment::colData(cds))[, c("group", "n")],
               expected$cell_md, ignore_attr = TRUE)
  expect_identical(as.data.frame(SummarizedExperiment::rowData(cds))$gene_short_name,
                   expected$gene_md$gene_short_name)
  expect_setequal(SingleCellExperiment::reducedDimNames(cds), c("PCA", "UMAP"))
  expect_equal(SingleCellExperiment::reducedDims(cds)$UMAP, expected$umap)
  expect_equal(SingleCellExperiment::reducedDims(cds)$PCA, expected$pca)
})

test_that("opening writes nothing into getwd() and puts BPCells files under the allocated work_dir", {
  skip_if_no_monocle()
  local_clean_projectData()
  lib <- shared_cds_lib()
  spy <- local_path_spy()
  cwd <- withr::local_tempdir("pdm3-cwd-")
  withr::local_dir(cwd)

  cds <- projectData::data_get("human_cds", package = "pdcdsdata", lib.loc = lib)

  expect_identical(normalizePath(getwd()), normalizePath(cwd))
  expect_length(list.files(cwd, all.files = TRUE, no.. = TRUE), 0)

  work_dir <- spy$paths$human_cds$work_dir
  expect_true(in_dir(work_dir, work_root()))
  expect_true(in_dir(counts_dir(cds), work_dir))
  expect_false(in_dir(counts_dir(cds), lib))
  # monocle3 also keeps a row-ordered copy of the counts; it is in work_dir too.
  copies <- list.files(work_dir, pattern = "^monocle\\.bpcells\\..*\\.tmp$")
  expect_gte(length(copies), 2)
  expect_false(startsWith(basename(work_dir), "monocle"))
})

test_that("two resources get independent working directories", {
  skip_if_no_monocle()
  local_clean_projectData()
  lib <- shared_cds_lib()
  spy <- local_path_spy()
  fx <- cds_fixtures()

  human <- projectData::data_get("human_cds", package = "pdcdsdata", lib.loc = lib)
  mouse <- projectData::data_get("mouse_cds", package = "pdcdsdata", lib.loc = lib)

  wd_h <- spy$paths$human_cds$work_dir
  wd_m <- spy$paths$mouse_cds$work_dir
  expect_false(identical(wd_h, wd_m))
  expect_false(in_dir(wd_h, wd_m) || in_dir(wd_m, wd_h))
  expect_true(in_dir(counts_dir(human), wd_h))
  expect_true(in_dir(counts_dir(mouse), wd_m))
  expect_equal(dim(human), dim(fx$human$expected$counts))
  expect_equal(dim(mouse), dim(fx$mouse$expected$counts))
  expect_equal(unname(cds_counts(mouse)), unname(fx$mouse$expected$counts))
})

test_that("repeated access uses the cached resource", {
  skip_if_no_monocle()
  local_clean_projectData()
  lib <- shared_cds_lib()
  counter <- local_open_counter()
  spy <- local_path_spy()
  projectData::data_attach("pdcdsdata", lib.loc = lib)

  first <- projectData::data_get("human_cds")
  dirs_after_first <- list.dirs(work_root(), recursive = TRUE)
  second <- projectData::data_get("human_cds")
  third <- get("human_cds", envir = as.environment("projectData:data"))

  expect_identical(counter$log, "pdcdsdata/human_cds")
  expect_identical(counts_dir(first), counts_dir(second))
  expect_identical(counts_dir(first), counts_dir(third))
  expect_identical(list.dirs(work_root(), recursive = TRUE), dirs_after_first)
  expect_length(spy$paths, 1)
})

test_that("a retained CDS keeps working after data_detach()", {
  skip_if_no_monocle()
  local_clean_projectData()
  lib <- shared_cds_lib()
  expected <- cds_fixtures()$human$expected
  projectData::data_attach("pdcdsdata", lib.loc = lib)
  cds <- projectData::data_get("human_cds")
  dir <- counts_dir(cds)

  projectData::data_detach()

  expect_false("human_cds" %in% projectData::data_catalog()$object)
  expect_true(dir.exists(dir))
  expect_equal(unname(cds_counts(cds)), unname(expected$counts))
})

test_that("the manifest validates against the installed package", {
  skip_if_no_monocle()
  local_clean_projectData()
  lib <- shared_cds_lib()
  projectData::data_loader_adapter("projectData.monocle3")
  pkg <- file.path(lib, "pdcdsdata")
  d <- projectData::data_manifest_validate(file.path(pkg, "projectData", "manifest.dcf"),
                                           root = pkg)
  expect_length(d, 2)
  expect_identical(d[[1]]$loader, "projectData.monocle3::cds")
  expect_identical(d[[1]]$adapter$export, "projectData_loaders")
  expect_identical(d[[1]]$recorded_class, "cell_data_set")
})

test_that("invalid saved directories fail with informative messages and mark the resource failed", {
  skip_if_no_monocle()
  local_clean_projectData()
  empty <- withr::local_tempdir("pdm3-empty-")
  lib <- install_cds_package(list(bad_cds = empty), pkg = "pdcdsbad")

  expect_error(
    projectData::data_get("bad_cds", package = "pdcdsbad", lib.loc = lib),
    "no file_index.rds",
    class = "projectData_opening_failed"
  )
  cat <- projectData::data_catalog()
  expect_identical(cat$state[cat$object == "bad_cds"], "failed")
})

test_that("data_retry() supports a new attempt after the installation is repaired", {
  skip_if_no_monocle()
  local_clean_projectData()
  fx <- cds_fixtures()
  lib <- install_cds_package(list(human_cds = fx$human$saved), pkg = "pdcdsretry")
  installed <- file.path(lib, "pdcdsretry", "extdata", "human_cds")
  matrix_dir <- file.path(installed, "bpcells_matrix_dir")
  parked <- paste0(matrix_dir, ".parked")
  expect_true(file.rename(matrix_dir, parked))
  counter <- local_open_counter()

  expect_error(
    projectData::data_get("human_cds", package = "pdcdsretry", lib.loc = lib),
    "missing saved file.*bpcells_matrix_dir",
    class = "projectData_opening_failed"
  )
  # A rejection by validate() never reaches open().
  expect_length(counter$log, 0)
  expect_identical(
    projectData::data_catalog()$state[projectData::data_catalog()$object == "human_cds"],
    "failed"
  )

  expect_true(file.rename(parked, matrix_dir))
  expect_identical(projectData::data_retry("pdcdsretry"), "human_cds")
  cds <- projectData::data_get("human_cds", package = "pdcdsretry")
  expect_s4_class(cds, "cell_data_set")
  expect_equal(unname(cds_counts(cds)), unname(fx$human$expected$counts))
})

test_that("a restored CDS does not depend on the installed resource directory", {
  skip_if_no_monocle()
  skip_on_os("windows")  # an installed UMAP index stays mapped and cannot be removed
  local_clean_projectData()
  fx <- cds_fixtures()
  lib <- install_cds_package(list(human_cds = fx$human$saved), pkg = "pdcdsgone")
  spy <- local_path_spy()
  cds <- projectData::data_get("human_cds", package = "pdcdsgone", lib.loc = lib)
  work_dir <- spy$paths$human_cds$work_dir
  installed <- file.path(lib, "pdcdsgone")
  expect_true(dir.exists(installed))

  # Both matrix copies monocle3 made are in work_dir, not in the installation.
  expect_true(in_dir(counts_dir(cds), work_dir))
  row_order <- SummarizedExperiment::assay(cds, "counts_row_order")
  expect_true(in_dir(row_order@dir, work_dir))

  projectData::data_detach()
  unlink(installed, recursive = TRUE)
  expect_false(dir.exists(installed))

  # Real operations that read the counts, the PCA model and the UMAP index.
  expect_equal(unname(cds_counts(cds)), unname(fx$human$expected$counts))
  expect_equal(unname(Matrix::rowSums(SummarizedExperiment::assay(cds, "counts"))),
               unname(rowSums(fx$human$expected$counts)))
  withr::local_package("monocle3")
  transformed <- suppressMessages(preprocess_transform(cds, reduction_method = "PCA"))
  transformed <- suppressMessages(
    reduce_dimension_transform(transformed, reduction_method = "UMAP")
  )
  expect_identical(dim(SingleCellExperiment::reducedDims(transformed)$UMAP),
                   c(ncol(cds), 2L))
})
