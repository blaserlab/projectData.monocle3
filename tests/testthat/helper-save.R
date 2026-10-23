# Helpers for the save_monocle_cds() tests. Real CDS objects are restored from
# the fixtures built in helper-fixtures.R; everything destructive happens in
# disposable package source trees.

# A BPCells-backed CDS restored from a fixture, cached for the test run.
# `expected` values of the fixture are in cds_fixtures()[[which]]$expected.
fixture_bpcells_cds <- function(which = "human") {
  key <- paste0("bp_", which)
  if (is.null(fixture_cache[[key]])) {
    dir <- tempfile("pdm3-load-")
    dir.create(dir)
    withr::defer(unlink(dir, recursive = TRUE), envir = testthat::teardown_env())
    matrix_control <- monocle3::set_matrix_control(list(
      matrix_class = "BPCells", matrix_mode = "dir", matrix_path = dir
    ))
    fixture_cache[[key]] <- with_attached("monocle3", suppressMessages(
      monocle3::load_monocle_objects(cds_fixtures()[[which]]$saved,
                                     matrix_control = matrix_control)
    ))
  }
  fixture_cache[[key]]
}

# The same CDS (metadata and reductions included) with in-memory counts.
fixture_memory_cds <- function(which = "human") {
  key <- paste0("mem_", which)
  if (is.null(fixture_cache[[key]])) {
    fixture_cache[[key]] <- with_attached("monocle3", suppressMessages(
      monocle3::convert_counts_matrix(fixture_bpcells_cds(which),
                                      list(matrix_class = "dgCMatrix"))
    ))
  }
  fixture_cache[[key]]
}

# Runs save_monocle_cds() silently, returning the result and the warnings.
save_quiet <- function(...) {
  warnings <- list()
  result <- withCallingHandlers(
    suppressMessages(save_monocle_cds(...)),
    warning = function(w) {
      warnings[[length(warnings) + 1L]] <<- w
      invokeRestart("muffleWarning")
    }
  )
  list(result = result, warnings = warnings)
}

# A data-package source tree with an ordinary dataset in data/.
new_save_pkg <- function(name = "savedata", env = parent.frame()) {
  pkg <- new_pkg_source(name, env = env)
  ordinary_data <- data.frame(letters = letters[1:10])
  add_rda(pkg, "ordinary_data", list(ordinary_data = ordinary_data))
  pkg
}

# Restores a saved resource of a source tree the way the loader does, into a
# disposable work directory.
open_saved <- function(pkg, name, env = parent.frame()) {
  work <- withr::local_tempdir(.local_envir = env)
  open_monocle_cds(
    list(resource = name, objects = name),
    list(source = file.path(pkg, "inst", "extdata", name), work_dir = work),
    list()
  )[[name]]
}

stage_dirs <- function(pkg) {
  list.files(pkg, pattern = "^\\.projectData\\.monocle3-stage", all.files = TRUE)
}

# Loads data/<name>.rda into a fresh environment and returns the object.
load_placeholder <- function(pkg, name) {
  env <- new.env()
  loaded <- load(file.path(pkg, "data", paste0(name, ".rda")), envir = env)
  list(names = loaded, object = env[[name]])
}

save_other_entry <- c(
  "Resource: other_res", "Loader: other::loader", "Source: extdata/other_thing",
  "Objects: other_obj", "Title: Hand-written title"
)

install_source_pkg <- function(pkg, env = parent.frame()) {
  lib <- withr::local_tempdir(.local_envir = env)
  out <- system2(file.path(R.home("bin"), "R"),
                 c("CMD", "INSTALL", "--no-test-load", "-l", shQuote(lib), shQuote(pkg)),
                 stdout = TRUE, stderr = TRUE)
  if (!file.exists(file.path(lib, basename(pkg), "DESCRIPTION"))) {
    stop("installation failed:\n", paste(out, collapse = "\n"))
  }
  lib
}
