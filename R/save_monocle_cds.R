#' Save a Monocle 3 CDS into a data package source tree
#'
#' `save_monocle_cds()` is a **package-authoring** operation. With one call it
#' turns a `cell_data_set` into everything a data package needs to ship it as a
#' disk-backed resource that [projectData::data_attach()] opens through this
#' package's loader:
#'
#' ```
#' my.datapkg/
#' ├── data/
#' │   └── <name>.rda               placeholder (written here)
#' └── inst/
#'     ├── extdata/
#'     │   └── <name>/              native Monocle 3 serialization (written here)
#'     └── projectData/
#'         └── manifest.dcf         entry for <name> (created or updated here)
#' ```
#'
#' Nothing is written to the working directory, `R/data.R` is never edited, and
#' the caller's `cds` is not modified.
#'
#' @section Serialization:
#' The CDS is written with `monocle3::save_monocle_objects()` using
#' `archive_control = list(archive_type = "none")` (no tar archive), so the
#' directory is installed as is. The counts must be a BPCells on-disk matrix,
#' because that is what the loader restores; `save_monocle_objects()` copies the
#' matrix directory into the saved directory. Everything else, including
#' metadata, reductions, their nearest-neighbour indexes and any in-memory
#' alternative assays, is stored in `cds_object.rds` and the index files that
#' Monocle writes.
#'
#' `save_monocle_objects()` converts nothing by itself, with two exceptions
#' worth knowing: it writes the CDS as HDF5 instead of rds if any assay is
#' HDF5-backed (such a save is rejected here because the loader does not
#' support it), and a CDS with in-memory counts is saved *without* a BPCells
#' directory (rejected here as well, with advice to use
#' `convert_to_bpcells = TRUE`).
#'
#' @section BPCells conversion:
#' With `convert_to_bpcells = FALSE` (the default) no assay is converted and
#' the CDS is saved as it is; counts that are already BPCells-backed pass
#' through unchanged, and in-memory counts are an error raised before anything is
#' written. With `convert_to_bpcells = TRUE` a *separate* copy of the CDS gets
#' its `counts` assay converted with `monocle3::convert_counts_matrix()`
#' (`matrix_class = "BPCells"`, `matrix_mode = "dir"`), writing the intermediate
#' matrix to a temporary directory of the session (never the working
#' directory), which is removed once the CDS is saved. Only `counts` is
#' converted; other assays are left alone. Cell and feature names must be
#' unchanged by the conversion, which is checked.
#'
#' @section Alternative assays:
#' Assays other than `counts` (and the derived `counts_row_order`, which
#' Monocle regenerates when loading) are not deliberately removed or converted.
#' In-memory alternative assays are stored in `cds_object.rds` and have been
#' verified to survive a save and a load through the adapter. An alternative
#' assay that is itself a BPCells matrix is **not** supported: Monocle saves
#' only a reference to its original directory, which will not exist for the
#' people using the package. A warning of class
#' `projectData.monocle3_external_assay` is raised and the data package is
#' written regardless; what a loaded copy contains for such assays is unverified.
#' Other representations (for example `DelayedArray` assays) were not tested.
#'
#' @section Overwriting and failure:
#' Before anything is written, the CDS, `name`, `package_dir`, installed
#' dependencies, existing targets and the existing manifest are checked. Existing
#' targets are replaced only with `overwrite = TRUE`; and then only a directory
#' that is a saved Monocle directory (or empty) and a placeholder written by
#' this package (or the historical `"This is a placeholder object."`). A
#' `data/<name>.rda` that holds anything else is never replaced. A name already
#' used by a manifest entry of another loader, or declared as an object by
#' another resource, is an error.
#'
#' The new files are first created in a hidden staging directory in the package
#' root (`.projectData.monocle3-stage-*`), where the saved directory is
#' validated with the loader's own checks and the placeholder is read back.
#' Only then are the previous files moved aside, the new ones renamed into place
#' and the manifest written (atomically, by `projectData::data_manifest_write()`).
#' If any of those steps fails, the new files are removed and the old ones are
#' moved back. The staging directory is removed afterwards. This is **not** a
#' filesystem transaction: renames are individually atomic, but a crash of the R
#' process (or a failing rollback) can leave the staging directory behind, and
#' the error then names where the previous files are. Saving itself can take a
#' while for a large matrix; an interruption during that phase touches only the
#' staging directory.
#'
#' `file_index.rds`, written by Monocle, records the staging directory as the
#' save location. The loader does not use it.
#'
#' @section Documentation:
#' Document the dataset with the usual roxygen2 convention in `R/data.R`, a
#' block followed by the quoted name, for example `"cds_main_adults"`. This
#' function does not edit `R/data.R`; it only tells you when no such topic is
#' found.
#'
#' @section Using the saved data:
#' After installing the package, `data("<name>", package = "<pkg>")` only loads
#' the placeholder, which prints instructions. The actual CDS is obtained with
#' `projectData::data_attach("<pkg>")` followed by `<name>`.
#'
#' @param cds A Monocle 3 `cell_data_set`.
#' @param name A single, syntactically valid R object name. It names the saved
#'   directory, the placeholder, the manifest resource and the object that
#'   [projectData::data_attach()] provides.
#' @param package_dir Root of an existing R package *source* directory.
#' @param convert_to_bpcells Convert the counts to an on-disk BPCells matrix
#'   before saving? Only `counts` is converted. See the section on conversion.
#' @param overwrite Replace an existing saved dataset and its placeholder?
#' @return Invisibly, a list with the `name`, `package`, the paths of the saved
#'   `directory`, `placeholder` and `manifest`, `manifest_status` (`"added"`,
#'   `"updated"` or `"unchanged"`) and whether existing files were `replaced`.
#' @examples
#' \dontrun{
#' # In a data package source directory:
#' projectData.monocle3::save_monocle_cds(cds_main_adults, "cds_main_adults")
#'
#' # Then document it in R/data.R, run devtools::document(), install, and:
#' projectData::data_attach("myDataPackage")
#' cds_main_adults
#' }
#' @seealso [write_monocle_manifest()] to register directories saved by other
#'   means, [projectData_loaders()]
#' @export
save_monocle_cds <- function(cds, name, package_dir = ".", convert_to_bpcells = FALSE,
                             overwrite = FALSE) {
  call <- sys.call()
  fail <- function(..., class = NULL) {
    stop(structure(
      class = c(class, "projectData.monocle3_save_error", "error", "condition"),
      list(message = paste0(...), call = call)
    ))
  }

  # 1. Validate everything before writing anything ----------------------
  for (pkg in c("monocle3", "BPCells", "SummarizedExperiment")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      fail("Package '", pkg, "' is required to save a Monocle CDS but is not installed.")
    }
  }
  if (!methods::is(cds, "cell_data_set") || !isTRUE(methods::validObject(cds, test = TRUE))) {
    fail("`cds` must be a valid monocle3 `cell_data_set`.")
  }
  if (!is_scalar_string(name) || !identical(make.names(name), name) || startsWith(name, ".")) {
    fail("`name` must be a single syntactically valid R object name that does not ",
         "start with a dot; got ", encodeString(format(name)[1L], quote = "'"), ".")
  }
  for (arg in c("convert_to_bpcells", "overwrite")) {
    value <- get(arg)
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
      fail("`", arg, "` must be TRUE or FALSE.")
    }
  }
  root <- check_package_source(package_dir, call = call)
  package <- unname(read.dcf(file.path(root, "DESCRIPTION"), fields = "Package")[1L, 1L])

  target <- check_save_targets(root, name, overwrite, fail)

  counts_on_disk <- methods::is(
    SummarizedExperiment::assay(cds, "counts", withDimnames = FALSE), "IterableMatrix"
  )
  if (!convert_to_bpcells && !counts_on_disk) {
    fail("The counts of `cds` are an in-memory matrix, and the loader needs ",
         "BPCells-backed counts. Use `convert_to_bpcells = TRUE`, or convert them ",
         "yourself with monocle3::convert_counts_matrix().")
  }

  manifest <- file.path(root, "inst", "projectData", "manifest.dcf")
  loader_id <- projectData_loaders()$id
  plan <- with_loader_registered({
    existing <- read_existing_manifest(manifest, root)
    found <- data.frame(resource = name, status = "discovered", reason = NA_character_,
                        source = paste0("extdata/", name), path = NA_character_,
                        placeholder = NA_character_, stringsAsFactors = FALSE)
    plan_manifest(existing, found, loader_id)
  })
  if (identical(plan$report$status, "conflict")) {
    fail("Cannot register '", name, "' in the manifest: ", plan$report$detail,
         ". Nothing was written.", class = "projectData.monocle3_conflict")
  }

  external <- external_assays(cds)
  if (length(external)) {
    warning(structure(
      class = c("projectData.monocle3_external_assay", "warning", "condition"),
      list(message = paste0(
        "Alternative assay(s) ", paste0("'", external, "'", collapse = ", "),
        " are on-disk BPCells matrices. Monocle saves only a reference to their ",
        "original directory, so they will not work in the installed package."),
        call = call)
    ))
  }

  # 2. Stage, verify, then commit ---------------------------------------
  stage <- tempfile(".projectData.monocle3-stage-", tmpdir = root)
  keep_stage <- FALSE
  convert_dir <- NULL
  on.exit({
    if (!is.null(convert_dir)) unlink(convert_dir, recursive = TRUE)
    if (!keep_stage) unlink(stage, recursive = TRUE)
  }, add = TRUE)
  dir.create(file.path(stage, "inst", "extdata"), recursive = TRUE)
  dir.create(file.path(stage, "data"))
  dir.create(file.path(stage, "backup"))

  to_save <- cds
  if (convert_to_bpcells) {
    converted <- convert_counts_to_bpcells(cds, fail)
    to_save <- converted$cds
    convert_dir <- converted$dir
  }

  staged_cds <- file.path(stage, "inst", "extdata", name)
  save_staged_cds(to_save, staged_cds)

  verdict <- validate_monocle_cds(
    list(source = paste0("extdata/", name), objects = name), file.path(stage, "inst"), list()
  )
  if (!isTRUE(verdict)) {
    fail("The saved CDS does not meet the loader's requirements, so nothing was ",
         "written: ", verdict)
  }

  staged_placeholder <- file.path(stage, "data", paste0(name, ".rda"))
  write_placeholder(staged_placeholder, name, package)
  info <- inspect_rda(staged_placeholder)
  if (!isTRUE(info$readable) || !is_recognized_placeholder(info, name)) {
    fail("Internal error: the generated placeholder is not recognized; nothing was written.")
  }

  outcome <- commit_staged_resource(
    root = root, stage = stage, name = name, plan = plan, manifest = manifest,
    staged_cds = staged_cds, staged_placeholder = staged_placeholder,
    old_cds = target$cds, old_placeholders = target$placeholders
  )
  if (!is.null(outcome$error)) {
    keep_stage <- !isTRUE(outcome$restored)
    fail("Saving '", name, "' failed while writing to the package: ",
         conditionMessage(outcome$error), "\n",
         if (outcome$restored) {
           "The previous files were restored."
         } else {
           paste0("Restoring the previous files also failed; they are kept in '",
                  file.path(stage, "backup"), "'.")
         })
  }

  report_save(root, name, package, outcome$manifest_status, target$replaced)
  invisible(list(
    name = name,
    package = package,
    directory = file.path(root, "inst", "extdata", name),
    placeholder = file.path(root, "data", paste0(name, ".rda")),
    manifest = manifest,
    manifest_status = outcome$manifest_status,
    replaced = target$replaced
  ))
}

