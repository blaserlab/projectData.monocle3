#' Register saved Monocle CDS directories in a data package's manifest
#'
#' `write_monocle_manifest()` is a **package-authoring** operation for
#' developers of data packages. It finds saved Monocle 3 `cell_data_set`
#' directories in a package source tree and creates or updates
#' `inst/projectData/manifest.dcf` so that [projectData](https://github.com/blaserlab/projectData)
#' resolves each one through the `projectData.monocle3::cds` loader. Installed
#' data packages never generate manifests at runtime; the manifest is written
#' once, here, and shipped with the package.
#'
#' @section Expected layout:
#' ```
#' my.datapkg/
#' |-- DESCRIPTION
#' |-- data/
#' |   |-- human_cds.rda        placeholder for human_cds
#' |   `-- ordinary_data.rda    ordinary dataset, ignored here
#' `-- inst/
#'     |-- extdata/
#'     |   `-- human_cds/       from monocle3::save_monocle_objects()
#'     `-- projectData/
#'         `-- manifest.dcf     created or updated
#' ```
#' Each directory directly below `inst/extdata/` that
#' `monocle3::save_monocle_objects(archive_control = list(archive_type =
#' "none"))` wrote is a candidate; its name is the resource name and the name
#' of the object it provides. A directory is registered only if it passes the
#' same structural checks the loader applies when the package is used (a
#' `file_index.rds` written by `save_monocle_objects()`, one rds CDS, one
#' BPCells matrix directory, every listed file present). Directories that are
#' not Monocle saves are ignored; directories that look like one but fail the
#' checks are skipped with the reason.
#'
#' @section Placeholders:
#' Every CDS needs a matching `data/<name>.rda` placeholder, so that the
#' object is discoverable with [utils::data()] and can be documented in the
#' usual way. The file is inspected without running anything: its serialized
#' header is parsed to read the object name and, for a small character vector,
#' its content. Currently the historical string `"This is a placeholder
#' object."` is recognized. A CDS without a placeholder is skipped with a
#' warning (and, if it already had a manifest entry, that entry is removed as
#' stale). A `.rda` that holds a real dataset, or that cannot be inspected, is
#' never treated as a placeholder, and no registration is created for it.
#' Placeholder files are never created or modified.
#'
#' @section Reconciliation:
#' The saved directories and placeholders currently in the package are the
#' source of truth for the entries this package owns, that is, those whose
#' `Loader` is `projectData.monocle3::cds`. The existing manifest is reconciled
#' with them, so a directory deleted by hand during development never leaves a
#' manifest that has to be repaired manually:
#'
#' | Existing entry | Action |
#' |---|---|
#' | Monocle resource with a valid directory and placeholder | kept, or updated where it differs |
#' | Monocle entry whose saved directory is gone | removed as stale |
#' | Monocle entry whose placeholder is missing | removed as stale |
#' | New valid directory with a placeholder | added |
#' | Entry of any other loader or adapter | kept unchanged, with all its fields |
#' | Resource name or object name already used by another adapter | **conflict**: reported, never taken over |
#' | Monocle entry whose directory exists but is invalid | kept; the call fails because the manifest would not be valid |
#'
#' Reconciliation only ever changes manifest entries. **It never deletes a
#' saved CDS directory or a placeholder**, and removing an entry does not touch
#' the files it described.
#'
#' The existing manifest is first read with the structural checks needed to
#' reconcile it safely (readable, known fields, `ManifestVersion: 1`, a
#' `Resource` and `Loader` in every record, unique resources, well-formed
#' `Options`), without requiring its sources to exist. A manifest that fails
#' these checks stops the call and is left untouched. The complete
#' proposed manifest is then validated by
#' [projectData::data_manifest_validate()]'s rules (through
#' [projectData::data_manifest_write()], including this package's loader) and
#' written only if that succeeds. An invalid entry of another adapter is never
#' repaired or removed: the error reports it, and the manifest is left as it
#' was.
#'
#' An existing Monocle entry is updated only where it differs: the loader,
#' source, object, adapter and recorded class are set to the values described
#' below, a missing help topic is filled in, and a `Title` or `Options` you
#' added by hand are kept. New entries are added at the end.
#'
#' Each new entry has the fields `Resource`, `Loader:
#' projectData.monocle3::cds`, `Source: extdata/<name>` (the installed layout,
#' never an absolute path or `inst/...`), `Objects`, `AdapterPackage:
#' projectData.monocle3`, `RecordedClass: cell_data_set` and `HelpTopic`.
#' `AdapterExport: projectData_loaders` is the default, which
#' [projectData::data_manifest_write()] leaves out of the file; it reads back
#' the same either way.
#'
#' The manifest is only rewritten when something was added, updated or removed,
#' so running the function again changes nothing and prints nothing. When it is
#' rewritten, the file is produced by [projectData::data_manifest_write()],
#' which validates every entry, checks that the text reads back unchanged, and
#' replaces the manifest with a single rename. A failure leaves the previous
#' manifest in place. As that writer emits every record in its standard field
#' order, hand-chosen field order or spacing in entries you did not change is
#' normalized when the manifest is rewritten. If no entry remains at all, the
#' manifest file is removed (and its directory, if that is left empty), because
#' a manifest without resources carries no information.
#'
#' @section No CDS is loaded:
#' Discovery reads only `file_index.rds`, directory listings and the header of
#' each placeholder. No CDS is restored, no BPCells matrix is opened and no
#' working directory is created. `monocle3` and `BPCells` need not be installed.
#'
#' @param package_dir Path to the root of a data-package *source* directory
#'   (the one with `DESCRIPTION`). Defaults to the working directory.
#' @return Invisibly, a data frame with one row per resource considered:
#'   `resource`, `status` (`"added"`, `"updated"`, `"unchanged"`, `"removed"`,
#'   `"skipped"` or `"conflict"`) and `detail`. Attributes `manifest` (the path) and `written`
#'   (whether the file was written) are attached. Skipped resources and
#'   conflicts also raise warnings of class `projectData.monocle3_skipped` and
#'   `projectData.monocle3_conflict`.
#' @examples
#' \dontrun{
#' # From the root of a data package that already contains saved CDS
#' # directories under inst/extdata/ and matching placeholders in data/:
#' projectData.monocle3::write_monocle_manifest(package_dir = ".")
#' }
#' @seealso [projectData_loaders()], [projectData::data_manifest_write()]
#' @export
write_monocle_manifest <- function(package_dir = ".") {
  root <- check_package_source(package_dir, call = sys.call())
  manifest <- manifest_path(root)
  outcome <- reconcile_manifest(root, manifest)
  report_manifest_changes(outcome$plan, outcome$written)
  invisible(structure(outcome$plan$report, manifest = manifest, written = outcome$written))
}

