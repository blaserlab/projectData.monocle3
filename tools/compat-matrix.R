# Runs the whole test suite once per entry of the compatibility matrix, each in
# a clean R process with its own library path, and prints what was verified.
#
#   Rscript tools/compat-matrix.R                     # every configuration
#   Rscript tools/compat-matrix.R current legacy
#   Rscript tools/compat-matrix.R --historical current  # also the historical fixtures
#   Rscript tools/compat-matrix.R --list
#
# Alternative libraries are built by tools/compat-libs.R into
# tools/compat-libs/<name>; a configuration whose library is missing is reported
# as NOT RUN. The suite runs with PDM3_INTEGRATION_TESTS=true (a missing
# dependency or an unavailable self-contained test is a failure, never a skip),
# NOT_CRAN=true, and the versions found must match the ones declared below.
#
# Status per configuration:
#   FAILED               any failure or error, or a package version other than declared
#   NOT VERIFIED (skips) any skip other than a labelled platform skip
#   VERIFIED             everything else
# Platform skips (reason starts with "[strict integration: platform skip]") are
# always printed. The status says nothing about configurations that were not run.
#
# Exit status is 0 only if every requested configuration is VERIFIED.

root <- normalizePath(
  if (file.exists("DESCRIPTION")) "." else file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), ".."),
  winslash = "/"
)

# `libs`: library directories put in front of the default path (relative to
# `root`); `expect`: version prefixes the run must find. The default library
# is expected to hold monocle3 1.4.27 and BPCells 0.3.1 (see
# .github/workflows/R-CMD-check.yaml); projectData comes from CRAN unless a
# library overrides it.
configs <- list(
  # Whatever is in the default library: CRAN projectData, monocle3 from
  # GitHub, BPCells at the release tag named in DESCRIPTION Remotes.
  current = list(
    libs = character(),
    expect = c(projectData = "0.1.0", monocle3 = "1.4.27", BPCells = "0.3.1")
  ),
  # The stack of the Issue 3 report: an older BPCells and a projectData
  # development version.
  legacy = list(
    libs = c("tools/compat-libs/projectdata_9008", "tools/compat-libs/bpcells_030"),
    expect = c(projectData = "0.0.0.9008", monocle3 = "1.4.27", BPCells = "0.3.0")
  ),
  bpcells_030 = list(
    libs = c("tools/compat-libs/projectdata_cran", "tools/compat-libs/bpcells_030"),
    expect = c(projectData = "0.1.0", monocle3 = "1.4.27", BPCells = "0.3.0")
  ),
  bpcells_031 = list(
    libs = c("tools/compat-libs/projectdata_cran", "tools/compat-libs/bpcells_031"),
    expect = c(projectData = "0.1.0", monocle3 = "1.4.27", BPCells = "0.3.1")
  ),
  # The oldest projectData the DESCRIPTION allows would need its own entry once
  # it can be installed from a reproducible source.
  # BPCells' main branch, whatever version it is. Early warning only.
  bpcells_main = list(
    libs = c("tools/compat-libs/projectdata_cran", "tools/compat-libs/bpcells_main"),
    expect = c(projectData = "0.1.0", monocle3 = "1.4.27")
  )
)

platform_skip_prefix <- "[strict integration: platform skip]"

args <- commandArgs(trailingOnly = TRUE)
if ("--list" %in% args) {
  print(names(configs))
  quit(status = 0)
}
historical <- "--historical" %in% args
args <- setdiff(args, "--historical")
selected <- if (length(args)) args else setdiff(names(configs), "bpcells_main")
unknown <- setdiff(selected, names(configs))
if (length(unknown)) stop("unknown configuration(s): ", paste(unknown, collapse = ", "))