# Looks at what already exists for `name`; refuses anything that may not be
# replaced, and anything at all when `overwrite` is FALSE.
check_save_targets <- function(root, name, overwrite, fail) {
  dest <- file.path(root, "inst", "extdata", name)
  has_cds <- file.exists(dest)
  if (has_cds) {
    empty_dir <- dir.exists(dest) && !length(list.files(dest, all.files = TRUE, no.. = TRUE))
    if (!dir.exists(dest) || !(empty_dir || looks_like_monocle_save(dest))) {
      fail("'inst/extdata/", name, "' exists but is not a saved Monocle directory, ",
           "so it will not be replaced.")
    }
  }
  candidates <- file.path(root, "data", paste0(name, ".", rda_extensions))
  candidates <- candidates[file.exists(candidates)]
  for (path in candidates) {
    info <- inspect_rda(path)
    ok <- isTRUE(info$readable) && identical(info$names, name) && isTRUE(info$single) &&
      is_recognized_placeholder(info, name)
    if (!ok) {
      fail("'data/", basename(path), "' does not hold a CDS placeholder (it may be a ",
           "real dataset), so it will not be replaced.")
    }
  }
  if ((has_cds || length(candidates)) && !overwrite) {
    found <- c(if (has_cds) paste0("inst/extdata/", name),
               if (length(candidates)) paste0("data/", basename(candidates)))
    fail("'", name, "' already exists in this package (", paste(found, collapse = ", "),
         "). Use `overwrite = TRUE` to replace it.")
  }
  list(cds = if (has_cds) dest, placeholders = candidates,
       replaced = has_cds || length(candidates) > 0L)
}

