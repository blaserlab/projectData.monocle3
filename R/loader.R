#' Loader declaration for disk-backed Monocle 3 CDS objects
#'
#' `projectData_loaders()` is the adapter export that projectData looks for
#' when a manifest names `AdapterPackage: projectData.monocle3`. It returns one
#' [projectData::data_loader()] with id `projectData.monocle3::cds`. projectData
#' loads this package's namespace (it does not attach it) the first time a
#' resource that needs the loader is accessed, so users never need
#' `library(projectData.monocle3)`.
#'
#' Each resource is one directory written by
#' `monocle3::save_monocle_objects(cds, directory, archive_control =
#' list(archive_type = "none"))` from a CDS whose counts are a BPCells on-disk
#' matrix. The loader:
#'
#' * `validate` checks the directory structure from `file_index.rds` and file
#'   existence only. It never restores the CDS or reads matrix data.
#' * `open` calls `monocle3::load_monocle_objects()` on the installed
#'   directory with `matrix_control$matrix_path` set to the unique
#'   `paths$work_dir` allocated by projectData, and returns a named list with
#'   the single CDS.
#'
#' @section What the restored object references:
#' Monocle copies the BPCells matrix directory (and a second, row-ordered copy
#' it derives) into uniquely named subdirectories of `paths$work_dir`, so the
#' counts do not depend on the installed package. The work directory lives in
#' the session temporary directory and is removed by monocle3 when R exits.
#' The UMAP nearest-neighbour index, however, is memory-mapped by Annoy
#' directly from the installed file. On Linux and macOS the mapping survives
#' deletion of the file; on Windows an installed copy cannot be removed while
#' it is mapped. See the README for details.
#'
#' @return A `projectData_loader` object.
#' @seealso [projectData::data_loader()], [projectData::data_loader_adapter()]
#' @export
projectData_loaders <- function() {
  projectData::data_loader(
    id = "projectData.monocle3::cds",
    open = open_monocle_cds,
    validate = validate_monocle_cds,
    storage = "disk-backed",
    needs_work_dir = TRUE
  )
}

# validate ---------------------------------------------------------------

# Returns TRUE or a single message. Reads only the small file_index.rds.
validate_monocle_cds <- function(descriptor, root, context) {
  src <- descriptor$source
  if (!is_scalar_string(src)) {
    return("a Monocle CDS resource needs a `Source` directory")
  }
  objs <- descriptor$objects
  if (length(objs) != 1L || !is_scalar_string(objs)) {
    return(paste0("a Monocle CDS resource must declare exactly one object in ",
                  "`Objects`; got ", length(objs)))
  }
  dir <- file.path(root, src)
  if (!dir.exists(dir)) {
    return(paste0("saved Monocle directory '", src, "' does not exist"))
  }
  index_path <- file.path(dir, "file_index.rds")
  if (!file.exists(index_path)) {
    hint <- if (length(list.files(dir, pattern = "\\.tar(\\.gz)?$"))) {
      " (a tar archive was found; save with archive_control = list(archive_type = \"none\"))"
    } else {
      ""
    }
    return(paste0("'", src, "' has no file_index.rds, so it was not written by ",
                  "monocle3::save_monocle_objects()", hint))
  }
  index <- tryCatch(readRDS(index_path), error = function(e) e)
  if (inherits(index, "error")) {
    return(paste0("cannot read '", src, "/file_index.rds': ", conditionMessage(index)))
  }
  validate_file_index(index, dir, src)
}