manifest_path <- function(root) file.path(root, "inst", "projectData", "manifest.dcf")

# The single reconciliation entry point, shared by write_monocle_manifest() and
# save_monocle_cds(): reads the existing manifest leniently, plans the changes
# against the resources `found` on disk, validates the complete proposed
# manifest and (when `write`) writes it.
reconcile_manifest <- function(root, manifest, found = discover_monocle_resources(root),
                               write = TRUE, require = NULL) {
  loader_id <- projectData_loaders()$id
  with_loader_registered({
    existing <- read_existing_manifest(manifest)
    plan <- plan_manifest(existing, found, loader_id)
    # `require`: a resource that must be registrable, checked before writing.
    if (!is.null(require)) {
      ok <- plan$report$status[plan$report$resource == require] %in%
        c("added", "updated", "unchanged")
      if (!any(ok)) {
        stop("'", require, "' cannot be registered in the manifest: ",
             paste(plan$report$detail[plan$report$resource == require], collapse = "; "),
             call. = FALSE)
      }
    }
    written <- if (write) write_planned_manifest(plan, manifest, root) else FALSE
    list(plan = plan, written = written)
  })
}

# Evaluates `expr` with this package's loader registered, so that projectData's
# manifest validation also runs the loader's `validate`. The loader is removed
# afterwards only if this call added it.
with_loader_registered <- function(expr) {
  loader_id <- projectData_loaders()$id
  if (!loader_id %in% projectData::data_loaders()$id) {
    projectData::data_loader_add(projectData_loaders())
    on.exit(try(projectData::data_loader_remove(loader_id), silent = TRUE), add = TRUE)
  }
  expr
}

changed_statuses <- c("added", "updated", "removed")

