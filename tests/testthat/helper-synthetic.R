# Self-contained integration fixtures: a small synthetic CDS built from public
# APIs, a generated data package authored with save_monocle_cds(), built with
# `R CMD build`, and installed into throwaway libraries with `R CMD INSTALL`.
# Nothing here needs projectData.monocle3.testdata; those tests are the
# "historical" ones (helper-integration.R).
#
# These helpers use only the helper-fixtures.R / helper-save.R / helper-authoring.R
# conventions already in this directory (work_root(), cds_counts(), file_state(),
# local_clean_projectData(), ...).

source(test_path("child-probe.R"), local = TRUE)

# Expected values -----------------------------------------------------------

# Everything the synthetic dataset is built from, as plain R objects, so tests
# can compare a restored CDS with the exact inputs. Deterministic for a seed.
synthetic_spec <- function(seed = 4217L, n_genes = 24L, n_cells = 16L, prefix = "a") {
  genes <- sprintf("%s_gene%02d", prefix, seq_len(n_genes))
  cells <- sprintf("%s_cell%02d", prefix, seq_len(n_cells))
  counts <- withr::with_seed(seed, {
    m <- matrix(stats::rpois(n_genes * n_cells, lambda = rep(c(0.5, 4), length.out = n_genes * n_cells)),
                n_genes, n_cells, dimnames = list(genes, cells))
    # Every gene and cell is observed.
    m[cbind(seq_len(n_genes), (seq_len(n_genes) %% n_cells) + 1L)] <- 3L
    m
  })
  stopifnot(all(rowSums(counts) > 0), all(colSums(counts) > 0))

  adt_ids <- sprintf("%s_adt%d", prefix, 1:4)
  adt_counts <- withr::with_seed(seed + 1L, {
    matrix(stats::rpois(4L * n_cells, 20), 4L, n_cells, dimnames = list(adt_ids, cells))
  })

  list(
    seed = seed, prefix = prefix, genes = genes, cells = cells,
    # integer-valued doubles, as monocle3 and BPCells expect
    counts = Matrix::Matrix(counts, sparse = TRUE),
    cell_md = data.frame(
      row.names = cells,
      group = rep(c("a", "b"), length.out = n_cells),
      batch = rep(c("x", "y", "z"), length.out = n_cells),
      n_umi = as.integer(colSums(counts)),
      score = seq_len(n_cells) / 4
    ),
    gene_md = data.frame(
      row.names = genes,
      gene_short_name = sprintf("%sG%02d", toupper(prefix), seq_len(n_genes)),
      biotype = rep(c("coding", "lncRNA"), length.out = n_genes)
    ),
    logcounts = log1p(counts),
    spliced = Matrix::Matrix(floor(counts * 0.6), sparse = TRUE),
    adt = list(
      counts = adt_counts, logcounts = log1p(adt_counts),
      row_data = data.frame(row.names = adt_ids, marker = paste0("m_", adt_ids)),
      metadata = list(source = "adt", n = 4L)
    ),
    # Fixed numbers instead of a computed embedding, so that equality is exact.
    umap = cbind(cos(seq_len(n_cells) / 3), sin(seq_len(n_cells) / 3)) * 5,
    pca = outer(seq_len(n_cells), 1:5, function(i, j) sin(i * j / 7)),
    metadata = list(source = "synthetic", seed = seed, prefix = prefix)
  )
}