validate_file_index <- function(index, dir, src) {
  idx <- paste0("'", src, "/file_index.rds'")
  if (!is.list(index) || !identical(index$save_function, "save_monocle_objects")) {
    return(paste0(idx, " was not written by monocle3::save_monocle_objects()"))
  }
  files <- index$files
  needed <- c("cds_object", "file_format", "file_path")
  if (!is.data.frame(files) || !all(needed %in% names(files)) || !nrow(files)) {
    return(paste0(idx, " does not list any saved files"))
  }
  # Column types and missing values are checked before any value is used in a
  # conditional or path operation.
  for (col in needed) {
    x <- files[[col]]
    if (!is.character(x)) {
      return(paste0(idx, " column `", col, "` must be character, not <",
                    class(x)[1L], ">"))
    }
    if (anyNA(x) || !all(nzchar(x))) {
      return(paste0(idx, " column `", col, "` has missing or empty values"))
    }
  }
  paths <- files$file_path
  if (any(grepl("^(/|[A-Za-z]:|~)", paths)) ||
      any(vapply(strsplit(paths, "[/\\\\]"), function(p) any(p == ".."), NA))) {
    return(paste0(idx, " lists paths that are not relative to the saved directory"))
  }
  if (anyDuplicated(paths)) {
    return(paste0(idx, " lists the same file path more than once"))
  }
  cds_rows <- files$cds_object == "cds"
  if (sum(cds_rows) != 1L || !identical(files$file_format[cds_rows], "rds")) {
    return(paste0("'", src, "' must hold exactly one CDS saved in rds format ",
                  "(hdf5_assays = TRUE is not supported)"))
  }
  mat_rows <- files$cds_object == "bpcells_matrix_dir"
  if (sum(mat_rows) != 1L) {
    return(paste0("'", src, "' has no BPCells matrix directory, so it is not a ",
                  "disk-backed CDS; convert the counts with ",
                  "monocle3::convert_counts_matrix() before saving"))
  }
  full <- file.path(dir, paths)
  missing <- paths[!file.exists(full)]
  if (length(missing)) {
    return(paste0("'", src, "' is missing saved file(s): ",
                  paste(missing, collapse = ", ")))
  }
  # Symlinks may point anywhere, so compare resolved locations. `dir` is
  # resolved too: a symlinked resource directory is legitimate, but nothing
  # inside it may lead out of it.
  real_dir <- normalizePath(dir, winslash = "/", mustWork = TRUE)
  real <- normalizePath(full, winslash = "/", mustWork = TRUE)
  prefix <- paste0(sub("/+$", "", real_dir), "/")
  inside <- if (.Platform$OS.type == "windows") {
    startsWith(tolower(real), tolower(prefix))
  } else {
    startsWith(real, prefix)
  }
  if (!all(inside)) {
    return(paste0(idx, " lists path(s) that resolve outside the saved directory: ",
                  paste(paths[!inside], collapse = ", ")))
  }
  if (!dir.exists(full[mat_rows])) {
    return(paste0("BPCells matrix '", paths[mat_rows], "' in '", src,
                  "' is not a directory"))
  }
  TRUE
}

# open -------------------------------------------------------------------

open_monocle_cds <- function(descriptor, paths, context) {
  for (pkg in c("monocle3", "BPCells")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("Package '", pkg, "' is required to open Monocle CDS resources but is ",
           "not installed. See the projectData.monocle3 README for installation.",
           call. = FALSE)
    }
  }
  object_name <- descriptor$objects
  if (length(object_name) != 1L || !is_scalar_string(object_name)) {
    stop("Resource '", descriptor$resource, "' must declare exactly one object.",
         call. = FALSE)
  }
  if (!is_scalar_string(paths$source) || !dir.exists(paths$source)) {
    stop("Saved Monocle directory does not exist: ", format(paths$source), call. = FALSE)
  }
  if (!is_scalar_string(paths$work_dir) || !dir.exists(paths$work_dir)) {
    stop("projectData did not provide an existing work directory.", call. = FALSE)
  }

  # monocle3 creates uniquely named `monocle.bpcells.*.tmp` children inside
  # matrix_path, so the unique work_dir can be passed as is.
  matrix_control <- monocle3::set_matrix_control(list(
    matrix_class = "BPCells",
    matrix_mode = "dir",
    matrix_path = normalizePath(paths$work_dir, winslash = "/", mustWork = TRUE)
  ))

  # load_monocle_objects() calls SummarizedExperiment generics unqualified, so
  # monocle3 must be on the search path for the duration of the call.
  cds <- with_attached("monocle3", {
    suppressMessages(monocle3::load_monocle_objects(
      directory_path = paths$source,
      matrix_control = matrix_control
    ))
  })

  if (!methods::is(cds, "cell_data_set") || !methods::validObject(cds, test = TRUE) %in% TRUE) {
    stop("'", paths$source, "' did not restore to a valid monocle3 cell_data_set.",
         call. = FALSE)
  }
  stats::setNames(list(cds), object_name)
}
