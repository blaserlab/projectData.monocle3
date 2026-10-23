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
#' ├── DESCRIPTION
#' ├── data/
#' │   ├── human_cds.rda        placeholder for human_cds
#' │   └── ordinary_data.rda    ordinary dataset, ignored here
#' └── inst/
#'     ├── extdata/
#'     │   └── human_cds/       from monocle3::save_monocle_objects()
#'     └── projectData/
#'         └── manifest.dcf     created or updated
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
#' warning. A `.rda` that holds a real dataset, or that cannot be inspected, is
#' never treated as a placeholder, and no registration is created for it.
#' Placeholder files are never created or modified.
#'
#' @section Existing manifests:
#' Entries are read with [projectData::data_manifest_validate()], so an
#' invalid manifest stops the call and is left untouched. Entries for other
#' loaders and resources are kept in their original order, with all of their
#' fields. A resource already assigned to a different loader, or whose object
#' name is already declared by another resource, is reported as a **conflict**
#' and left as it is; this function never takes over entries managed by
#' something else. A Monocle entry that already exists is updated only where it
#' differs: the loader, source, object, adapter and recorded class are set to
#' the values described below, a missing help topic is filled in, and a
#' `Title` or `Options` you added by hand are kept. New entries are added at
#' the end.
#'
#' Each new entry has the fields `Resource`, `Loader:
#' projectData.monocle3::cds`, `Source: extdata/<name>` (the installed layout,
#' never an absolute path or `inst/...`), `Objects`, `AdapterPackage:
#' projectData.monocle3`, `RecordedClass: cell_data_set` and `HelpTopic`.
#' `AdapterExport: projectData_loaders` is the default, which
#' [projectData::data_manifest_write()] leaves out of the file; it reads back
#' the same either way.
#'
#' The manifest is only rewritten when something was added or updated, so
#' running the function again changes nothing. When it is rewritten, the file
#' is produced by [projectData::data_manifest_write()], which validates every
#' entry (including with this package's loader), checks that the text reads
#' back unchanged, and replaces the manifest with a single rename. A failure
#' leaves the previous manifest in place. As that writer emits every record in
#' its standard field order, hand-chosen field order or spacing in entries you
#' did not change is normalized when another entry is added.
#'
#' @section No CDS is loaded:
#' Discovery reads only `file_index.rds`, directory listings and the header of
#' each placeholder. No CDS is restored, no BPCells matrix is opened and no
#' working directory is created. `monocle3` and `BPCells` need not be installed.
#'
#' @param package_dir Path to the root of a data-package *source* directory
#'   (the one with `DESCRIPTION`). Defaults to the working directory.
#' @return Invisibly, a data frame with one row per resource considered:
#'   `resource`, `status` (`"added"`, `"updated"`, `"unchanged"`, `"skipped"` or
#'   `"conflict"`) and `detail`. Attributes `manifest` (the path) and `written`
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
  manifest <- file.path(root, "inst", "projectData", "manifest.dcf")
  found <- discover_monocle_resources(root)

  loader_id <- projectData_loaders()$id
  plan <- with_loader_registered({
    existing <- read_existing_manifest(manifest, root)
    plan <- plan_manifest(existing, found, loader_id)
    changed <- write_planned_manifest(plan, manifest, root)
    plan
  })
  report <- plan$report
  report_manifest_changes(report, manifest, changed)
  invisible(structure(report, manifest = manifest, written = changed))
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

# Writes the planned descriptors only when something was added or updated.
# Needs the loader registered and the sources present under `root`.
write_planned_manifest <- function(plan, manifest, root) {
  changed <- any(plan$report$status %in% c("added", "updated"))
  if (changed) {
    projectData::data_manifest_write(
      plan$descriptors, manifest, root = root, overwrite = file.exists(manifest)
    )
  }
  changed
}

read_existing_manifest <- function(manifest, root) {
  if (!file.exists(manifest)) {
    return(list())
  }
  tryCatch(
    projectData::data_manifest_validate(manifest, root = root),
    error = function(e) {
      stop("The existing manifest cannot be used and was not modified:\n",
           conditionMessage(e), call. = FALSE)
    }
  )
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

# Returns the merged descriptor list and a one-row-per-resource report. Entries
# not belonging to a discovered Monocle resource pass through untouched.
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

  for (i in seq_len(nrow(found))) {
    r <- found[i, , drop = FALSE]
    if (!identical(r$status, "discovered")) {
      add_report(r$resource, "skipped", r$reason)
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

report_manifest_changes <- function(report, manifest, written) {
  rel <- paste0("inst/projectData/", basename(manifest))
  if (!nrow(report)) {
    message("No saved Monocle CDS resources found under inst/extdata/; ",
            "the manifest was not changed.")
    return(invisible())
  }
  lines <- sprintf("  %-9s %s%s", report$status, report$resource,
                   ifelse(nzchar(report$detail), paste0(" (", report$detail, ")"), ""))
  lines <- lines[!report$status %in% c("skipped", "conflict")]
  if (length(lines)) {
    message(if (written) "Wrote " else "No changes to ", rel, ":\n",
            paste(lines, collapse = "\n"))
  }
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
  invisible()
}
