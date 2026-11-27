# Filesystem safety ------------------------------------------------------------
#
# Trust boundaries (see also the "Filesystem safety" section of AGENTS.md):
#   1. the author's original data (a BPCells directory anywhere on disk): read
#      only, by monocle3/BPCells, which FOLLOW symbolic links;
#   2. the package source tree: the author's; parents such as `inst/extdata` may
#      legitimately be symbolic links;
#   3. the staging directory: created here, exclusively ours;
#   4. the installed resource: read only, reached through a possibly symlinked
#      library;
#   5. the work directory allocated by projectData: the only place the loader's
#      native copy writes to.
# Neither monocle3 nor BPCells check path containment or refuse links, so this
# file does, with ONE rule applied wherever a Monocle resource tree is read or
# copied: nothing inside a resource (or an external BPCells directory) may be a
# symbolic link, dangling, escaping or not. The directory a path starts from may
# itself be reached through links (symlinked R libraries are legitimate); only
# what lies inside it is judged. Links are never followed by the walker below.
# Base R cannot tell a FIFO or device node from a regular file; those are not
# detected (a documented limitation).

# Names a BPCells matrix directory must have (monocle3 itself reads `val` or
# `val_data` for its checksum). Verified for compressed and uncompressed layouts.
bpcells_required_files <- c("version", "storage_order", "shape", "row_names",
                            "col_names", "idxptr")

# Upper bound on entries listed by the walker; a Monocle save has about ten.
max_tree_entries <- 10000L

# TRUE for symbolic links (including dangling ones; on Windows also junctions
# that R can read). Sys.readlink() gives NA, not "", for paths that do not exist.
is_symlink <- function(paths) {
  link <- Sys.readlink(paths)
  !is.na(link) & nzchar(link)
}

# Containment is judged on resolved locations. `dir` is resolved too, so a
# symlinked library or resource directory is accepted.
is_inside <- function(paths, dir, windows = .Platform$OS.type == "windows") {
  real_dir <- normalizePath(dir, winslash = "/", mustWork = TRUE)
  real <- normalizePath(paths, winslash = "/", mustWork = FALSE)
  prefix <- paste0(sub("/+$", "", real_dir), "/")
  if (windows) {
    startsWith(tolower(real), tolower(prefix))
  } else {
    startsWith(real, prefix)
  }
}

# Paths recorded in an index must be plain relative paths: no absolute or
# home-relative forms, no drive letters, no `..` components.
is_plain_relative <- function(paths) {
  !grepl("^(/|\\\\|[A-Za-z]:|~)", paths) &
    !vapply(strsplit(paths, "[/\\\\]"), function(p) any(p == ".."), NA)
}

# Every entry below `dir` without following symbolic links: a data frame of
# `path` (relative to `dir`) and `kind` ("file", "dir", "symlink" or "other").
# Links are listed but never entered, so a link cycle cannot make this loop and
# nothing outside `dir` is read. Cost: one directory listing per real directory,
# bounded by `max_entries` (the attribute `truncated` is set when exceeded).
tree_entries <- function(dir, max_entries = max_tree_entries) {
  rel <- character()
  kind <- character()
  pending <- ""
  truncated <- FALSE
  while (length(pending) && !truncated) {
    cur <- pending[[1L]]
    pending <- pending[-1L]
    full <- if (nzchar(cur)) file.path(dir, cur) else dir
    found <- list.files(full, all.files = TRUE, no.. = TRUE)
    if (!length(found)) next
    r <- if (nzchar(cur)) file.path(cur, found) else found
    p <- file.path(dir, r)
    k <- ifelse(is_symlink(p), "symlink",
                ifelse(dir.exists(p), "dir", ifelse(file.exists(p), "file", "other")))
    rel <- c(rel, r)
    kind <- c(kind, k)
    pending <- c(pending, r[k == "dir"])
    truncated <- length(rel) > max_entries
  }
  out <- data.frame(path = rel, kind = kind, stringsAsFactors = FALSE)
  attr(out, "truncated") <- truncated
  out
}

# One human-readable phrase per refused entry.
entry_problems <- function(dir, entries) {
  bad <- entries[entries$kind %in% c("symlink", "other"), , drop = FALSE]
  vapply(seq_len(nrow(bad)), function(i) {
    full <- file.path(dir, bad$path[i])
    what <- if (bad$kind[i] == "other") {
      "is not a regular file or directory"
    } else if (!file.exists(full)) {
      "is a dangling symbolic link"
    } else if (!is_inside(full, dir)) {
      "is a symbolic link that leaves the directory"
    } else {
      "is a symbolic link"
    }
    paste0("'", bad$path[i], "' ", what)
  }, "")
}

