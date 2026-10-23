# Discovery of saved Monocle CDS resources in a data-package source tree.
# Nothing in this file writes to the file system, restores a CDS, or touches
# monocle3 or BPCells.

# Checks that `package_dir` is an R package source directory and returns its
# normalized path.
check_package_source <- function(package_dir, call = NULL) {
  fail <- function(...) {
    stop(structure(
      class = c("projectData.monocle3_package_dir_error", "error", "condition"),
      list(message = paste0(...), call = call)
    ))
  }
  if (!is_scalar_string(package_dir)) {
    fail("`package_dir` must be a single path.")
  }
  if (!dir.exists(package_dir)) {
    fail("`package_dir` ('", package_dir, "') is not an existing directory.")
  }
  root <- normalizePath(package_dir, winslash = "/", mustWork = TRUE)
  if (file.exists(file.path(root, "Meta", "package.rds"))) {
    fail("'", root, "' is an installed package. Run this on the package source ",
         "directory; installed packages never generate manifests.")
  }
  desc <- file.path(root, "DESCRIPTION")
  pkg <- if (file.exists(desc)) {
    tryCatch(read.dcf(desc, fields = "Package")[1L, 1L], error = function(e) NA_character_)
  } else {
    NA_character_
  }
  if (is.na(pkg)) {
    fail("'", root, "' is not an R package source directory ",
         "(no DESCRIPTION file with a Package field).")
  }
  root
}

discovery_columns <- function(n = 0L) {
  data.frame(
    resource = character(n), status = character(n), reason = character(n),
    source = character(n), path = character(n), placeholder = character(n),
    stringsAsFactors = FALSE
  )
}

