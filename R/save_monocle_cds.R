#' Save a Monocle 3 CDS into a data package source tree
#'
#' `save_monocle_cds()` is a **package-authoring** operation. With one call it
#' turns a `cell_data_set` into everything a data package needs to ship it as a
#' disk-backed resource that [projectData::data_attach()] opens through this
#' package's loader:
#'
#' ```
#' my.datapkg/
#' |-- data/
#' |   `-- <name>.rda               placeholder (written here)
#' `-- inst/
#'     |-- extdata/
#'     |   `-- <name>/              native Monocle 3 serialization (written here)
#'     `-- projectData/
#'         `-- manifest.dcf         entry for <name> (created or updated here)
#' ```
#'
#' Nothing is written to the working directory, `R/data.R` is never edited, and
#' the caller's `cds` is not modified.
#'
#' @section Serialization:
#' The CDS is written with `monocle3::save_monocle_objects()` using
#' `archive_control = list(archive_type = "none")` (no tar archive), so the
#' directory is installed as is. The loader restores BPCells on-disk counts, so
#' the counts of the saved CDS always are such a matrix;
#' `save_monocle_objects()` copies the matrix directory into the saved
#' directory. Everything else, including metadata, reductions, their
#' nearest-neighbour indexes and any in-memory alternative assays and
#' alternative experiments, is stored in `cds_object.rds` and the index files
#' that Monocle writes.
#'
#' @section BPCells conversion:
#' Conversion is automatic; there is nothing to switch on. The `counts` assay is
#' inspected first (with `methods::is()` against BPCells' `IterableMatrix` class
#' and `BPCells::all_matrix_inputs()` to find the matrices underneath):
#'
#' * **Counts that are already an on-disk BPCells matrix** (a `MatrixDir`,
#'   possibly lazily subset or transformed) are *not* converted again. They are
#'   saved as they are.
#' * **In-memory counts** (a `dgCMatrix` or `dgTMatrix`, or a BPCells matrix held
#'   in memory) are converted on a *separate working copy* of the CDS with
#'   `monocle3::convert_counts_matrix()` (`matrix_class = "BPCells"`,
#'   `matrix_mode = "dir"`). The intermediate matrix goes to a temporary
#'   directory of the session (never the working directory) that is removed once
#'   the CDS is saved, and the caller's `cds` is not modified. Cell and feature
#'   names must be unchanged by the conversion, which is checked. Monocle
#'   adds its internal, derived `counts_row_order` assay to the converted copy;
#'   it is a row-oriented copy of the counts, not a separate assay, and is
#'   regenerated whenever the CDS is loaded.
#' * **Any other representation** (for example a dense `matrix`, a
#'   `DelayedMatrix` or an HDF5-backed BPCells matrix) is an error raised before
#'   anything is written, naming the class found.
#'
#' Only `counts` is converted; other assays are left alone. `save_monocle_objects()`
#' itself writes the CDS as HDF5 instead of rds if any assay is HDF5-backed
#' (such a save is rejected here because the loader does not support it).
#'
#' @section Alternative assays:
#' Assays other than `counts` (and the derived `counts_row_order`, which
#' Monocle regenerates when loading) are not deliberately removed or converted.
#' In-memory alternative assays are stored in `cds_object.rds` and have been
#' verified to survive a save and a load through the adapter. An alternative
#' assay that is itself a BPCells matrix is **not** supported: Monocle saves
#' only a reference to its original directory, which will not exist for the
#' people using the package. Saving is therefore **refused** with an error of
#' class `projectData.monocle3_external_assay` (also
#' `projectData.monocle3_save_error`) before anything is written. The error lists
#' every offending assay with its location, such as `assay 'spliced'` or
#' `altExp 'ADT' / altExp 'normalized' / assay 'counts'`. Convert such assays to
#' an in-memory matrix, or remove them, before saving; this function never
#' converts them because that could use a lot of memory.
#'
#' The check is recursive: the assays of every alternative experiment
#' (`SingleCellExperiment::altExp()`), at any depth, are inspected, and unlike
#' at the top level there is no exception for `counts` or `counts_row_order`
#' there. An alternative experiment with in-memory assays is supported. No matrix
#' values are read; BPCells matrices are judged by the classes of the matrices
#' underneath, and only `MatrixMem` (in-memory) ones are accepted; a BPCells wrapper
#' around an R matrix (`Iterable_dgCMatrix_wrapper`) is refused too, as it is not
#' known to be self-contained. `DelayedArray` assays are
#' also refused, because whether they are file-backed is not examined and their
#' serialization is untested. Other exotic representations are not checked and
#' are not guaranteed to work.
#'
#' @section Overwriting and failure:
#' Before anything is written, the CDS, `name`, `package_dir`, installed
#' dependencies, existing targets and the existing manifest are checked. Existing
#' targets are replaced only with `overwrite = TRUE`, and only when this package
#' can show it wrote them. A directory that merely contains files named like a
#' Monocle save (`file_index.rds`, `cds_object.rds`, `bpcells_matrix_dir`) is not
#' thereby owned.
#'
#' An existing `inst/extdata/<name>` is replaceable when at least two of these
#' three independent pieces of evidence are present:
#'
#' * a `file_index.rds` that is a native Monocle index (written by
#'   `save_monocle_objects()`, with a well-formed file listing; the listed files
#'   need not all exist);
#' * a manifest entry for `<name>` with this package's loader, whose `Source` and
#'   `Objects` agree with it;
#' * a recognized placeholder `data/<name>.rda`, written by this package or the
#'   historical `"This is a placeholder object."`.
#'
#' The directory must also hold nothing the evidence does not account for: only
#' `file_index.rds` and the files it lists (or, when the index is unusable,
#' `cds_object.rds` and `bpcells_matrix_dir`). The outcomes:
#'
#' | Existing `inst/extdata/<name>` | Result |
#' |---|---|
#' | none (or only a recognized placeholder) | normal save |
#' | valid or damaged, two or more kinds of evidence | replaced with `overwrite = TRUE`; error of class `projectData.monocle3_exists` (also `projectData.monocle3_damaged` when damaged) without |
#' | native save, or marker files, with less evidence (for example a bare `bpcells_matrix_dir`, a malformed `file_index.rds`, or a save no manifest entry or placeholder claims) | error `projectData.monocle3_ambiguous_ownership`, with or without `overwrite` |
#' | contains other files, or is a file | error `projectData.monocle3_not_owned` |
#' | manifest entry of another loader | error `projectData.monocle3_conflict` |
#' | empty directory | replaced with `overwrite = TRUE` (nothing can be lost) |
#'
#' So a save made with this package whose manifest was deleted, or whose
#' placeholder was removed, can still be replaced, and so can a damaged one (a
#' deleted `cds_object.rds`) as long as two kinds of evidence remain. A manifest
#' entry of this loader that disagrees with the directory is ambiguous. A
#' `data/<name>.rda` that holds anything other than a recognized placeholder is
#' never replaced (`projectData.monocle3_placeholder_not_recognized`). A name
#' already used by a manifest entry of another loader, or declared as an object by
#' another resource, is an error. All of these errors are raised before any file
#' is staged or written, and none of them suggests `overwrite = TRUE` as a remedy
#' when ownership is not established; there is no `force` argument. Replacing a
#' damaged resource reports what was replaced and why it was allowed.
#'
#' @section The manifest:
#' The manifest is reconciled with the package exactly as by
#' [write_monocle_manifest()], after the CDS and its placeholder are in place:
#' the new resource is added or updated, entries of this package whose saved
#' directory or placeholder no longer exist are removed as stale (so deleting
#' a saved directory by hand never blocks the next save), other valid saved
#' resources that are not yet registered are added, and entries of other adapters
#' are kept as they are. Nothing but the manifest entries is deleted; saved
#' directories and placeholders are never removed by reconciliation. If an
#' entry of another adapter is invalid, nothing is saved.
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
#' @section Filesystem safety:
#' monocle3 and BPCells follow symbolic links when they copy a matrix directory
#' and do not check where paths lead, so this function does. Before anything is
#' staged, the directory of each on-disk BPCells matrix under `counts` is
#' listed (no file is read, one flat directory per matrix) and refused, with an
#' error of class `projectData.monocle3_unsafe_backing` (also
#' `projectData.monocle3_save_error`), if it is missing, holds a nested
#' directory, lacks the files BPCells writes (`version`, `storage_order`,
#' `shape`, `row_names`, `col_names`, `idxptr` and `val` or `val_data`), or
#' contains a symbolic link of any kind (internal, escaping or dangling): a link
#' would put the bytes of some other file into your package. The directory
#' itself may be reached through links, and so may the package directory and
#' parents such as `inst/extdata`. An existing `inst/extdata/<name>` that is a
#' link, or contains one, is never replaced (`projectData.monocle3_not_owned`),
#' and a dangling link where a placeholder would go is refused too. The staging
#' directory is created fresh (never through an existing path), is checked to lie
#' inside the package, and is removed without following links. The saved tree is
#' validated with the loader's own checks before anything is moved into the
#' package. Entry types are judged with base R, which cannot distinguish a FIFO or
#' device file from a regular file; those are not detected.
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
#' @param overwrite Replace an existing saved dataset and its placeholder?
#' @return Invisibly, a list with the `name`, `package`, the paths of the saved
#'   `directory`, `placeholder` and `manifest`, `manifest_status` (`"added"`,
#'   `"updated"` or `"unchanged"`), whether existing files were `replaced`, and
#'   the names of any `removed_stale` manifest entries.
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
save_monocle_cds <- function(cds, name, package_dir = ".", overwrite = FALSE) {
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
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
    fail("`overwrite` must be TRUE or FALSE.")
  }
  root <- check_package_source(package_dir, call = call)
  package <- unname(read.dcf(file.path(root, "DESCRIPTION"), fields = "Package")[1L, 1L])

  # Read before the targets are judged: ownership of an existing directory
  # depends on what the manifest says about it. Same reader, same errors, as the
  # reconciliation below.
  manifest <- manifest_path(root)
  existing <- read_existing_manifest(manifest)
  target <- check_save_targets(root, name, overwrite, fail, existing)

  representation <- counts_representation(cds)
  if (identical(representation$kind, "unsupported")) {
    fail("The counts of `cds` cannot be saved: ", representation$reason, " ",
         "Counts that are already an on-disk BPCells matrix are saved as they are, and ",
         "in-memory sparse counts (dgCMatrix or dgTMatrix) are converted automatically; ",
         "convert these counts to one of those first. Nothing was written.")
  }

  # What the package will contain once this resource is in place.
  found <- discover_monocle_resources(root)
  found <- rbind(found[found$resource != name, , drop = FALSE], data.frame(
    resource = name, status = "discovered", reason = NA_character_,
    source = paste0("extdata/", name), path = NA_character_,
    placeholder = NA_character_, stringsAsFactors = FALSE
  ))
  plan <- reconcile_manifest(root, manifest, found, write = FALSE)$plan
  own <- plan$report[plan$report$resource == name & plan$report$status == "conflict", ,
                     drop = FALSE]
  if (nrow(own)) {
    fail("Cannot register '", name, "' in the manifest: ", own$detail,
         ". Nothing was written.", class = "projectData.monocle3_conflict")
  }
  tryCatch(
    with_loader_registered(check_unrelated_entries(plan, root)),
    projectData.monocle3_manifest_error = function(e) {
      fail(conditionMessage(e), class = "projectData.monocle3_manifest_error")
    }
  )

  external <- external_assays(cds)
  if (nrow(external)) {
    fail(external_assay_message(name, external), class = "projectData.monocle3_external_assay")
  }

  # The author's own BPCells directory is copied by BPCells, which follows
  # links; it is judged here, before anything is staged. (In-memory counts have
  # no such directory yet; the converted copy is judged below.)
  if (identical(representation$kind, "bpcells_dir")) {
    check_counts_backing(cds, name, fail)
  }

  # 2. Stage, verify, then commit ---------------------------------------
  stage <- tempfile(".projectData.monocle3-stage-", tmpdir = root)
  stage_created <- FALSE
  keep_stage <- FALSE
  convert_dir <- NULL
  on.exit({
    if (!is.null(convert_dir)) unlink(convert_dir, recursive = TRUE)
    # Only a directory this call created, and never through a link.
    if (!keep_stage && stage_created) remove_tree(stage, within = root)
  }, add = TRUE)
  stage_created <- make_new_dir(stage)
  if (!stage_created || !is_inside(stage, root) ||
      !all(vapply(file.path(stage, c("inst/extdata", "data", "backup")), make_new_dir,
                  NA, recursive = TRUE))) {
    fail("Could not create a staging directory under '", root, "'; nothing was written. ",
         "Check that the package directory is writable.")
  }

  to_save <- cds
  if (identical(representation$kind, "convertible")) {
    converted <- convert_counts_to_bpcells(cds, fail)
    to_save <- converted$cds
    convert_dir <- converted$dir
    check_counts_backing(to_save, name, fail)
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
    root = root, stage = stage, name = name, manifest = manifest,
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

  report_manifest_changes(outcome$plan, outcome$written, warn = FALSE, except = name)
  if (identical(target$state, "damaged")) {
    message("The previous '", name, "' was damaged (", target$reason, "); it was replaced. ",
            "Ownership was established by: ", paste(target$evidence, collapse = ", "), ".")
  }
  report_save(root, name, package, outcome$manifest_status, target$replaced)
  invisible(list(
    name = name,
    package = package,
    directory = file.path(root, "inst", "extdata", name),
    placeholder = file.path(root, "data", paste0(name, ".rda")),
    manifest = manifest,
    manifest_status = outcome$manifest_status,
    replaced = target$replaced,
    removed_stale = outcome$plan$report$resource[outcome$plan$report$status == "removed"]
  ))
}