# Validates the proposed manifest as a whole and writes it, but only when the
# plan changes something. An unchanged manifest is validated and left alone. When
# no entry remains, the manifest file is removed (an empty manifest carries no
# information). Needs the loader registered and the sources present under `root`.
# Returns whether the file was changed.
write_planned_manifest <- function(plan, manifest, root) {
  changed <- any(plan$report$status %in% changed_statuses)
  invalid <- function(e) {
    stop(structure(
      class = c("projectData.monocle3_manifest_error", "error", "condition"),
      list(message = paste0(
        "The resulting manifest is not valid, so ", basename(manifest), " was not modified:\n",
        conditionMessage(e), "\n",
        "This package only repairs its own entries (loader ", projectData_loaders()$id,
        "); fix other entries by hand."), call = NULL)
    ))
  }
  if (!changed) {
    if (file.exists(manifest)) {
      tryCatch(projectData::data_manifest_validate(manifest, root = root), error = invalid)
    }
    return(FALSE)
  }
  if (!length(plan$descriptors)) {
    if (file.exists(manifest)) {
      file.remove(manifest)
      dir <- dirname(manifest)
      if (!length(list.files(dir, all.files = TRUE, no.. = TRUE))) unlink(dir, recursive = TRUE)
    }
    return(TRUE)
  }
  tryCatch(
    projectData::data_manifest_write(
      plan$descriptors, manifest, root = root, overwrite = file.exists(manifest)
    ),
    error = invalid
  )
  TRUE
}

# Validates the entries of other adapters in a plan without writing the
# manifest: used before anything is saved, so an unrelated broken entry stops
# the save early instead of after the data were written.
check_unrelated_entries <- function(plan, root) {
  loader_id <- projectData_loaders()$id
  others <- Filter(function(d) !identical(d$loader, loader_id), plan$descriptors)
  if (!length(others)) {
    return(invisible(TRUE))
  }
  scratch <- tempfile("projectData.monocle3-check-")
  dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  tryCatch(
    suppressMessages(projectData::data_manifest_write(
      others, file.path(scratch, "manifest.dcf"), root = root, overwrite = TRUE
    )),
    error = function(e) {
      stop(structure(
        class = c("projectData.monocle3_manifest_error", "error", "condition"),
        list(message = paste0(
          "The existing manifest has entries of other adapters that are not valid, so ",
          "nothing was written:\n", conditionMessage(e), "\n",
          "This package only repairs its own entries (loader ", loader_id,
          "); fix other entries by hand."), call = NULL)
      ))
    }
  )
  invisible(TRUE)
}

manifest_fields <- c("ManifestVersion", "Resource", "Loader", "Source", "Objects", "Title",
                     "HelpTopic", "Options", "AdapterPackage", "AdapterExport", "RecordedClass")

# Reads the manifest into descriptors with only the structural checks needed to
# reconcile it safely: readable DCF, known fields only, ManifestVersion 1, every
# record with a Resource and a Loader, unique resources, well-formed Options.
# Unlike projectData::data_manifest_validate() this does not look at the
# sources, so entries whose files were deleted can still be read (and removed).
# The result has the shape of the validated descriptors; the complete proposed
# manifest is validated by projectData before anything is written.
read_existing_manifest <- function(manifest) {
  if (!file.exists(manifest)) {
    return(list())
  }
  fail <- function(...) {
    stop(structure(
      class = c("projectData.monocle3_manifest_error", "error", "condition"),
      list(message = paste0("The existing manifest cannot be used and was not modified:\n",
                            ..., "\n(", manifest, ")"), call = NULL)
    ))
  }
  m <- tryCatch(read.dcf(manifest), error = function(e) {
    fail("not readable as DCF (", conditionMessage(e), ")")
  })
  unknown <- setdiff(colnames(m), manifest_fields)
  if (length(unknown)) {
    fail("unknown field(s) ", paste0("'", unknown, "'", collapse = ", "))
  }
  get <- function(i, f) if (f %in% colnames(m)) unname(m[i, f]) else NA_character_
  if (!nrow(m) || is.na(get(1L, "ManifestVersion"))) {
    fail("the first record must contain ManifestVersion")
  }
  if (!identical(get(1L, "ManifestVersion"), "1")) {
    fail("unsupported ManifestVersion '", get(1L, "ManifestVersion"), "' (supported: 1)")
  }
  rows <- seq_len(nrow(m))[-1L]
  ids <- vapply(rows, function(i) get(i, "Resource"), "")
  if (anyNA(ids)) {
    fail("every resource record needs a Resource field")
  }
  if (anyDuplicated(ids)) {
    fail("duplicate Resource ", paste0("'", unique(ids[duplicated(ids)]), "'", collapse = ", "),
         " declared more than once")
  }
  lapply(rows, function(i) {
    resource <- get(i, "Resource")
    loader <- get(i, "Loader")
    if (is.na(loader)) {
      fail("resource '", resource, "' needs a Loader")
    }
    objects <- if (!is.na(get(i, "Objects"))) trimws(strsplit(get(i, "Objects"), ",", fixed = TRUE)[[1L]])
    n <- max(1L, length(objects))
    one <- function(f) rep(get(i, f), n)
    adapter <- if (!is.na(get(i, "AdapterPackage"))) {
      list(package = get(i, "AdapterPackage"),
           export = if (is.na(get(i, "AdapterExport"))) "projectData_loaders" else get(i, "AdapterExport"))
    }
    list(resource = resource, loader = loader, source = get(i, "Source"), objects = objects,
         options = parse_options_field(get(i, "Options"), resource, fail),
         title = one("Title"), help_topic = one("HelpTopic"),
         recorded_class = one("RecordedClass"), adapter = adapter, origin = "manifest")
  })
}