# Assays other than counts (and the derived counts_row_order) that Monocle
# would store only by reference.
external_assays <- function(cds) {
  others <- setdiff(SummarizedExperiment::assayNames(cds), c("counts", "counts_row_order"))
  others[vapply(others, function(a) {
    methods::is(SummarizedExperiment::assay(cds, a, withDimnames = FALSE), "IterableMatrix")
  }, NA)]
}

# Converts the counts of a separate copy using monocle3's own conversion. The
# intermediate matrix goes to a directory of the session temporary directory,
# not the default (the working directory).
convert_counts_to_bpcells <- function(cds, fail) {
  dir <- tempfile("projectData.monocle3-convert-")
  dir.create(dir)
  converted <- tryCatch(
    with_attached("monocle3", suppressMessages(monocle3::convert_counts_matrix(
      cds, matrix_control = list(matrix_class = "BPCells", matrix_mode = "dir",
                                 matrix_path = dir)
    ))),
    error = function(e) {
      unlink(dir, recursive = TRUE)
      fail("Converting the counts to BPCells failed: ", conditionMessage(e))
    }
  )
  before <- SummarizedExperiment::assay(cds, "counts")
  after <- SummarizedExperiment::assay(converted, "counts")
  same <- identical(dim(before), dim(after)) &&
    identical(dimnames(before), dimnames(after)) &&
    identical(colnames(cds), colnames(converted)) &&
    identical(rownames(cds), rownames(converted))
  if (!same) {
    unlink(dir, recursive = TRUE)
    fail("Converting the counts to BPCells changed the dimensions or the cell and ",
         "feature names; nothing was written.")
  }
  list(cds = converted, dir = dir)
}