# Problems with the TREE of a saved Monocle directory (loader, authoring and
# ownership share this): links and non-regular entries anywhere inside, and a
# runaway number of entries. Returns character(0) when clean.
saved_tree_problems <- function(dir) {
  entries <- tree_entries(dir)
  c(if (isTRUE(attr(entries, "truncated"))) {
      paste0("it holds more than ", max_tree_entries, " entries")
    },
    entry_problems(dir, entries))
}

# Problems with one BPCells matrix directory, whether it lies inside a resource
# or is the author's original data: it must exist, be flat, hold only regular
# files (never a link: the copy made by BPCells follows links and would put
# files from elsewhere into the resource) and have the files BPCells writes.
# Reads no file contents.
backing_dir_problems <- function(path) {
  if (!dir.exists(path)) {
    return("it does not exist or is not a directory")
  }
  entries <- tree_entries(path)
  nested <- entries$path[entries$kind == "dir"]
  problems <- c(
    if (isTRUE(attr(entries, "truncated"))) paste0("it holds more than ", max_tree_entries, " entries"),
    entry_problems(path, entries),
    if (length(nested)) paste0("'", nested, "' is a nested directory")
  )
  # Links and odd entries were reported above; they are not also "missing".
  files <- entries$path[entries$kind != "dir"]
  missing <- setdiff(bpcells_required_files, files)
  if (!any(c("val", "val_data") %in% files)) missing <- c(missing, "val")
  if (length(missing)) {
    problems <- c(problems, paste0("required file(s) missing: ", paste(missing, collapse = ", ")))
  }
  problems
}

# Removes `path` without ever following a link: a link is unlinked itself, and
# R's unlink(recursive = TRUE) does not enter links (verified). With `within`,
# anything that does not resolve inside it is left alone. Returns TRUE when
# `path` is gone afterwards.
remove_tree <- function(path, within = NULL) {
  if (is_symlink(path)) {
    return(isTRUE(file.remove(path)))
  }
  if (!file.exists(path)) {
    return(TRUE)
  }
  if (!is.null(within) && !is_inside(path, within)) {
    return(FALSE)
  }
  unlink(path, recursive = TRUE)
  !file.exists(path)
}

# The only renaming primitive of the commit, so that tests can inject failures.
# Returns TRUE or FALSE; on failure the reason R reported (the operating system's
# message) is in attr(, "reason"). On Windows renaming a directory fails with
# "Access is denied" (observed in CI) while the staged BPCells files are still
# open somewhere in the session, and gc() did not release them. After a rename
# fails there, a directory is moved by copying it and then removing the source:
# a copy only needs read access, and nothing is lost if it fails (`to` is
# removed again, `from` is untouched). If the source cannot be removed afterwards
# it is left behind (it is a staging or backup path that is cleaned up later) and
# the move still counts as done.
move_path <- function(from, to) {
  reason <- character()
  attempt <- function() {
    withCallingHandlers(
      isTRUE(file.rename(from, to)),
      warning = function(w) {
        reason <<- conditionMessage(w)
        invokeRestart("muffleWarning")
      }
    )
  }
  ok <- attempt()
  if (!ok && .Platform$OS.type == "windows" && dir.exists(from) && !file.exists(to)) {
    ok <- copy_then_remove(from, to)
    if (!ok) reason <- c(reason, "copy fallback failed as well")
  }
  structure(ok, reason = if (!ok) reason)
}

# Copies the directory `from` to the new path `to`, then removes `from` (best
# effort). Links are never followed (the trees moved here were checked to hold
# none). On any failure `to` is removed and FALSE returned.
copy_then_remove <- function(from, to) {
  made <- isTRUE(suppressWarnings(dir.create(to)))
  copied <- made && all(suppressWarnings(file.copy(
    list.files(from, all.files = TRUE, no.. = TRUE, full.names = TRUE), to,
    recursive = TRUE, copy.mode = TRUE
  )))
  if (!copied) {
    if (made) unlink(to, recursive = TRUE)
    return(FALSE)
  }
  gc()
  suppressWarnings(unlink(from, recursive = TRUE))
  TRUE
}

# Creates `path` as a new directory that did not exist (dir.create() never
# follows a pre-existing link here: it fails). Returns TRUE on success.
make_new_dir <- function(path, recursive = FALSE) {
  isTRUE(suppressWarnings(dir.create(path, recursive = recursive))) && !is_symlink(path)
}