parse_options_field <- function(text, resource, fail) {
  if (is.na(text)) {
    return(list())
  }
  entries <- trimws(strsplit(text, ";", fixed = TRUE)[[1L]])
  pos <- regexpr("=", entries, fixed = TRUE)
  if (!length(entries) || any(!nzchar(entries)) || any(pos < 1L) || grepl(";\\s*$", text)) {
    fail("resource '", resource, "': malformed Options; expected key=value entries")
  }
  stats::setNames(as.list(trimws(substring(entries, pos + 1L))),
                  trimws(substr(entries, 1L, pos - 1L)))
}

# The descriptor of one Monocle resource, in the form projectData documents for
# data_manifest_write().
monocle_descriptor <- function(resource, loader_id) {
  list(
    resource = resource,
    loader = loader_id,
    source = paste0("extdata/", resource),
    objects = resource,
    recorded_class = "cell_data_set",
    help_topic = resource,
    adapter = list(package = "projectData.monocle3", export = "projectData_loaders")
  )
}

descriptor_key <- function(d) {
  d[c("resource", "loader", "source", "objects", "options", "title", "help_topic",
      "recorded_class", "adapter")]
}

# Applies the managed fields of `desired` to an existing entry of this loader,
# keeping whatever else (Title, Options, a hand-written HelpTopic) it carries.
update_monocle_descriptor <- function(current, desired) {
  new <- current
  for (f in c("loader", "source", "objects", "recorded_class", "adapter")) {
    new[[f]] <- desired[[f]]
  }
  if (all(is.na(new$help_topic))) {
    new$help_topic <- desired$help_topic
  }
  for (f in c("title", "help_topic")) {
    new[[f]] <- new[[f]][1L]
  }
  new
}

