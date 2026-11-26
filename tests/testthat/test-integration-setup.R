# Tests of the integration-test gating in helper-integration.R itself. These need
# neither the Monocle stack nor the historical fixtures.

test_that("each switch selects its own mode and rejects unknown values", {
  skip_if_not_installed("withr")
  for (value in c("", "false", "FALSE")) {
    withr::local_envvar(PDM3_INTEGRATION_TESTS = value, PDM3_HISTORICAL_TESTS = value)
    expect_false(integration_mode())
    expect_false(historical_mode())
  }
  withr::local_envvar(PDM3_INTEGRATION_TESTS = "true", PDM3_HISTORICAL_TESTS = "false")
  expect_true(integration_mode())
  expect_false(historical_mode())
  withr::local_envvar(PDM3_INTEGRATION_TESTS = "false", PDM3_HISTORICAL_TESTS = "TRUE")
  expect_false(integration_mode())
  expect_true(historical_mode())

  withr::local_envvar(PDM3_INTEGRATION_TESTS = "1")
  expect_error(integration_mode(), "PDM3_INTEGRATION_TESTS", class = "projectData.monocle3_integration_config")
  withr::local_envvar(PDM3_HISTORICAL_TESTS = "yes")
  expect_error(historical_mode(), "PDM3_HISTORICAL_TESTS", class = "projectData.monocle3_integration_config")
})

test_that("a problem skips in ordinary mode and is an error in strict mode", {
  skip_if_not_installed("withr")
  withr::local_envvar(PDM3_INTEGRATION_TESTS = "false")
  expect_null(integration_gate(character()))
  outcome <- tryCatch(integration_gate("dependency missing"), skip = function(cnd) "skipped")
  expect_identical(outcome, "skipped")

  withr::local_envvar(PDM3_INTEGRATION_TESTS = "true")
  expect_null(integration_gate(character()))
  err <- tryCatch(integration_gate(c("dependency missing", "BPCells missing")),
                  skip = function(cnd) "skipped", error = function(cnd) cnd)
  expect_s3_class(err, "projectData.monocle3_integration_prerequisite")
  expect_match(conditionMessage(err), "PDM3_INTEGRATION_TESTS=true", fixed = TRUE)
  expect_match(conditionMessage(err), "dependency missing", fixed = TRUE)
  expect_match(conditionMessage(err), "BPCells missing", fixed = TRUE)
})

test_that("the historical family is gated by its own switch, independently of the other", {
  skip_if_not_installed("withr")
  gate <- function() {
    tryCatch(historical_gate("fixture package missing"),
             skip = function(cnd) "skipped", error = function(cnd) cnd)
  }
  # Strict self-contained tests do not make a missing fixture package a failure ...
  withr::local_envvar(PDM3_INTEGRATION_TESTS = "true", PDM3_HISTORICAL_TESTS = "false")
  expect_identical(gate(), "skipped")
  # ... and strict historical tests fail without it, naming their own switch.
  withr::local_envvar(PDM3_INTEGRATION_TESTS = "false", PDM3_HISTORICAL_TESTS = "true")
  err <- gate()
  expect_s3_class(err, "projectData.monocle3_integration_prerequisite")
  expect_match(conditionMessage(err), "PDM3_HISTORICAL_TESTS=true", fixed = TRUE)
  expect_match(conditionMessage(err), "[historical fixtures]", fixed = TRUE)
  # The self-contained gate is unaffected by the historical switch.
  withr::local_envvar(PDM3_INTEGRATION_TESTS = "false", PDM3_HISTORICAL_TESTS = "true")
  expect_identical(tryCatch(integration_gate("dependency missing"), skip = function(cnd) "skipped"),
                   "skipped")
})

test_that("a missing fixture package is a historical problem only", {
  skip_if_not_installed("withr")
  withr::local_envvar(PDM3_INTEGRATION_TESTS = "true", PDM3_HISTORICAL_TESTS = "false")
  expect_identical(self_contained_problems(), dependency_problems())
  absent <- "projectData.monocle3.notInstalled"
  expect_match(installed_testdata_problems(strict = TRUE, pkg = absent), "is not installed")
  expect_match(installed_testdata_problems(strict = FALSE, pkg = absent), "is not installed")
})

