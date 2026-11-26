# Fails unless every runtime package of the self-contained integration tests can
# be loaded, and prints the environment (versions, Bioconductor, platform). Run
# by CI after installing dependencies and before the tests, so a missing package
# is an installation failure, not a skipped test.
#
#   Rscript tools/verify-stack.R

required <- c("projectData", "monocle3", "BPCells", "SingleCellExperiment",
              "SummarizedExperiment", "Matrix", "testthat", "withr", "pkgload",
              "callr", "rcmdcheck")
# knitr and rmarkdown are only needed for vignettes, which the package has none of
# beyond what check builds; they are reported but not required here.
optional <- c("knitr", "rmarkdown", "DelayedArray", "S4Vectors", "BiocManager")

load_ok <- vapply(required, function(p) {
  tryCatch({
    suppressPackageStartupMessages(loadNamespace(p))
    TRUE
  }, error = function(e) {
    message("cannot load '", p, "': ", conditionMessage(e))
    FALSE
  })
}, NA)

version <- function(p) {
  if (nzchar(system.file(package = p))) as.character(packageVersion(p)) else "not installed"
}
sha <- function(p) {
  s <- packageDescription(p)$RemoteSha
  if (is.null(s)) "" else paste0(" @", substr(s, 1, 7))
}
bioc <- if (requireNamespace("BiocManager", quietly = TRUE)) as.character(BiocManager::version()) else "unknown"

lines <- c(
  paste("R:", R.version.string),
  paste("Platform:", R.version$platform, "|", utils::sessionInfo()$running),
  paste("Bioconductor:", bioc),
  paste("Repositories:", paste(getOption("repos"), collapse = ", ")),
  sprintf("%-22s %s%s%s", c(required, optional),
          vapply(c(required, optional), version, ""),
          vapply(c(required, optional), function(p) if (nzchar(system.file(package = p))) sha(p) else "", ""),
          ifelse(c(required, optional) %in% names(load_ok)[!load_ok], "  (FAILS TO LOAD)", ""))
)
cat(lines, sep = "\n")
summary_file <- Sys.getenv("GITHUB_STEP_SUMMARY")
if (nzchar(summary_file)) cat(c("```", lines, "```", ""), file = summary_file, sep = "\n", append = TRUE)

if (!all(load_ok)) stop("Required packages missing or broken: ", paste(names(load_ok)[!load_ok], collapse = ", "))
