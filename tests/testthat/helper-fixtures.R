# Fixtures for the projectData.monocle3 tests. Real monocle3/BPCells CDS
# objects are built in a separate R process (monocle3 constructors need
# monocle3 attached and monocle3/BPCells write temporary directories into
# the working directory), then installed inside throwaway data packages.

source(system.file("examples", "fixtures.R", package = "projectData"), local = TRUE)

skip_if_no_monocle <- function() {
  skip_on_cran()
  skip_if_not_installed("monocle3")
  skip_if_not_installed("BPCells")
  skip_if_not_installed("SingleCellExperiment")
  skip_if_not_installed("SummarizedExperiment")
  skip_if_not_installed("withr")
}

# Builds one saved CDS plus the values it was built from, in `dir`.
build_cds_fixture <- function(dir, seed, n_genes, n_cells, prefix) {
  dir.create(dir, recursive = TRUE)
  script <- file.path(dir, "build.R")
  writeLines(c(
    sprintf("setwd(%s)", deparse(dir)),
    "suppressMessages({library(monocle3); library(BPCells)})",
    sprintf("set.seed(%d)", seed),
    sprintf("ng <- %d; nc <- %d", n_genes, n_cells),
    "m <- matrix(rpois(ng * nc, lambda = rep(c(1, 6), length.out = ng * nc)), ng, nc,",
    sprintf("  dimnames = list(paste0('%sg', seq_len(ng)), paste0('%sc', seq_len(nc))))", prefix, prefix),
    "bp <- write_matrix_dir(convert_matrix_type(as(as(m, 'dgCMatrix'), 'IterableMatrix'), 'double'),",
    "  file.path(getwd(), 'bp_build'))",
    "cell_md <- data.frame(row.names = colnames(m), group = rep(c('a', 'b'), length.out = nc), n = seq_len(nc))",
    "gene_md <- data.frame(row.names = rownames(m), gene_short_name = paste0('G', seq_len(ng)))",
    "cds <- new_cell_data_set(bp, cell_metadata = cell_md, gene_metadata = gene_md)",
    "cds <- preprocess_cds(cds, num_dim = 5, verbose = FALSE)",
    "cds <- reduce_dimension(cds, reduction_method = 'UMAP', cores = 1, verbose = FALSE)",
    "save_monocle_objects(cds, file.path(getwd(), 'saved'), verbose = FALSE,",
    "  archive_control = list(archive_type = 'none'))",
    "saveRDS(list(counts = m, cell_md = cell_md, gene_md = gene_md,",
    "  umap = reducedDims(cds)$UMAP, pca = reducedDims(cds)$PCA), file.path(getwd(), 'expected.rds'))"
  ), script)
  status <- suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"), shQuote(script),
    stdout = FALSE, stderr = FALSE,
    env = paste0("R_LIBS=", paste(.libPaths(), collapse = .Platform$path.sep))
  ))
  saved <- file.path(dir, "saved")
  if (!identical(status, 0L) || !file.exists(file.path(saved, "file_index.rds"))) {
    return(NULL)
  }
  list(saved = saved, expected = readRDS(file.path(dir, "expected.rds")))
}

fixture_cache <- new.env()

# Two CDS fixtures of different shape, built once per test run.
cds_fixtures <- function() {
  if (is.null(fixture_cache$built)) {
    root <- tempfile("pdm3-fixtures-")
    withr::defer(unlink(root, recursive = TRUE), envir = testthat::teardown_env())
    fixture_cache$built <- list(
      human = build_cds_fixture(file.path(root, "human"), 4821, 300, 120, "h"),
      mouse = build_cds_fixture(file.path(root, "mouse"), 7305, 200, 80, "m")
    )
  }
  fx <- fixture_cache$built
  if (is.null(fx$human) || is.null(fx$mouse)) {
    skip("could not build a CDS fixture with the installed monocle3/BPCells")
  }
  fx
}

copy_dir_to <- function(from) {
  function(path) {
    dir.create(path, recursive = TRUE)
    file.copy(list.files(from, full.names = TRUE, all.files = TRUE, no.. = TRUE),
              path, recursive = TRUE)
  }
}

manifest_lines <- function(resources) {
  c("ManifestVersion: 1", "",
    unlist(lapply(resources, function(r) c(
      paste0("Resource: ", r),
      "Loader: projectData.monocle3::cds",
      paste0("Source: extdata/", r),
      paste0("Objects: ", r),
      "AdapterPackage: projectData.monocle3",
      "AdapterExport: projectData_loaders",
      "RecordedClass: cell_data_set",
      paste0("HelpTopic: ", r),
      ""))))
}

# Installs data package `pkg` into a new library. `sources` is a named list,
# resource name -> saved directory.
install_cds_package <- function(sources, pkg = "pdcdsdata", env = parent.frame()) {
  lib <- fixture_library()
  withr::defer(unlink(lib, recursive = TRUE), envir = env)
  fixture_package(lib, pkg, lazy = FALSE, datasets = list(),
    files = stats::setNames(lapply(sources, copy_dir_to),
                            paste0("extdata/", names(sources))),
    manifest = manifest_lines(names(sources)))
  lib
}

# Library shared by tests that do not modify the installation.
shared_cds_lib <- function() {
  if (is.null(fixture_cache$lib)) {
    fx <- cds_fixtures()
    lib <- install_cds_package(list(human_cds = fx$human$saved, mouse_cds = fx$mouse$saved),
                               env = testthat::teardown_env())
    fixture_cache$lib <- lib
  }
  fixture_cache$lib
}

# Restores projectData session state with the calling test.
local_clean_projectData <- function(env = parent.frame()) {
  old <- projectData::data_config()
  withr::defer({
    suppressWarnings(try(projectData::data_detach(), silent = TRUE))
    loaders <- projectData::data_loaders()
    for (id in loaders$id[!loaders$builtin]) projectData::data_loader_remove(id)
    projectData::data_config(messages = old$messages, on_open = old$on_open)
  }, envir = env)
  projectData::data_config(messages = FALSE, on_open = NULL)
  invisible()
}

local_open_counter <- function() {
  counter <- new.env()
  counter$log <- character()
  projectData::data_config(on_open = function(info) {
    counter$log <- c(counter$log, paste(info$collection, info$resource, sep = "/"))
  })
  counter
}

# Registers the real loader wrapped so a test can see the `paths` it received.
local_path_spy <- function() {
  spy <- new.env()
  spy$paths <- list()
  loader <- projectData.monocle3::projectData_loaders()
  inner <- loader$open
  loader$open <- function(descriptor, paths, context) {
    spy$paths[[descriptor$resource]] <- paths
    inner(descriptor, paths, context)
  }
  projectData::data_loader_add(loader)
  spy
}

work_root <- function() file.path(tempdir(), "projectData-work")

# Dense counts of a restored CDS, without attaching anything permanently.
cds_counts <- function(cds) {
  suppressWarnings(as.matrix(SummarizedExperiment::assay(cds, "counts")))
}

counts_dir <- function(cds) SummarizedExperiment::assay(cds, "counts")@dir

in_dir <- function(path, dir) {
  startsWith(normalizePath(path, winslash = "/"), paste0(normalizePath(dir, winslash = "/"), "/"))
}