# Reconciles the manifest's descriptors with the resources found on disk.
#
# Monocle-owned entries (loader == ours) whose saved CDS directory is gone, or
# whose placeholder is missing, are removed as stale; valid resources are added
# or updated; every other entry passes through untouched. `found` is the
# result of discover_monocle_resources() (or a stand-in with the same columns).
# Returns the proposed descriptors and a report with one row per resource
# (`resource`, `status`, `detail`).
plan_manifest <- function(existing, found, loader_id) {
  descriptors <- existing
  report <- list()
  add_report <- function(resource, status, detail = "") {
    report[[length(report) + 1L]] <<- data.frame(
      resource = resource, status = status, detail = detail, stringsAsFactors = FALSE
    )
  }
  object_owner <- function(object, except = NA_integer_) {
    for (i in seq_along(descriptors)) {
      if (!identical(i, except) && object %in% descriptors[[i]]$objects) {
        return(descriptors[[i]]$resource)
      }
    }
    NA_character_
  }

  # Stale entries first, so that the object names they declared are free again.
  stale <- vapply(descriptors, function(d) {
    if (!identical(d$loader, loader_id)) {
      return(NA_character_)
    }
    row <- match(d$resource, found$resource)
    if (is.na(row)) {
      paste0("no saved CDS in inst/extdata/", d$resource)
    } else if (identical(found$status[row], "no_placeholder")) {
      paste0("no placeholder data/", d$resource, ".rda")
    } else {
      NA_character_
    }
  }, "")
  for (i in which(!is.na(stale))) {
    add_report(descriptors[[i]]$resource, "removed", stale[[i]])
  }
  removed_for_placeholder <- vapply(descriptors, function(d) d$resource, "")[
    grepl("^no placeholder", stale)]
  descriptors <- descriptors[is.na(stale)]

  for (i in seq_len(nrow(found))) {
    r <- found[i, , drop = FALSE]
    if (!identical(r$status, "discovered")) {
      # Already reported as removed, with the same reason.
      if (!r$resource %in% removed_for_placeholder) {
        add_report(r$resource, "skipped", r$reason)
      }
      next
    }
    desired <- monocle_descriptor(r$resource, loader_id)
    ids <- vapply(descriptors, function(d) d$resource, "")
    pos <- match(r$resource, ids)
    owner <- object_owner(r$resource, except = pos)
    if (!is.na(owner)) {
      add_report(r$resource, "conflict", paste0(
        "object '", r$resource, "' is already declared by resource '", owner, "'"))
    } else if (is.na(pos)) {
      descriptors[[length(descriptors) + 1L]] <- desired
      add_report(r$resource, "added")
    } else if (!identical(descriptors[[pos]]$loader, loader_id)) {
      add_report(r$resource, "conflict", paste0(
        "resource is already assigned to loader '", descriptors[[pos]]$loader, "'"))
    } else {
      updated <- update_monocle_descriptor(descriptors[[pos]], desired)
      if (identical(descriptor_key(updated), descriptor_key(descriptors[[pos]]))) {
        add_report(r$resource, "unchanged")
      } else {
        descriptors[[pos]] <- updated
        add_report(r$resource, "updated")
      }
    }
  }
  report <- if (length(report)) {
    do.call(rbind, report)
  } else {
    data.frame(resource = character(), status = character(), detail = character(),
               stringsAsFactors = FALSE)
  }
  list(descriptors = descriptors, report = report)
}

# Reports a rewritten manifest concisely; says nothing when the manifest did not
# change. Skipped directories and conflicts are warnings (`warn`). Rows for
# `except` are left out of the summary, and nothing is printed if they were the
# only changes (save_monocle_cds() reports its own resource).
report_manifest_changes <- function(plan, written, warn = TRUE, except = character()) {
  report <- plan$report
  shown <- report[!report$resource %in% except, , drop = FALSE]
  if (written && any(shown$status %in% changed_statuses)) {
    list_status <- function(status, label) {
      ids <- shown$resource[shown$status == status]
      if (length(ids)) paste0("  ", label, ": ", paste(ids, collapse = ", "))
    }
    loader_id <- projectData_loaders()$id
    n_other <- sum(!vapply(plan$descriptors, function(d) identical(d$loader, loader_id), NA))
    message(paste(c(
      "projectData.monocle3: manifest updated",
      list_status("added", "Added"),
      list_status("updated", "Updated"),
      list_status("removed", "Removed stale"),
      if (!length(plan$descriptors)) "  No resources remain; the manifest file was removed",
      if (n_other) paste0("  Preserved: ", n_other, " unrelated resource",
                          if (n_other != 1L) "s")
    ), collapse = "\n"))
  }
  if (warn) {
    for (status in c("skipped", "conflict")) {
      rows <- report[report$status == status, , drop = FALSE]
      if (!nrow(rows)) next
      text <- if (identical(status, "skipped")) {
        "Skipped saved Monocle directories (not registered):\n"
      } else {
        "Conflicts with existing manifest entries (left unchanged):\n"
      }
      warning(structure(
        class = c(paste0("projectData.monocle3_", status), "warning", "condition"),
        list(message = paste0(text, paste0("  ", rows$resource, ": ", rows$detail,
                                           collapse = "\n")),
             call = NULL)
      ))
    }
  }
  invisible()
}