# Builds a cell_data_set from a spec through public monocle3, SingleCellExperiment
# and BPCells APIs. With counts = "bpcells" the counts are an on-disk BPCells
# matrix in `dir` (which must outlive the object); with "memory" they are a
# dgCMatrix. No file is written outside `dir`.
synthetic_cds <- function(spec, counts = c("memory", "bpcells"),
                          dir = withr::local_tempdir(.local_envir = parent.frame())) {
  counts <- match.arg(counts)
  quietly <- function(x) suppressWarnings(suppressMessages(x))
  matrix <- if (counts == "bpcells") {
    quietly(BPCells::write_matrix_dir(
      BPCells::convert_matrix_type(methods::as(spec$counts, "IterableMatrix"), "double"),
      file.path(dir, "counts")
    ))
  } else {
    spec$counts
  }
  cds <- quietly(with_attached("monocle3", monocle3::new_cell_data_set(
    matrix, cell_metadata = spec$cell_md, gene_metadata = spec$gene_md
  )))
  SummarizedExperiment::assay(cds, "logcounts") <- spec$logcounts
  SummarizedExperiment::assay(cds, "spliced") <- spec$spliced
  SingleCellExperiment::reducedDims(cds) <- list(PCA = spec$pca, UMAP = spec$umap)
  SingleCellExperiment::altExp(cds, "ADT") <- SingleCellExperiment::SingleCellExperiment(
    assays = list(counts = spec$adt$counts, logcounts = spec$adt$logcounts),
    rowData = spec$adt$row_data,
    metadata = spec$adt$metadata
  )
  S4Vectors::metadata(cds)$synthetic <- spec$metadata
  cds
}

# A CDS whose ADT alternative experiment is stored in an on-disk BPCells matrix:
# unsupported by save_monocle_cds().
synthetic_cds_with_external_assay <- function(spec, dir) {
  cds <- synthetic_cds(spec, "memory")
  external <- suppressWarnings(suppressMessages(BPCells::write_matrix_dir(
    BPCells::convert_matrix_type(methods::as(Matrix::Matrix(spec$adt$counts, sparse = TRUE), "IterableMatrix"), "double"),
    file.path(dir, "external-adt")
  )))
  SingleCellExperiment::altExp(cds, "EXT") <- SingleCellExperiment::SingleCellExperiment(
    assays = list(counts = external)
  )
  cds
}

# Expectations on a cds_summary() ------------------------------------------

# Compares a cds_summary() with the spec it was built from. Everything is
# exact: the fixture is small and nothing is estimated. The complete CDS is
# never compared with identical(): backing references and internal Monocle
# metadata legitimately differ.
expect_summary_matches_spec <- function(sm, spec, counts_backing = "MatrixDir") {
  expect_identical(sm$class, "cell_data_set")
  expect_true(sm$valid)
  expect_identical(sm$dim, dim(spec$counts))
  expect_identical(sm$dimnames, list(spec$genes, spec$cells))

  # Assays: counts is on disk; everything else is in memory and unchanged.
  expect_setequal(setdiff(sm$assay_names, "counts_row_order"), c("counts", "logcounts", "spliced"))
  expect_identical(unname(sm$assay_class[["counts"]]), counts_backing)
  expect_false(sm$assay_iterable[["logcounts"]])
  expect_false(sm$assay_iterable[["spliced"]])
  expect_equal(sm$assays$counts, as.matrix(spec$counts), tolerance = 0)
  expect_equal(sm$assays$logcounts, spec$logcounts, tolerance = 0)
  expect_equal(sm$assays$spliced, as.matrix(spec$spliced), tolerance = 0)
  if ("counts_row_order" %in% sm$assay_names) {
    expect_equal(sm$assays$counts_row_order, sm$assays$counts, tolerance = 0)
  }

  # Metadata of cells and genes.
  cols <- names(spec$cell_md)
  expect_identical(rownames(sm$col_data), spec$cells)
  expect_equal(sm$col_data[, cols], spec$cell_md, tolerance = 0)
  genes <- names(spec$gene_md)
  expect_identical(rownames(sm$row_data), spec$genes)
  expect_equal(sm$row_data[, genes], spec$gene_md, tolerance = 0)

  # Alternative experiment, in memory.
  expect_identical(names(sm$alt), "ADT")
  adt <- sm$alt$ADT
  expect_identical(adt$dim, c(4L, length(spec$cells)))
  expect_identical(adt$dimnames, list(rownames(spec$adt$counts), spec$cells))
  expect_identical(adt$assay_names, c("counts", "logcounts"))
  expect_equal(adt$assays$counts, spec$adt$counts, tolerance = 0)
  expect_equal(adt$assays$logcounts, spec$adt$logcounts, tolerance = 0)
  expect_equal(adt$row_data$marker, spec$adt$row_data$marker)
  expect_identical(adt$metadata, spec$adt$metadata)

  # Reductions.
  expect_setequal(names(sm$reduced), c("PCA", "UMAP"))
  expect_equal(sm$reduced$UMAP, unname_cols(spec$umap), ignore_attr = TRUE, tolerance = 0)
  expect_equal(sm$reduced$PCA, unname_cols(spec$pca), ignore_attr = TRUE, tolerance = 0)

  # Object-level metadata.
  expect_identical(sm$metadata$synthetic, spec$metadata)
  expect_true(is.character(sm$metadata$cds_version))
}