run_config <- function(name) {
  cfg <- configs[[name]]
  libs <- if (length(cfg$libs)) file.path(root, cfg$libs) else character()
  absent <- libs[!dir.exists(libs)]
  if (length(absent)) {
    return(list(name = name, status = "NOT RUN", note = paste("missing library:", absent[1])))
  }
  env <- c(callr::rcmd_safe_env(), NOT_CRAN = "true", PDM3_INTEGRATION_TESTS = "true",
           PDM3_HISTORICAL_TESTS = if (historical) "true" else "false")
  if (historical && !nzchar(Sys.getenv("PDM3_TESTDATA_SOURCE"))) {
    stop("--historical needs PDM3_TESTDATA_SOURCE (the projectData.monocle3.testdata source tree).")
  }
  if (historical) env <- c(env, PDM3_TESTDATA_SOURCE = Sys.getenv("PDM3_TESTDATA_SOURCE"))
  res <- callr::r(
    function(root) {
      pkgs <- c("projectData", "monocle3", "BPCells", "SingleCellExperiment",
                "SummarizedExperiment", "Matrix", "testthat", "pkgload", "withr")
      versions <- vapply(pkgs, function(p) as.character(utils::packageVersion(p)), "")
      # Packages installed from a git ref rather than a tag carry a RemoteSha.
      sha <- function(p) {
        s <- utils::packageDescription(p)$RemoteSha
        if (is.null(s)) NA_character_ else substr(s, 1, 7)
      }
      bioc <- if (requireNamespace("BiocManager", quietly = TRUE)) {
        as.character(BiocManager::version())
      } else NA_character_
      r <- testthat::test_local(root, reporter = "silent", stop_on_failure = FALSE,
                                stop_on_warning = FALSE)
      df <- as.data.frame(r)
      collect <- function(class, fn) unlist(lapply(r, function(f) {
        unlist(lapply(f$results, function(x) if (inherits(x, class)) fn(f, x)))
      }))
      list(
        versions = versions, shas = c(monocle3 = sha("monocle3"), BPCells = sha("BPCells")),
        bioc = bioc, r = R.version.string, os = utils::sessionInfo()$running,
        libpaths = .libPaths(),
        tests = nrow(df), expectations = sum(df$nb), failed = sum(df$failed),
        errors = sum(df$error), skipped = sum(df$skipped), warnings = sum(df$warning),
        skips = collect("expectation_skip", function(f, x) conditionMessage(x)),
        problems = collect(c("expectation_failure", "expectation_error"), function(f, x) {
          paste0(f$test, ": ", substr(gsub("\\s+", " ", conditionMessage(x)), 1, 1500))
        })
      )
    },
    args = list(root), libpath = c(libs, .libPaths()), env = env,
    show = FALSE, spinner = FALSE
  )
  found <- res$versions[names(cfg$expect)]
  wrong <- names(cfg$expect)[!startsWith(found, cfg$expect)]
  # testthat reports a skip as "Reason: <message>".
  skips <- sub("^Reason: ", "", as.character(res$skips))
  # Without --historical the historical fixture tests skip by design.
  allowed <- c(platform_skip_prefix, if (!historical) "[historical fixtures]")
  unexpected <- skips[!vapply(skips, function(s) any(startsWith(s, allowed)), NA)]
  status <- if (res$failed > 0 || res$errors > 0 || length(wrong)) {
    "FAILED"
  } else if (res$skipped > 0 && length(unexpected) > 0) {
    "NOT VERIFIED (skips)"
  } else {
    "VERIFIED"
  }
  c(list(name = name, status = status, wrong_versions = wrong, historical = historical), res)
}

results <- lapply(selected, function(n) {
  message("== ", n)
  tryCatch(run_config(n), error = function(e) list(name = n, status = "ERROR", note = conditionMessage(e)))
})

report <- unlist(lapply(results, function(r) {
  head <- sprintf("%s: %s%s", r$name, r$status, if (isTRUE(r$historical)) " (+ historical fixtures)" else "")
  if (is.null(r$versions)) return(c(head, paste0("   ", r$note)))
  v <- r$versions
  c(
    head,
    sprintf("   %s | %s | Bioconductor %s", r$r, r$os, r$bioc),
    sprintf("   projectData %s | monocle3 %s%s | BPCells %s%s | SCE %s | SE %s | Matrix %s",
            v[["projectData"]], v[["monocle3"]],
            if (is.na(r$shas[["monocle3"]])) "" else paste0(" @", r$shas[["monocle3"]]),
            v[["BPCells"]], if (is.na(r$shas[["BPCells"]])) "" else paste0(" @", r$shas[["BPCells"]]),
            v[["SingleCellExperiment"]], v[["SummarizedExperiment"]], v[["Matrix"]]),
    sprintf("   %d tests, %d expectations, %d failed, %d errors, %d skipped, %d warnings",
            r$tests, r$expectations, r$failed, r$errors, r$skipped, r$warnings),
    if (length(r$wrong_versions)) paste("   version mismatch with the declared stack:", paste(r$wrong_versions, collapse = ", ")),
    if (length(r$problems)) paste0("   - ", r$problems),
    if (length(r$skips)) paste("   skips:", paste(unique(r$skips), collapse = " | "))
  )
}))
cat(report, sep = "\n")
summary_file <- Sys.getenv("GITHUB_STEP_SUMMARY")
if (nzchar(summary_file)) cat(c("```", report, "```", ""), file = summary_file, sep = "\n", append = TRUE)
quit(status = as.integer(!all(vapply(results, function(r) identical(r$status, "VERIFIED"), NA))))
