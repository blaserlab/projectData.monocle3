# Tests of the integration-test gating in helper-integration.R itself.

test_that("PDM3_INTEGRATION_TESTS selects the mode and rejects unknown values", {
  skip_if_not_installed("withr")
  for (value in c("", "false", "FALSE")) {
    withr::local_envvar(PDM3_INTEGRATION_TESTS = value)
    expect_false(integration_mode())
  }
  withr::local_envvar(PDM3_INTEGRATION_TESTS = "true")
  expect_true(integration_mode())
  withr::local_envvar(PDM3_INTEGRATION_TESTS = "1")
  expect_error(integration_mode(), class = "projectData.monocle3_integration_config")
})

test_that("a problem skips in ordinary mode and is an error in full mode", {
  skip_if_not_installed("withr")
  withr::local_envvar(PDM3_INTEGRATION_TESTS = "false")
  expect_null(integration_gate(character()))
  outcome <- tryCatch(integration_gate("fixture missing"), skip = function(cnd) "skipped")
  expect_identical(outcome, "skipped")

  withr::local_envvar(PDM3_INTEGRATION_TESTS = "true")
  expect_null(integration_gate(character()))
  err <- tryCatch(integration_gate(c("fixture missing", "BPCells missing")),
                  skip = function(cnd) "skipped", error = function(cnd) cnd)
  expect_s3_class(err, "projectData.monocle3_integration_prerequisite")
  expect_match(conditionMessage(err), "fixture missing", fixed = TRUE)
  expect_match(conditionMessage(err), "BPCells missing", fixed = TRUE)
})

test_that("platform skips stay skips and are labelled in a full run", {
  skip_if_not_installed("withr")
  here <- if (.Platform$OS.type == "windows") "windows" else "linux"
  reason <- function() {
    tryCatch(skip_on_platform(c("windows", "mac", "linux", "solaris"), "demo"),
             skip = function(cnd) conditionMessage(cnd))
  }
  withr::local_envvar(PDM3_INTEGRATION_TESTS = "false")
  expect_false(grepl("full integration", reason(), fixed = TRUE))
  withr::local_envvar(PDM3_INTEGRATION_TESTS = "true")
  expect_match(reason(), "[full integration: platform skip]", fixed = TRUE)
  expect_match(reason(), "demo", fixed = TRUE)
})

test_that("the fixture source tree is only searched beside the package in ordinary mode", {
  skip_if_not_installed("withr")
  withr::local_envvar(PDM3_TESTDATA_SOURCE = "/nonexistent/path", PDM3_INTEGRATION_TESTS = "true")
  expect_null(testdata_source())
  expect_match(testdata_source_problems(), "PDM3_TESTDATA_SOURCE must point to")
})

# Registered only in a full run: reports every unmet prerequisite at once, even
# if no other test would reach them.
if (integration_mode()) {
  test_that("full integration prerequisites are met", {
    problems <- full_run_problems()
    expect(!length(problems), paste0("unmet prerequisites:\n  - ", paste(problems, collapse = "\n  - ")))
  })
}