# Looks at what already exists for `name`; refuses anything that may not be
# replaced (see resource_ownership() for who may be replaced), and anything at
# all when `overwrite` is FALSE. Runs before anything is staged or written.
# `existing` is the manifest as read by read_existing_manifest().
check_save_targets <- function(root, name, overwrite, fail, existing = list()) {
  dest <- file.path(root, "inst", "extdata", name)
  # A dangling link is something that exists: renaming over it would silently
  # discard it, so it is judged (and refused) like any other target.
  exists <- function(p) file.exists(p) | is_symlink(p)
  has_cds <- exists(dest)
  candidates <- file.path(root, "data", paste0(name, ".", rda_extensions))
  candidates <- candidates[exists(candidates)]
  for (path in candidates) {
    info <- inspect_rda(path)
    ok <- isTRUE(info$readable) && identical(info$names, name) && isTRUE(info$single) &&
      is_recognized_placeholder(info, name)
    if (!ok) {
      fail("'data/", basename(path), "' does not hold a CDS placeholder written by this ",
           "package (it may be a real dataset), so it will not be replaced. Nothing was ",
           "written. Choose another `name`, or move that file yourself if it is no ",
           "longer needed.", class = "projectData.monocle3_placeholder_not_recognized")
    }
  }
  verdict <- list(state = "none", reason = NA_character_, evidence = character())
  if (has_cds) {
    verdict <- resource_ownership(root, name, existing, has_placeholder = length(candidates) > 0L)
    if (!verdict$owned) {
      fail(ownership_message(name, verdict), class = verdict$class)
    }
  }
  if ((has_cds || length(candidates)) && !overwrite) {
    found <- c(if (has_cds) paste0("inst/extdata/", name),
               if (length(candidates)) paste0("data/", basename(candidates)))
    damaged <- identical(verdict$state, "damaged")
    fail("'", name, "' already exists in this package (", paste(found, collapse = ", "), ")",
         if (damaged) paste0(" and is damaged (", verdict$reason, "), but this package can ",
                             "show it wrote it (", paste(verdict$evidence, collapse = ", "), ")"),
         ". Use `overwrite = TRUE` to replace it.",
         class = c(if (damaged) "projectData.monocle3_damaged", "projectData.monocle3_exists"))
  }
  list(cds = if (has_cds) dest, placeholders = candidates,
       replaced = has_cds || length(candidates) > 0L,
       state = verdict$state, reason = verdict$reason, evidence = verdict$evidence)
}

