is_scalar_string <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
}

# Evaluates `expr` with `pkg` attached, then detaches whatever this call newly
# attached (the package and its Depends), leaving the user's search path as it
# was. Namespaces stay loaded; only the search path is restored.
with_attached <- function(pkg, expr) {
  before <- search()
  on.exit({
    added <- setdiff(search(), before)
    for (p in added) {
      try(detach(p, character.only = TRUE), silent = TRUE)
    }
  }, add = TRUE)
  if (!paste0("package:", pkg) %in% before) {
    suppressPackageStartupMessages(
      library(pkg, character.only = TRUE, quietly = TRUE, warn.conflicts = FALSE)
    )
  }
  expr
}