# A package scaffold ---------------------------------------------------------

# Minimal source tree of a data package: DESCRIPTION, an empty NAMESPACE, and
# conventional documentation (R/data.R plus the .Rd files roxygen2 would write)
# for each dataset name. Returns the package root.
synthetic_package_source <- function(name, datasets, parent, version = "0.0.0.9001") {
  dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  root <- file.path(parent, name)
  dir.create(file.path(root, "R"), recursive = TRUE)
  dir.create(file.path(root, "man"))
  writeLines(c(
    paste("Package:", name),
    "Title: Synthetic Disk-Backed CDS Data",
    paste("Version:", version),
    "Authors@R: person('Test', 'Author', email = 'test@example.com', role = c('aut', 'cre'))",
    "Description: Synthetic data for testing projectData.monocle3.",
    "License: MIT + file LICENSE",
    "LazyData: true",
    "Encoding: UTF-8"
  ), file.path(root, "DESCRIPTION"))
  writeLines(c("YEAR: 2026", "COPYRIGHT HOLDER: Test Author"), file.path(root, "LICENSE"))
  writeLines(character(), file.path(root, "NAMESPACE"))
  writeLines(unlist(lapply(datasets, function(d) c(
    paste0("#' Synthetic dataset ", d),
    "#'",
    "#' @format A Monocle 3 cell_data_set with BPCells-backed counts.",
    "#' @details Access using projectData::data_attach().",
    paste0("\"", d, "\""),
    ""
  ))), file.path(root, "R", "data.R"))
  for (d in datasets) {
    writeLines(c(
      paste0("\\name{", d, "}"), "\\docType{data}", paste0("\\alias{", d, "}"),
      paste0("\\title{Synthetic dataset ", d, "}"),
      "\\format{A Monocle 3 cell_data_set with BPCells-backed counts.}",
      "\\usage{", d, "}", "\\description{Synthetic dataset.}", "\\keyword{datasets}"
    ), file.path(root, "man", paste0(d, ".Rd")))
  }
  root
}

# Subprocess helpers ---------------------------------------------------------

# Runs `R CMD <args>` in `wd`. Stops with the complete output on failure.
run_r_cmd <- function(args, wd = getwd()) {
  out <- withr::with_dir(wd, suppressWarnings(system2(
    file.path(R.home("bin"), "R"), args, stdout = TRUE, stderr = TRUE
  )))
  status <- attr(out, "status") %||% 0L
  if (!identical(status, 0L)) {
    stop(sprintf("`R %s` failed with status %s.\n--- output ---\n%s", paste(args, collapse = " "),
                 status, paste(out, collapse = "\n")), call. = FALSE)
  }
  out
}