# Deliberately does not suggest `overwrite = TRUE`: ownership is not established.
ownership_message <- function(name, verdict) {
  paste0(
    "'inst/extdata/", name, "' exists but this package cannot show that it wrote it (",
    verdict$reason, "), so it will not be replaced, with or without `overwrite`. Nothing ",
    "was written. Choose another `name`, or move or delete that directory yourself if it ",
    "is not needed: this package never deletes what it cannot show it wrote."
  )
}

# Finds assays whose matrix lives outside the object and that Monocle's
# serialization would store only by reference, so a data package would ship a
# dangling path. Returns a data frame with one row per offending assay and a
# human-readable `location`, e.g. "altExp 'ADT' / altExp 'norm' / assay 'counts'".
#
# At the top level, `counts` (validated by counts_representation()) and the
# derived `counts_row_order` are exempt. Nested assays have no exemption, and
# no values are read: only the class of each assay and, for BPCells matrices,
# the classes of the matrices underneath are inspected.
external_assays <- function(cds) {
  found <- list()
  walk <- function(x, path, top) {
    for (a in SummarizedExperiment::assayNames(x)) {
      if (top && a %in% c("counts", "counts_row_order")) next
      m <- SummarizedExperiment::assay(x, a, withDimnames = FALSE)
      kind <- disk_backing(m)
      if (!is.na(kind)) {
        found[[length(found) + 1L]] <<- data.frame(
          location = paste(c(path, paste0("assay '", a, "'")), collapse = " / "),
          assay = a, class = class(m)[1L], backing = kind, stringsAsFactors = FALSE
        )
      }
    }
    if (methods::is(x, "SingleCellExperiment")) {
      alts <- SingleCellExperiment::altExps(x, withDimnames = FALSE)
      for (nm in names(alts)) {
        walk(alts[[nm]], c(path, paste0("altExp '", nm, "'")), FALSE)
      }
    }
  }
  walk(cds, character(), TRUE)
  if (!length(found)) {
    return(data.frame(location = character(), assay = character(), class = character(),
                      backing = character(), stringsAsFactors = FALSE))
  }
  do.call(rbind, found)
}

