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
#' @section Filesystem safety:
#' monocle3 and BPCells copy the matrix directory by following whatever is
#' inside it, so the loader refuses a resource before the native load when
#' anything inside the saved directory is a symbolic link (internal, escaping or
#' dangling), when an indexed path is absolute, uses `..`, or is of the wrong
#' type, or when the BPCells directory is not flat or lacks the files BPCells
#' writes. The directory itself, and the library it lives in, may be reached
#' through symbolic links. The same check runs in `validate` and again in `open`
#' (a listing of about ten entries; no matrix data is read), and `open` refuses a
#' work directory that lies inside the installed resource. Resources written by
#' [save_monocle_cds()] never contain links.
#'
#' @section What the restored object references:
#' Monocle copies the BPCells matrix directory (and a second, row-ordered copy
#' it derives) into uniquely named subdirectories of `paths$work_dir`, so the
#' counts do not depend on the installed package. The work directory lives in
#' the session temporary directory and is removed by monocle3 when R exits.
#' The UMAP nearest-neighbour index, however, is memory-mapped by Annoy
#' directly from the installed file. On Linux and macOS the mapping survives
#' deletion of the file; on Windows an installed copy cannot be removed while
#' it is mapped. See `vignette("storage")` for details.
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

# Returns TRUE or a single message. Lists the resource tree (a handful of
# entries) and reads only the small file_index.rds; never matrix data.
validate_monocle_cds <- function(descriptor, root, context) {
  src <- descriptor$source
  if (!is_scalar_string(src)) {
    return("a Monocle CDS resource needs a `Source` directory")
  }
  if (!is_plain_relative(src)) {
    return(paste0("`Source` must be a relative path inside the package: '", src, "'"))
  }
  objs <- descriptor$objects
  if (length(objs) != 1L || !is_scalar_string(objs)) {
    return(paste0("a Monocle CDS resource must declare exactly one object in ",
                  "`Objects`; got ", length(objs)))
  }
  check_saved_directory(file.path(root, src), src)
}

# The checks shared by validate (at registration time) and open (just before
# the native load), so the two cannot drift. `dir` itself may be reached through
# symbolic links (a symlinked library); nothing inside it may be one.
check_saved_directory <- function(dir, src) {
  if (!dir.exists(dir)) {
    return(paste0("saved Monocle directory '", src, "' does not exist"))
  }
  # Before anything inside is read: a linked file_index.rds could lead anywhere.
  tree <- saved_tree_problems(dir)
  if (length(tree)) {
    return(paste0("'", src, "' is not a safe saved Monocle directory (", paste(tree, collapse = "; "),
                  "). Symbolic links inside a resource are never followed; the installed ",
                  "data package looks damaged or altered: reinstall it"))
  }
  index_path <- file.path(dir, "file_index.rds")
  if (!file.exists(index_path) || dir.exists(index_path)) {
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
  problem <- file_index_listing_problem(index, src)
  if (!is.null(problem)) {
    return(problem)
  }
  files <- index$files
  paths <- files$file_path
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
  validate_saved_files(files, dir, src, mat_rows)
}

# The part of the index check that concerns the index alone: a native Monocle
# index with a well-formed, contained, duplicate-free file listing. No file
# system access and no judgement of what the loader supports. Returns NULL or a
# message. Also used to recognize a native save when deciding ownership.
file_index_listing_problem <- function(index, src) {
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
  if (!all(is_plain_relative(paths))) {
    return(paste0(idx, " lists paths that are not relative to the saved directory"))
  }
  if (anyDuplicated(paths)) {
    return(paste0(idx, " lists the same file path more than once"))
  }
  NULL
}

# Checks the saved files against the (already well-formed) listing. The tree
# was already found free of links, so resolved locations equal lexical ones; the
# containment test stays as an independent guard on the listed paths.
validate_saved_files <- function(files, dir, src, mat_rows) {
  idx <- paste0("'", src, "/file_index.rds'")
  paths <- files$file_path
  full <- file.path(dir, paths)
  missing <- paths[!file.exists(full)]
  if (length(missing)) {
    return(paste0("'", src, "' is missing saved file(s): ",
                  paste(missing, collapse = ", ")))
  }
  if (!all(is_inside(full, dir))) {
    return(paste0(idx, " lists path(s) that resolve outside the saved directory: ",
                  paste(paths[!is_inside(full, dir)], collapse = ", ")))
  }
  is_dir <- dir.exists(full)
  if (!is_dir[mat_rows]) {
    return(paste0("BPCells matrix '", paths[mat_rows], "' in '", src,
                  "' is not a directory"))
  }
  if (any(is_dir[!mat_rows])) {
    return(paste0(idx, " lists a directory where a file is expected: ",
                  paste(paths[is_dir & !mat_rows], collapse = ", ")))
  }
  matrix_problems <- backing_dir_problems(full[mat_rows])
  if (length(matrix_problems)) {
    return(paste0("BPCells matrix '", paths[mat_rows], "' in '", src,
                  "' is not usable: ", paste(matrix_problems, collapse = "; ")))
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
  # Native loading copies the BPCells directory into the work directory; that
  # must never be (inside) the installed resource, which is read only.
  work_dir <- normalizePath(paths$work_dir, winslash = "/", mustWork = TRUE)
  source_dir <- normalizePath(paths$source, winslash = "/", mustWork = TRUE)
  if (identical(work_dir, source_dir) || is_inside(work_dir, source_dir)) {
    stop("The work directory provided for '", descriptor$resource,
         "' lies inside the installed resource; refusing to write there.", call. = FALSE)
  }
  # The same checks as validate, repeated at the point of use.
  problem <- check_saved_directory(paths$source, descriptor$source %||% basename(paths$source))
  if (!isTRUE(problem)) {
    stop("Cannot open Monocle resource '", descriptor$resource, "': ", problem, ".",
         call. = FALSE)
  }

  # monocle3 creates uniquely named `monocle.bpcells.*.tmp` children inside
  # matrix_path, so the unique work_dir can be passed as is.
  matrix_control <- monocle3::set_matrix_control(list(
    matrix_class = "BPCells",
    matrix_mode = "dir",
    matrix_path = work_dir
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
