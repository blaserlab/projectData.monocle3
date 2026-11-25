# Ownership of an existing resource directory ---------------------------------
#
# Three separate questions, answered by three separate pieces of code:
#   discovery     looks_like_monocle_save(): is this worth looking at? (any marker
#                 file; a heuristic that never authorizes anything)
#   validation    validate_monocle_cds(): does it have the structure the loader
#                 supports?
#   authorization resource_ownership(): may save_monocle_cds(overwrite = TRUE)
#                 replace it? Defined here.
#
# A non-empty directory may be replaced only when this package can show it wrote
# it. Evidence, each judged independently:
#   S  `file_index.rds` that reads as a native Monocle index written by
#      save_monocle_objects() with a usable file listing (structure only; whether
#      the listed files exist is not required, so damaged saves still count)
#   M  a manifest entry of this loader whose Source and Objects agree with the name
#   P  a recognized placeholder for this name (classed, or the historical string)
# and the rule is: at least two of S, M and P, no entry in the directory that the
# evidence does not account for, and no conflicting manifest entry. So:
#   valid native save + placeholder or manifest entry      replaceable ("valid")
#   damaged save, same evidence                            replaceable ("damaged")
#   native save found alone (could be a user's own)        refused, ambiguous
#   marker files alone (bpcells_matrix_dir, object.rds)    refused
# Refused whatever the evidence: a manifest entry of another loader for the name,
# a manifest entry of this loader that disagrees with the directory, entries that
# neither the index nor the three names Monocle always writes (file_index.rds,
# cds_object.rds, bpcells_matrix_dir) account for, and a non-directory.
#
# An empty directory is replaceable (state "empty"): it holds nothing that could
# be lost, and it is what is left when a previous save was interrupted. It is
# still subject to the manifest checks and to `overwrite`.
#
# `existing` is the list of manifest descriptors (read_existing_manifest()).
# Returns list(owned, state, reason, class, evidence); `class` is the error
# class to use when `owned` is FALSE.
resource_ownership <- function(root, name, existing, has_placeholder) {
  dest <- file.path(root, "inst", "extdata", name)
  loader_id <- projectData_loaders()$id
  result <- function(owned, state, reason = NA_character_, class = NULL,
                     evidence = character()) {
    list(owned = owned, state = state, reason = reason, class = class, evidence = evidence)
  }
  refuse <- function(reason, class = "projectData.monocle3_not_owned", evidence = character()) {
    result(FALSE, "refused", reason, class, evidence)
  }

  if (!dir.exists(dest)) {
    return(refuse("it is not a directory"))
  }

  mine <- Filter(function(d) identical(d$resource, name), existing)
  d <- if (length(mine)) mine[[1L]]
  if (!is.null(d) && !identical(d$loader, loader_id)) {
    return(refuse(paste0("the manifest assigns '", name, "' to loader '", d$loader, "'"),
                  class = "projectData.monocle3_conflict"))
  }
  agrees <- !is.null(d) && identical(d$source, paste0("extdata/", name)) &&
    identical(d$objects, name)
  if (!is.null(d) && !agrees) {
    return(refuse(paste0("its manifest entry does not agree with it (Source '", d$source,
                         "', Objects '", paste(d$objects, collapse = ", "), "')"),
                  class = "projectData.monocle3_ambiguous_ownership"))
  }

  entries <- list.files(dest, recursive = TRUE, all.files = TRUE, include.dirs = TRUE,
                        no.. = TRUE)
  if (!length(entries)) {
    return(result(TRUE, "empty"))
  }

  index <- read_native_index(dest, name)
  native <- is.null(index$problem)
  top <- list.files(dest, all.files = TRUE, no.. = TRUE)
  expected <- c("file_index.rds", "cds_object.rds", "bpcells_matrix_dir")
  accounted <- if (native) {
    c("file_index.rds", sub("[/\\\\].*$", "", index$value$files$file_path))
  } else {
    expected
  }
  stray <- setdiff(top, accounted)
  if (length(stray)) {
    return(refuse(paste0(
      if (!looks_like_monocle_save(dest)) "it is not a saved Monocle directory; ",
      "it contains entries that a saved Monocle directory written by this package does ",
      "not have: ", paste(stray, collapse = ", "))))
  }

  evidence <- c(
    `a native Monocle file index` = native,
    `a manifest entry of this loader` = agrees,
    `a recognized placeholder` = isTRUE(has_placeholder)
  )
  found <- names(evidence)[evidence]
  if (sum(evidence) >= 2L) {
    problem <- validate_monocle_cds(
      list(source = paste0("extdata/", name), objects = name), file.path(root, "inst"), list()
    )
    return(if (isTRUE(problem)) {
      result(TRUE, "valid", evidence = found)
    } else {
      result(TRUE, "damaged", reason = problem, evidence = found)
    })
  }

  what <- if (looks_like_monocle_save(dest)) {
    "it resembles a saved Monocle directory but"
  } else {
    "it is not a saved Monocle directory, and"
  }
  refuse(paste0(
    what, " ownership cannot be established: found ",
    if (length(found)) paste(found, collapse = ", ") else "no evidence",
    if (!native && !is.null(index$problem)) paste0(" (", index$problem, ")"),
    "; at least two of a native Monocle file index, a manifest entry of this loader and ",
    "a recognized placeholder are needed"),
    class = if (looks_like_monocle_save(dest)) {
      "projectData.monocle3_ambiguous_ownership"
    } else {
      "projectData.monocle3_not_owned"
    })
}

# Reads `file_index.rds` of a saved directory and judges only its structure.
# Returns list(value, problem); `problem` is NULL when the index is a usable
# native Monocle index.
read_native_index <- function(dir, name) {
  path <- file.path(dir, "file_index.rds")
  if (!file.exists(path) || dir.exists(path)) {
    return(list(value = NULL, problem = "no file_index.rds"))
  }
  value <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(value)) {
    return(list(value = NULL, problem = "file_index.rds cannot be read"))
  }
  problem <- file_index_listing_problem(value, paste0("extdata/", name))
  list(value = value, problem = if (!is.null(problem)) "file_index.rds is not a valid Monocle index")
}
