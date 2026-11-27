# Helpers for the vignettes: build a tiny synthetic Monocle 3 cell_data_set, and
# a throwaway data package installed into a temporary library. Nothing is
# written outside the directories you pass in. Sourced by the vignettes with
# source(system.file("examples", "demo-package.R", package = "projectData.monocle3")).
# Needs monocle3 (attached), BPCells, SingleCellExperiment and Matrix.

# A small synthetic CDS. With counts = "memory" the counts are a dgCMatrix
# (save_monocle_cds() converts them); with "bpcells" they are an on-disk BPCells
# matrix written to `dir`, which must outlive the object. `logcounts` is an
# in-memory alternative assay.
make_demo_cds <- function(dir = tempfile("demo-counts-"), counts = c("memory", "bpcells"),
                     n_genes = 40, n_cells = 25, seed = 3817) {
  counts <- match.arg(counts)
  genes <- sprintf("gene%02d", seq_len(n_genes))
  cells <- sprintf("cell%02d", seq_len(n_cells))
  set.seed(seed)
  m <- matrix(rpois(n_genes * n_cells, lambda = 2), n_genes, n_cells,
              dimnames = list(genes, cells))
  # Every gene and cell must be observed.
  m[cbind(seq_len(n_genes), (seq_len(n_genes) %% n_cells) + 1L)] <- 3
  sparse <- Matrix::Matrix(m, sparse = TRUE)
  if (counts == "bpcells") {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    sparse <- suppressWarnings(suppressMessages(BPCells::write_matrix_dir(
      BPCells::convert_matrix_type(methods::as(sparse, "IterableMatrix"), "double"),
      file.path(dir, "counts")
    )))
  }
  cds <- suppressWarnings(suppressMessages(monocle3::new_cell_data_set(
    sparse,
    cell_metadata = data.frame(row.names = cells,
                               group = rep(c("a", "b"), length.out = n_cells)),
    gene_metadata = data.frame(row.names = genes, gene_short_name = toupper(genes))
  )))
  SummarizedExperiment::assay(cds, "logcounts") <- log1p(m)
  SingleCellExperiment::reducedDims(cds) <- list(
    UMAP = cbind(cos(seq_len(n_cells)), sin(seq_len(n_cells)))
  )
  cds
}

# A source package skeleton that R CMD INSTALL accepts.
demo_package_skeleton <- function(parent, name) {
  root <- file.path(parent, name)
  dir.create(root, recursive = TRUE)
  writeLines(c(
    paste("Package:", name),
    "Title: Demonstration Data Package",
    "Version: 0.1.0",
    "Authors@R: person('Ada', 'Author', email = 'ada@example.com', role = c('aut', 'cre'))",
    "Description: A tiny synthetic data package for the projectData.monocle3 vignettes.",
    "License: MIT + file LICENSE",
    "Suggests: projectData.monocle3",
    "Encoding: UTF-8"
  ), file.path(root, "DESCRIPTION"))
  writeLines(c(paste("YEAR:", format(Sys.Date(), "%Y")), "COPYRIGHT HOLDER: Ada Author"),
             file.path(root, "LICENSE"))
  dir.create(file.path(root, "R"))
  writeLines(character(), file.path(root, "NAMESPACE"))
  root
}

# Builds `name` with one saved dataset called `dataset`, documents it, and
# installs it into `lib`. Returns the source directory.
demo_data_package <- function(workdir, lib, name = "demoMonocleData",
                              dataset = "demo_cds", counts = "memory") {
  stopifnot(dir.exists(workdir), dir.exists(lib))
  root <- demo_package_skeleton(workdir, name)
  originals <- file.path(workdir, paste0(name, "-originals"))
  suppressMessages(projectData.monocle3::save_monocle_cds(
    make_demo_cds(originals, counts = counts), dataset, package_dir = root))
  writeLines(c(
    "#' Demonstration Monocle 3 dataset",
    "#'",
    "#' @format A Monocle 3 cell_data_set with BPCells-backed counts.",
    "#' @source Synthetic.",
    paste0("\"", dataset, "\"")
  ), file.path(root, "R", "data.R"))
  dir.create(file.path(root, "man"))
  writeLines(c(
    paste0("\\name{", dataset, "}"), paste0("\\alias{", dataset, "}"),
    "\\docType{data}", "\\title{Demonstration Monocle 3 dataset}",
    "\\format{A Monocle 3 cell_data_set with BPCells-backed counts.}",
    "\\description{Access it with \\code{projectData::data_attach()}.}",
    "\\keyword{datasets}"
  ), file.path(root, "man", paste0(dataset, ".Rd")))
  utils::install.packages(root, lib = lib, repos = NULL, type = "source", quiet = TRUE)
  root
}