# NA for matrices held in memory; otherwise a short description of the
# external storage. BPCells operation chains are judged by their leaves, not by
# their (varying) outer class: only in-memory leaves are acceptable.
disk_backing <- function(m) {
  if (methods::is(m, "IterableMatrix")) {
    leaves <- vapply(BPCells::all_matrix_inputs(m), function(l) class(l)[1L], "")
    disk <- leaves[!grepl("MatrixMem", leaves)]
    return(if (length(disk)) paste0("BPCells ", paste(unique(disk), collapse = ", ")) else NA_character_)
  }
  if (methods::is(m, "DelayedArray")) {
    # Delayed operations may sit on in-memory or file-backed seeds; both are
    # treated as external because Monocle's handling of them is untested.
    return("DelayedArray")
  }
  NA_character_
}

external_assay_message <- function(name, external) {
  paste0(
    "Cannot save CDS '", name, "':\n\n",
    "The following assay(s) are disk-backed (or are BPCells/delayed representations not ",
    "known to be in memory) and may reference external files that are not preserved by ",
    "Monocle's native serialization, so the saved data package would not be portable:\n",
    paste0("  - ", external$location, " (", external$class, ": ", external$backing, ")",
           collapse = "\n"),
    "\n\nOnly Monocle-managed BPCells counts of the main CDS are currently supported as ",
    "disk-backed storage. Convert each of these assays to an in-memory representation ",
    "before saving, or remove it if appropriate. Nothing was written."
  )
}

