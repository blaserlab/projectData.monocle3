# Self-contained code shared by the parent test process and by fresh child R
# processes (see helper-synthetic.R). It must not use any other test helper:
# the child only has this file, the installed packages and, under
# devtools::test(), the adapter loaded with pkgload.

# A plain-R description of a cell_data_set, with every small value spelled out so
# that results can be compared across processes. Counts are densified; only use
# on tiny objects.
cds_summary <- function(cds) {
  dense <- function(m) suppressMessages(suppressWarnings(as.matrix(m)))
  assay_names <- SummarizedExperiment::assayNames(cds)
  backing_dir <- function(name) {
    if (!name %in% assay_names) return(NA_character_)
    m <- SummarizedExperiment::assay(cds, name)
    if (methods::is(m, "MatrixDir")) normalizePath(m@dir, winslash = "/", mustWork = FALSE) else NA_character_
  }
  alt <- lapply(stats::setNames(nm = SingleCellExperiment::altExpNames(cds)), function(nm) {
    a <- SingleCellExperiment::altExp(cds, nm)
    list(
      dim = dim(a), dimnames = dimnames(a),
      assay_names = SummarizedExperiment::assayNames(a),
      assays = lapply(stats::setNames(nm = SummarizedExperiment::assayNames(a)),
                      function(x) dense(SummarizedExperiment::assay(a, x))),
      row_data = as.data.frame(SummarizedExperiment::rowData(a)),
      metadata = S4Vectors::metadata(a)
    )
  })
  list(
    class = class(cds)[[1]],
    valid = isTRUE(methods::validObject(cds, test = TRUE)),
    dim = dim(cds),
    dimnames = dimnames(cds),
    assay_names = assay_names,
    assay_class = vapply(assay_names, function(a) class(SummarizedExperiment::assay(cds, a))[[1]], ""),
    assay_iterable = vapply(assay_names, function(a) methods::is(SummarizedExperiment::assay(cds, a), "IterableMatrix"), NA),
    assays = lapply(stats::setNames(nm = assay_names),
                    function(a) dense(SummarizedExperiment::assay(cds, a))),
    col_data = as.data.frame(SummarizedExperiment::colData(cds)),
    row_data = as.data.frame(SummarizedExperiment::rowData(cds)),
    reduced = lapply(SingleCellExperiment::reducedDims(cds), function(m) unname_cols(as.matrix(m))),
    alt = alt,
    metadata = S4Vectors::metadata(cds),
    counts_dir = backing_dir("counts"),
    row_order_dir = backing_dir("counts_row_order")
  )
}

unname_cols <- function(m) {
  colnames(m) <- NULL
  m
}

# The installed package tree as file name -> checksum.
tree_checksums <- function(dir) {
  files <- list.files(dir, recursive = TRUE, all.files = TRUE)
  stats::setNames(unname(tools::md5sum(file.path(dir, files))), files)
}

catalog_rows <- function(pkg) {
  cat <- projectData::data_catalog()
  cat <- cat[cat$package == pkg, c("object", "state", "storage", "loader", "origin", "source"), drop = FALSE]
  cat[order(cat$object), , drop = FALSE]
}

# Attaches data package `args$pkg` from `args$lib`, opens `args$resources`
# through the documented projectData interface, and reports what happened.
#
# The adapter is deliberately not registered here: projectData resolves it from
# the manifest. With `args$spy` the adapter's loader is registered wrapped, to
# record the `paths` projectData passes to open().
probe_load <- function(args) {
  if (!is.null(args$adapter_path)) pkgload::load_all(args$adapter_path, quiet = TRUE)
  cwd_before <- getwd()
  search_before <- search()
  work_root <- normalizePath(file.path(tempdir(), "projectData-work"), winslash = "/", mustWork = FALSE)
  installed <- file.path(args$lib, args$pkg)
  checksums_before <- tree_checksums(installed)

  projectData::data_config(messages = FALSE)
  spy <- new.env()
  spy$paths <- list()
  if (isTRUE(args$spy)) {
    loader <- projectData.monocle3::projectData_loaders()
    inner <- loader$open
    loader$open <- function(descriptor, paths, context) {
      spy$paths[[descriptor$resource]] <- paths
      inner(descriptor, paths, context)
    }
    projectData::data_loader_add(loader)
  }

  projectData::data_attach(args$pkg, lib.loc = args$lib)
  catalog_before <- catalog_rows(args$pkg)
  work_after_attach <- list.files(work_root, recursive = TRUE)
  loaders_after_attach <- projectData::data_loaders()$id

  objects <- lapply(stats::setNames(nm = args$resources), function(r) projectData::data_get(r))
  summaries <- lapply(objects, cds_summary)
  catalog_opened <- catalog_rows(args$pkg)
  loaders_after_open <- projectData::data_loaders()$id

  projectData::data_detach()
  retained <- lapply(objects, cds_summary)

  list(
    summaries = summaries,
    retained = retained,
    # normalized now: the child's temporary directory is gone once it exits
    paths = lapply(as.list(spy$paths), function(p) {
      lapply(p, normalizePath, winslash = "/", mustWork = FALSE)
    }),
    installed = normalizePath(installed, winslash = "/"),
    work_root = work_root,
    catalog_before = catalog_before,
    catalog_opened = catalog_opened,
    work_after_attach = work_after_attach,
    loaders_after_attach = loaders_after_attach,
    loaders_after_open = loaders_after_open,
    cwd_unchanged = identical(getwd(), cwd_before),
    search_unchanged = identical(search(), search_before),
    installed_unchanged = identical(tree_checksums(installed), checksums_before),
    namespaces = list(adapter = isNamespaceLoaded("projectData.monocle3"),
                      monocle3_attached = "package:monocle3" %in% search())
  )
}

# Opens `args$resource` while a stub `monocle3` package that cannot be loaded
# comes first in the library paths, then restores the real paths and retries.
probe_missing_dependency <- function(args) {
  if (!is.null(args$adapter_path)) pkgload::load_all(args$adapter_path, quiet = TRUE)
  projectData::data_config(messages = FALSE)
  state <- function() {
    cat <- projectData::data_catalog()
    cat$state[cat$package == args$pkg & cat$object == args$resource]
  }
  .libPaths(c(args$stub_lib, args$libpaths))
  projectData::data_attach(args$pkg, lib.loc = args$lib)
  error <- tryCatch(projectData::data_get(args$resource), error = function(e) e)
  failed <- list(class = class(error), message = conditionMessage(error), state = state())

  .libPaths(args$libpaths)
  projectData::data_retry(args$pkg, args$resource)
  recovered <- cds_summary(projectData::data_get(args$resource))
  list(failed = failed, state_after_retry = state(), recovered = recovered)
}