# Builds a source package with `R CMD build`; returns the tarball path. The
# output is kept in attr(, "log") for diagnostics.
build_source_package <- function(src, dest) {
  dir.create(dest, showWarnings = FALSE, recursive = TRUE)
  log <- run_r_cmd(c("CMD", "build", "--no-build-vignettes", "--no-manual", "--no-resave-data",
                     shQuote(src)), wd = dest)
  pkg <- read.dcf(file.path(src, "DESCRIPTION"), c("Package", "Version"))
  tarball <- file.path(dest, sprintf("%s_%s.tar.gz", pkg[[1, "Package"]], pkg[[1, "Version"]]))
  if (!file.exists(tarball)) {
    stop("R CMD build produced no tarball at ", tarball, ".\n--- output ---\n", paste(log, collapse = "\n"))
  }
  structure(tarball, log = log)
}

# Installs a tarball into `lib` (created) with `R CMD INSTALL`; returns `lib`.
# The output is kept in attr(, "log").
install_tarball <- function(tarball, lib) {
  dir.create(lib, showWarnings = FALSE, recursive = TRUE)
  log <- run_r_cmd(c("CMD", "INSTALL", "-l", shQuote(lib), shQuote(tarball)))
  name <- sub("_.*$", "", basename(tarball))
  if (!file.exists(file.path(lib, name, "DESCRIPTION"))) {
    stop("Installation left no package in ", lib, ".\n--- output ---\n", paste(log, collapse = "\n"))
  }
  structure(lib, log = log)
}

# Installs a package `name` into a new library that cannot be loaded (its
# .onLoad fails), so requireNamespace(name) is FALSE while the library is first
# in the library paths. Returns the library.
local_stub_library <- function(name, env = parent.frame()) {
  work <- withr::local_tempdir("pdm3-stub-", .local_envir = env)
  src <- file.path(work, name)
  dir.create(file.path(src, "R"), recursive = TRUE)
  writeLines(c(paste("Package:", name), "Title: Stub That Cannot Load", "Version: 99.0.0",
               "Description: A stub for tests.", "License: MIT + file LICENSE",
               "Authors@R: person('Test', 'Author', email = 'test@example.com', role = c('aut', 'cre'))"),
             file.path(src, "DESCRIPTION"))
  writeLines(c("YEAR: 2026", "COPYRIGHT HOLDER: Test"), file.path(src, "LICENSE"))
  writeLines(character(), file.path(src, "NAMESPACE"))
  writeLines(".onLoad <- function(libname, pkgname) stop('hidden for a test')", file.path(src, "R", "zzz.R"))
  lib <- file.path(work, "lib")
  dir.create(lib)
  run_r_cmd(c("CMD", "INSTALL", "--no-test-load", "-l", shQuote(lib), shQuote(src)))
  lib
}

# How a child R process should load the adapter under test: from the source
# tree when the tests run under devtools::test(), installed otherwise.
adapter_for_child <- function() {
  if (requireNamespace("pkgload", quietly = TRUE) && pkgload::is_dev_package("projectData.monocle3")) {
    return(find.package("projectData.monocle3"))
  }
  if (!nzchar(system.file(package = "projectData.monocle3"))) {
    integration_gate("projectData.monocle3 cannot be loaded in a child process")
  }
  NULL
}

# Runs `op` (a function of child-probe.R) with `args` in a fresh `Rscript`
# process with the same library paths, and returns its result. A failure inside
# the child is returned as a `probe_error` list; a crash stops with the output.
run_child <- function(op, args, dir = withr::local_tempdir(.local_envir = parent.frame())) {
  args <- c(args, list(op = op, libpaths = .libPaths(), out = file.path(dir, "result.rds"),
                       adapter_path = adapter_for_child(),
                       probe_file = normalizePath(test_path("child-probe.R"))))
  args_file <- file.path(dir, "args.rds")
  script <- file.path(dir, "child.R")
  saveRDS(args, args_file)
  writeLines(c(
    "args <- readRDS(commandArgs(TRUE)[[1]])",
    ".libPaths(args$libpaths)",
    "source(args$probe_file)",
    "res <- tryCatch(get(args$op)(args), error = function(e) {",
    "  structure(list(message = conditionMessage(e), class = class(e)), class = 'probe_error')",
    "})",
    "saveRDS(res, args$out)"
  ), script)
  output <- suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"), c("--vanilla", shQuote(script), shQuote(args_file)),
    stdout = TRUE, stderr = TRUE
  ))
  if (!file.exists(args$out)) {
    stop("The child R process produced no result.\n--- output ---\n", paste(output, collapse = "\n"),
         call. = FALSE)
  }
  structure(readRDS(args$out), output = output)
}