test_that("platform skips stay skips and are labelled in a strict run", {
  skip_if_not_installed("withr")
  reason <- function() {
    tryCatch(skip_on_platform(c("windows", "mac", "linux", "solaris"), "demo"),
             skip = function(cnd) conditionMessage(cnd))
  }
  withr::local_envvar(PDM3_INTEGRATION_TESTS = "false", PDM3_HISTORICAL_TESTS = "false")
  expect_false(grepl("strict integration", reason(), fixed = TRUE))
  withr::local_envvar(PDM3_INTEGRATION_TESTS = "true")
  expect_match(reason(), "[strict integration: platform skip]", fixed = TRUE)
  expect_match(reason(), "demo", fixed = TRUE)
})

test_that("symbolic-link tests skip only when links are unusable, and say so in a strict run", {
  skip_if_not_installed("withr")
  reason <- function(problems) {
    tryCatch(skip_if_no_symlinks(problems), skip = function(cnd) conditionMessage(cnd))
  }
  unusable <- "a file symbolic link cannot be created"
  withr::local_envvar(PDM3_INTEGRATION_TESTS = "false", PDM3_HISTORICAL_TESTS = "false")
  expect_match(reason(unusable), "cannot be created", fixed = TRUE)
  expect_false(grepl("strict integration", reason(unusable), fixed = TRUE))
  withr::local_envvar(PDM3_INTEGRATION_TESTS = "true")
  expect_match(reason(unusable), "[strict integration: platform skip]", fixed = TRUE)
  # Where links work (Linux and macOS always, Windows with the privilege) nothing is skipped.
  expect_null(reason(character()))
  # The probe itself is a character vector of problems.
  expect_type(symlink_problems(), "character")
})

test_that("subprocess helpers pass the environment portably (system2(env =) is Unix-only)", {
  files <- list.files(test_path(), pattern = "\\.R$", full.names = TRUE)
  files <- files[basename(files) != "test-integration-setup.R"]
  code <- unlist(lapply(files, function(f) {
    lines <- readLines(f, warn = FALSE)
    paste0(basename(f), ":", seq_along(lines), ": ", lines)
  }))
  expect_identical(grep("^\\S+: .*env = paste0\\(\"R_LIBS", code, value = TRUE), character())
  expect_identical(grep("^\\S+: [^#]*system2\\(.*\\benv *=", code, value = TRUE), character())
})

test_that("the fixture source tree is only searched beside the package in ordinary historical mode", {
  skip_if_not_installed("withr")
  withr::local_envvar(PDM3_TESTDATA_SOURCE = "/nonexistent/path", PDM3_HISTORICAL_TESTS = "true")
  expect_null(testdata_source())
  expect_match(testdata_source_problems(), "PDM3_TESTDATA_SOURCE must point to")
})

test_that("the historical fixture identity is a version floor plus content checksums", {
  expect_match(testdata_min_version, "^0\\.0\\.0\\.9\\d+$")
  expect_length(testdata_fingerprint, 2L * length(testdata_cds))
  expect_setequal(unique(dirname(names(testdata_fingerprint))), testdata_cds)
  expect_true(all(nchar(testdata_fingerprint) == 32L))
  # A checksum mismatch or an absent file is not a match.
  expect_identical(identical_checksums(c(a = "x", b = NA), c("x", "y")), c(TRUE, FALSE))
})

# Registered only in a strict run: reports every unmet prerequisite at once, even
# if no other test would reach them.
if (integration_mode()) {
  test_that("strict self-contained integration prerequisites are met", {
    problems <- self_contained_problems()
    expect(!length(problems), paste0("unmet prerequisites:\n  - ", paste(problems, collapse = "\n  - ")))
  })
}
if (historical_mode()) {
  test_that("strict historical integration prerequisites are met", {
    problems <- historical_problems()
    expect(!length(problems), paste0("unmet prerequisites:\n  - ", paste(problems, collapse = "\n  - ")))
  })
}