# Separate function so that tests can make the save step fail.
save_staged_cds <- function(cds, directory) {
  with_attached("monocle3", {
    suppressMessages(utils::capture.output(
      monocle3::save_monocle_objects(
        cds, directory_path = directory, verbose = FALSE,
        archive_control = list(archive_type = "none")
      )
    ))
  })
  invisible(directory)
}

# Moves the staged files into the package, keeping the previous ones aside
# until the manifest is written. Returns `error = NULL` on success; otherwise
# the error, and whether the previous state was restored.
commit_staged_resource <- function(root, stage, name, plan, manifest, staged_cds,
                                   staged_placeholder, old_cds, old_placeholders) {
  dest_cds <- file.path(root, "inst", "extdata", name)
  dest_placeholder <- file.path(root, "data", paste0(name, ".rda"))
  moved <- list()
  placed <- character()
  made_dirs <- character()

  ensure_dir <- function(dir) {
    missing <- character()
    while (!dir.exists(dir) && nchar(dir) > nchar(root)) {
      missing <- c(dir, missing)
      dir <- dirname(dir)
    }
    if (length(missing)) {
      dir.create(missing[length(missing)], recursive = TRUE)
      made_dirs <<- c(made_dirs, missing)
    }
  }
  move <- function(from, to) {
    if (!isTRUE(file.rename(from, to))) {
      stop("could not move '", from, "' to '", to, "'", call. = FALSE)
    }
  }
  restore <- function() {
    for (path in rev(placed)) unlink(path, recursive = TRUE)
    ok <- TRUE
    for (m in rev(moved)) ok <- isTRUE(file.rename(m$to, m$from)) && ok
    for (dir in rev(made_dirs)) {
      if (dir.exists(dir) && !length(list.files(dir, all.files = TRUE, no.. = TRUE))) {
        unlink(dir, recursive = TRUE)
      }
    }
    ok
  }

  status <- tryCatch({
    ensure_dir(dirname(dest_cds))
    ensure_dir(dirname(dest_placeholder))
    ensure_dir(dirname(manifest))
    for (path in c(old_cds, old_placeholders)) {
      backup <- file.path(stage, "backup", paste0(length(moved) + 1L, "_", basename(path)))
      move(path, backup)
      moved[[length(moved) + 1L]] <- list(from = path, to = backup)
    }
    move(staged_cds, dest_cds)
    placed <- c(placed, dest_cds)
    move(staged_placeholder, dest_placeholder)
    placed <- c(placed, dest_placeholder)
    with_loader_registered(write_planned_manifest(plan, manifest, root))
    plan$report$status
  }, error = function(e) e)

  if (inherits(status, "error")) {
    return(list(error = status, restored = restore()))
  }
  list(error = NULL, manifest_status = status)
}

report_save <- function(root, name, package, manifest_status, replaced) {
  message(
    if (replaced) "Replaced" else "Saved", " Monocle CDS '", name, "':\n",
    "  inst/extdata/", name, "/\n",
    "  data/", name, ".rda (placeholder)\n",
    "  inst/projectData/manifest.dcf (", manifest_status, ")"
  )
  r_files <- list.files(file.path(root, "R"), pattern = "\\.[Rr]$", full.names = TRUE)
  documented <- any(vapply(r_files, function(f) {
    any(grepl(paste0("^\\s*[\"'`]", name, "[\"'`]\\s*$"), readLines(f, warn = FALSE)))
  }, NA))
  if (!documented) {
    message("No documentation topic for '", name, "' found in R/. Add a roxygen2 block ",
            "ending in \"", name, "\" (usually in R/data.R) and run devtools::document().")
  }
  invisible()
}