# The directories of the on-disk BPCells matrices underneath the counts of
# `cds`, without reading any values. Lazily subset or transformed counts can
# rest on several.
counts_backing_dirs <- function(cds) {
  counts <- SummarizedExperiment::assay(cds, "counts", withDimnames = FALSE)
  leaves <- BPCells::all_matrix_inputs(counts)
  dirs <- unlist(lapply(leaves, function(l) if (methods::is(l, "MatrixDir")) l@dir))
  unique(as.character(dirs))
}

# Refuses, before anything is written, a counts directory that cannot be copied
# safely: missing, holding links (they would be followed and the target's bytes
# embedded), nested directories, or lacking the files BPCells writes. The
# directory itself may be reached through links. Cost: a listing of one flat
# directory per matrix; no file is read.
check_counts_backing <- function(cds, name, fail) {
  for (dir in counts_backing_dirs(cds)) {
    problems <- backing_dir_problems(dir)
    if (length(problems)) {
      fail("Cannot save CDS '", name, "': its BPCells counts directory '", dir,
           "' cannot be copied safely:\n", paste0("  - ", problems, collapse = "\n"),
           "\nBPCells follows symbolic links when it copies, which would put files from ",
           "elsewhere into the data package. Replace links by real files, or write the ",
           "matrix again with BPCells::write_matrix_dir(). Nothing was written.",
           class = "projectData.monocle3_unsafe_backing")
    }
  }
  invisible()
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
  if (!identical(counts_representation(converted)$kind, "bpcells_dir")) {
    unlink(dir, recursive = TRUE)
    fail("Converting the counts to BPCells did not produce an on-disk matrix; ",
         "nothing was written.")
  }
  list(cds = converted, dir = dir)
}

