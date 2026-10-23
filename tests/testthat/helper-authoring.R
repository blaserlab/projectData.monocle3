# Synthetic data-package source trees for the manifest-authoring tests. None of
# these need monocle3 or BPCells: the loader's validation and discovery read
# only file_index.rds and directory listings.

new_pkg_source <- function(name = "fakedata", env = parent.frame()) {
  skip_if_not_installed("withr")
  root <- withr::local_tempdir(.local_envir = env)
  pkg <- file.path(root, name)
  dir.create(pkg)
  writeLines(c(paste("Package:", name), "Version: 0.0.1", "Title: Fake",
               "Description: Fake.", "License: MIT"),
             file.path(pkg, "DESCRIPTION"))
  pkg
}

fake_files <- function() {
  data.frame(
    cds_object = c("cds", "bpcells_matrix_dir"),
    file_format = c("rds", "BPCells:MatrixDir"),
    file_path = c("cds_object.rds", "bpcells_matrix_dir"),
    stringsAsFactors = FALSE
  )
}

# A directory shaped like the output of save_monocle_objects().
add_fake_cds <- function(pkg, name, files = fake_files(), index = TRUE,
                         save_function = "save_monocle_objects", create = TRUE) {
  dir <- file.path(pkg, "inst", "extdata", name)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  if (index) {
    saveRDS(list(save_function = save_function, files = files),
            file.path(dir, "file_index.rds"))
  }
  if (create) {
    for (p in files$file_path) {
      path <- file.path(dir, p)
      if (identical(files$cds_object[files$file_path == p], "bpcells_matrix_dir")) {
        dir.create(path, showWarnings = FALSE)
      } else {
        writeLines("x", path)
      }
    }
  }
  invisible(dir)
}

# Writes data/<stem>.rda holding `objects` (a named list).
add_rda <- function(pkg, stem, objects, ...) {
  dir.create(file.path(pkg, "data"), showWarnings = FALSE)
  save(list = names(objects), envir = list2env(objects),
       file = file.path(pkg, "data", paste0(stem, ".rda")), ...)
}

legacy_placeholder <- "This is a placeholder object."

add_placeholder <- function(pkg, name, value = legacy_placeholder, ...) {
  add_rda(pkg, name, stats::setNames(list(value), name), ...)
}

# CDS directory plus its legacy placeholder.
add_resource <- function(pkg, name) {
  add_fake_cds(pkg, name)
  add_placeholder(pkg, name)
}

manifest_file <- function(pkg) file.path(pkg, "inst", "projectData", "manifest.dcf")

write_manifest_text <- function(pkg, lines) {
  dir.create(dirname(manifest_file(pkg)), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, manifest_file(pkg))
}

# Resource ids in a manifest, in file order.
manifest_resources <- function(pkg) {
  m <- read.dcf(manifest_file(pkg))
  unname(m[-1, "Resource"])
}

# Quietly runs the authoring call, returning the report and any warnings.
run_write <- function(pkg) {
  warnings <- list()
  report <- withCallingHandlers(
    suppressMessages(write_monocle_manifest(pkg)),
    warning = function(w) {
      warnings[[length(warnings) + 1L]] <<- w
      invokeRestart("muffleWarning")
    }
  )
  list(report = report, warnings = warnings)
}

status_of <- function(report, resource) report$status[report$resource == resource]

file_state <- function(path) {
  files <- list.files(path, recursive = TRUE, all.files = TRUE, full.names = TRUE,
                      include.dirs = TRUE)
  plain <- files[!dir.exists(files)]
  list(files = sub(path, "", files, fixed = TRUE),
       md5 = unname(tools::md5sum(plain)),
       mtime = file.mtime(plain))
}