# Finds saved Monocle CDS directories under `<package_dir>/inst/extdata/` and
# pairs each with its `data/<resource>.rda` placeholder.
#
# Returns one row per candidate directory, sorted by resource name, with
# `status`:
#   discovered         valid saved CDS with a recognized placeholder
#   invalid_cds        looks like a Monocle save but fails the loader's checks
#   no_placeholder     valid CDS, no matching data/ file
#   not_placeholder    data/ file holds something other than a placeholder
#   bad_placeholder    data/ file is unreadable, or the match is ambiguous
# Directories that show no sign of being a Monocle save are not listed.
# `source` is relative to the installed package root (`extdata/<resource>`).
discover_monocle_resources <- function(package_dir) {
  root <- check_package_source(package_dir)
  extdata <- file.path(root, "inst", "extdata")
  if (!dir.exists(extdata)) {
    return(discovery_columns())
  }
  entries <- sort(list.files(extdata, full.names = FALSE))
  entries <- entries[!startsWith(entries, ".")]
  entries <- entries[dir.exists(file.path(extdata, entries))]

  rows <- lapply(entries, function(name) {
    dir <- file.path(extdata, name)
    if (!looks_like_monocle_save(dir)) {
      return(NULL)
    }
    source <- paste0("extdata/", name)
    row <- function(status, reason = NA_character_, placeholder = NA_character_) {
      data.frame(resource = name, status = status, reason = reason, source = source,
                 path = dir, placeholder = placeholder, stringsAsFactors = FALSE)
    }
    if (!identical(make.names(name), name)) {
      return(row("invalid_cds", paste0(
        "'", name, "' is not a syntactically valid R object name, so it cannot ",
        "match a data/ placeholder object")))
    }
    # The loader's own structural check, run against the installed-layout path.
    verdict <- validate_monocle_cds(
      list(source = source, objects = name), file.path(root, "inst"), list()
    )
    if (!isTRUE(verdict)) {
      return(row("invalid_cds", verdict))
    }
    match_placeholder(root, name, row)
  })
  rows <- rows[!vapply(rows, is.null, NA)]
  if (!length(rows)) {
    return(discovery_columns())
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

# A directory is a candidate when it carries any marker of a Monocle save. The
# BPCells matrix directory alone is a marker of *candidacy* only; whether it is
# a complete save is decided by the loader's validation.
looks_like_monocle_save <- function(dir) {
  any(file.exists(file.path(dir, c("file_index.rds", "cds_object.rds", "bpcells_matrix_dir"))))
}

rda_extensions <- c("rda", "RData", "rdata")

match_placeholder <- function(root, name, row) {
  data_dir <- file.path(root, "data")
  candidates <- file.path(data_dir, paste0(name, ".", rda_extensions))
  candidates <- candidates[file.exists(candidates)]
  if (!length(candidates)) {
    return(row("no_placeholder", paste0(
      "no data/", name, ".rda placeholder; create one before registering the resource")))
  }
  if (length(candidates) > 1L) {
    return(row("bad_placeholder", paste0(
      "more than one data file matches '", name, "': ",
      paste(basename(candidates), collapse = ", "))))
  }
  rel <- paste0("data/", basename(candidates))
  info <- inspect_rda(candidates)
  if (!isTRUE(info$readable)) {
    return(row("bad_placeholder", paste0(rel, " could not be inspected: ", info$reason),
               candidates))
  }
  if (!identical(info$names, name) || identical(info$single, FALSE)) {
    found <- if (identical(info$single, FALSE) && identical(info$names, name)) {
      "more than one object"
    } else if (!length(info$names)) {
      "no objects"
    } else {
      paste0("object ", paste0("'", info$names, "'", collapse = ", "))
    }
    return(row("not_placeholder", paste0(
      rel, " holds ", found, " instead of the single object '", name, "'")))
  }
  if (!is_recognized_placeholder(info, name)) {
    return(row("not_placeholder", paste0(
      rel, " holds a ", describe_rda_object(info), ", not a recognized placeholder; ",
      "it is left alone")))
  }
  row("discovered", placeholder = candidates)
}

describe_rda_object <- function(info) {
  switch(info$kind,
    character = "character vector with different content",
    paste0("non-placeholder object (", info$kind, ")")
  )
}

# Placeholder recognition -------------------------------------------------

# Each recognizer takes the object summary from inspect_rda() and the expected
# object name, and returns TRUE or FALSE. To accept a new placeholder
# representation, add a recognizer here; discovery does not change.
legacy_placeholder_text <- "This is a placeholder object."

placeholder_recognizers <- function() {
  list(
    # Historical form: a plain, unclassed, length-one character string.
    legacy_string = function(info, name) {
      isTRUE(info$single) &&
        identical(info$kind, "character") &&
        length(info$value) == 1L &&
        identical(info$value, legacy_placeholder_text) &&
        !length(info$attributes)
    },
    # Written by save_monocle_cds(): a named character vector of instructions
    # that carries its class, object name and package as attributes.
    classed = function(info, name) {
      attrs <- info$attributes
      isTRUE(info$single) &&
        identical(info$kind, "character") &&
        length(info$value) >= 1L &&
        identical(attrs$class, placeholder_class) &&
        identical(attrs$object_name, name) &&
        length(attrs$package) == 1L && !is.na(attrs$package) &&
        length(attrs$names) == length(info$value)
    }
  )
}

is_recognized_placeholder <- function(info, name) {
  any(vapply(placeholder_recognizers(), function(f) isTRUE(f(info, name)), NA))
}

# Inspecting an .rda without running anything ---------------------------------

# Reads just enough of an `.rda` (an XDR serialization stream, usually
# compressed) to learn the first object's name, whether it is the only object,
# and, when it is a small character vector, its content and attributes. The
# stream is parsed, never evaluated or unserialized, so nothing in the file is
# executed, and a large real dataset is rejected after a few bytes. Anything
# unexpected yields `readable = TRUE` with a non-placeholder `kind`, or
# `readable = FALSE` with a reason; both are treated as "not a placeholder".
inspect_rda <- function(path, max_chars = 4096L, max_strings = 16L) {
  unsupported <- function(why) {
    stop(structure(class = c("rda_unsupported", "error", "condition"),
                   list(message = why, call = NULL)))
  }
  con <- tryCatch(gzfile(path, "rb"), error = function(e) NULL)
  if (is.null(con)) {
    return(list(readable = FALSE, reason = "file cannot be opened"))
  }
  on.exit(close(con), add = TRUE)

  int <- function() {
    x <- readBin(con, "integer", 1L, size = 4L, endian = "big")
    if (!length(x)) unsupported("unexpected end of file")
    x
  }
  bytes <- function(n) {
    if (is.na(n) || n < 0L || n > max_chars) unsupported("string too long to inspect")
    if (n == 0L) return("")
    raw <- readBin(con, "raw", n)
    if (length(raw) != n) unsupported("unexpected end of file")
    rawToChar(raw)
  }
  type_of <- function(flags) bitwAnd(flags, 255L)
  has_attr <- function(flags) bitwAnd(flags, 512L) != 0L
  has_tag <- function(flags) bitwAnd(flags, 1024L) != 0L

  # Symbols already seen, so that back-references (REFSXP) resolve.
  symbols <- character()
  charsxp <- function() {
    flags <- int()
    if (type_of(flags) != 9L) unsupported("expected a string")
    len <- int()
    if (len == -1L) NA_character_ else bytes(len)
  }
  tag <- function() {
    flags <- int()
    type <- type_of(flags)
    if (type == 1L) {
      nm <- charsxp()
      symbols[[length(symbols) + 1L]] <<- nm
      nm
    } else if (type == 255L) {
      idx <- bitwShiftR(flags, 8L)
      if (idx == 0L) idx <- int()
      if (idx < 1L || idx > length(symbols)) unsupported("unsupported reference")
      symbols[[idx]]
    } else {
      unsupported("unsupported tag")
    }
  }
  strings <- function() {
    n <- int()
    if (n < 0L || n > max_strings) unsupported("vector too long to inspect")
    vapply(seq_len(n), function(i) charsxp(), "")
  }
  attributes_list <- function() {
    out <- list()
    repeat {
      flags <- int()
      type <- type_of(flags)
      if (type == 254L) break
      if (type != 2L || !has_tag(flags) || has_attr(flags)) unsupported("unsupported attributes")
      nm <- tag()
      vflags <- int()
      if (type_of(vflags) != 16L || has_attr(vflags)) unsupported("unsupported attribute value")
      out[[nm]] <- strings()
    }
    out
  }

  parsed <- tryCatch({
    magic <- readChar(con, 5L, useBytes = TRUE)
    if (!length(magic) || !magic %in% c("RDX3\n", "RDX2\n")) {
      unsupported("not an R data file")
    }
    if (!identical(readChar(con, 2L, useBytes = TRUE), "X\n")) {
      unsupported("not an XDR-format R data file")
    }
    version <- int()
    int()
    int()
    if (version == 3L) bytes(int())
    first <- int()
    if (type_of(first) == 254L) {
      list(names = character(), single = FALSE, kind = "none", value = NULL, attributes = list())
    } else {
      if (type_of(first) != 2L || !has_tag(first) || has_attr(first)) {
        unsupported("unexpected file layout")
      }
      object_name <- tag()
      vflags <- int()
      body <- tryCatch({
        if (type_of(vflags) != 16L) {
          list(kind = paste0("type ", type_of(vflags)), complete = FALSE)
        } else {
          value <- strings()
          attrs <- if (has_attr(vflags)) attributes_list() else list()
          list(kind = "character", value = value, attributes = attrs, complete = TRUE)
        }
      }, rda_unsupported = function(e) list(kind = "character", complete = FALSE))
      single <- if (isTRUE(body$complete)) {
        tryCatch(type_of(int()) == 254L, rda_unsupported = function(e) NA)
      } else {
        NA
      }
      list(names = object_name, single = single, kind = body$kind,
           value = body$value, attributes = body$attributes %||% list())
    }
  }, rda_unsupported = function(e) conditionMessage(e),
     error = function(e) paste0("not readable (", conditionMessage(e), ")"))

  if (is.character(parsed)) {
    return(list(readable = FALSE, reason = parsed))
  }
  c(list(readable = TRUE), parsed)
}

`%||%` <- function(x, y) if (is.null(x)) y else x