# The suite: authored once, installed twice --------------------------------

synthetic_pkg <- "pdm3SyntheticData"

# One source package with two resources, authored with save_monocle_cds():
# `cds_a` starts with in-memory counts (converted automatically), `cds_b` with
# BPCells-backed counts. It is built once and installed into two libraries.
# Everything lives under one directory (spaces and, where the locale allows,
# non-ASCII characters in its name) removed at the end of the test run.
synthetic_suite <- function() {
  if (!is.null(fixture_cache$suite)) return(fixture_cache$suite)
  skip_if_no_e2e()
  odd <- if (isTRUE(l10n_info()[["UTF-8"]])) "pdm3 suite \u00fc\u00e9 " else "pdm3 suite "
  base <- tempfile(odd)
  dir.create(base)
  withr::defer(unlink(base, recursive = TRUE), envir = testthat::teardown_env())

  spec_a <- synthetic_spec(4217L, 24L, 16L, "a")
  spec_b <- synthetic_spec(8093L, 30L, 12L, "b")
  author <- file.path(base, "author")
  dir.create(author)
  cds_a <- synthetic_cds(spec_a, "memory", file.path(author, "a"))
  cds_b <- synthetic_cds(spec_b, "bpcells", file.path(author, "b"))

  src <- synthetic_package_source(synthetic_pkg, c("cds_a", "cds_b"), file.path(base, "source tree"))
  saved_a <- save_quiet(cds_a, "cds_a", src)
  saved_b <- save_quiet(cds_b, "cds_b", src)
  tarball <- build_source_package(src, file.path(base, "tarball"))
  lib_a <- install_tarball(tarball, file.path(base, "library A"))
  lib_b <- install_tarball(tarball, file.path(base, "library B"))

  fixture_cache$suite <- list(
    base = base, src = src, tarball = tarball, lib_a = lib_a, lib_b = lib_b, pkg = synthetic_pkg,
    spec = list(cds_a = spec_a, cds_b = spec_b),
    cds = list(cds_a = cds_a, cds_b = cds_b),
    saved = list(cds_a = saved_a, cds_b = saved_b),
    # How each resource's counts were stored before saving.
    counts_before = list(cds_a = class(SummarizedExperiment::assay(cds_a, "counts"))[[1]],
                         cds_b = class(SummarizedExperiment::assay(cds_b, "counts"))[[1]]),
    install_log = attr(lib_a, "log")
  )
  fixture_cache$suite
}

# Gate for the self-contained end-to-end tests. Ordinary runs skip when the
# declared runtime dependencies are missing (and on CRAN); with
# PDM3_INTEGRATION_TESTS=true a missing dependency is a failure.
skip_if_no_e2e <- function() {
  if (!integration_mode()) skip_on_cran()
  integration_gate(dependency_problems())
  invisible()
}

# A disposable copy of an installed package of the suite, in a new library.
# `lib` is the library to copy from. Never modifies the original.
local_package_copy <- function(lib = synthetic_suite()$lib_a, pkg = synthetic_pkg,
                               env = parent.frame()) {
  copy <- withr::local_tempdir("pdm3-copy-", .local_envir = env)
  stopifnot(file.copy(file.path(lib, pkg), copy, recursive = TRUE))
  copy
}

in_tree <- function(path, dir) {
  startsWith(normalizePath(path, winslash = "/", mustWork = FALSE),
             paste0(normalizePath(dir, winslash = "/", mustWork = FALSE), "/"))
}