# Classifies the counts of a CDS without reading any values:
#   bpcells_dir  already an on-disk BPCells matrix (every underlying matrix is a
#                MatrixDir); saved as it is
#   convertible  in memory, and monocle3::convert_counts_matrix() can move it to disk
#   unsupported  anything else; `reason` names the class found
counts_representation <- function(cds) {
  if (!"counts" %in% SummarizedExperiment::assayNames(cds)) {
    return(list(kind = "unsupported", reason = "`cds` has no `counts` assay."))
  }
  counts <- SummarizedExperiment::assay(cds, "counts", withDimnames = FALSE)
  cls <- class(counts)[1L]
  if (methods::is(counts, "IterableMatrix")) {
    leaves <- vapply(BPCells::all_matrix_inputs(counts), function(m) class(m)[1L], "")
    if (all(leaves == "MatrixDir")) {
      return(list(kind = "bpcells_dir", class = cls))
    }
    if (all(leaves == "MatrixDir" | grepl("MatrixMem", leaves))) {
      return(list(kind = "convertible", class = cls))
    }
    return(list(kind = "unsupported", reason = paste0(
      "they are a BPCells matrix of class '", cls, "' built on ",
      paste0("'", unique(leaves), "'", collapse = ", "),
      ", which monocle3 cannot convert to an on-disk directory.")))
  }
  if (methods::is(counts, "dgCMatrix") || methods::is(counts, "dgTMatrix")) {
    return(list(kind = "convertible", class = cls))
  }
  list(kind = "unsupported", reason = paste0(
    "they are a '", cls, "' matrix, which monocle3::convert_counts_matrix() does not ",
    "convert to BPCells."))
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
commit_staged_resource <- function(root, stage, name, manifest, staged_cds,
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
    if (!isTRUE(move_path(from, to))) {
      stop("could not move '", from, "' to '", to, "'", call. = FALSE)
    }
  }
  restore <- function() {
    # Placed paths are directories and files this call created (the staged tree
    # is link-free); a link is unlinked itself, never followed.
    for (path in rev(placed)) remove_tree(path)
    ok <- TRUE
    for (m in rev(moved)) ok <- isTRUE(move_path(m$to, m$from)) && ok
    for (dir in rev(made_dirs)) {
      if (dir.exists(dir) && !is_symlink(dir) &&
          !length(list.files(dir, all.files = TRUE, no.. = TRUE))) {
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
    # Reconciles against what is now on disk, so the new resource is judged by
    # the same discovery as any other.
    reconcile_manifest(root, manifest, require = name)
  }, error = function(e) e)

  if (inherits(status, "error")) {
    return(list(error = status, restored = restore()))
  }
  report <- status$plan$report
  list(error = NULL, plan = status$plan, written = status$written,
       manifest_status = report$status[report$resource == name &
                                         report$status %in% c("added", "updated", "unchanged")])
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
