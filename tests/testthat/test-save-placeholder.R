# Placeholder construction and recognition. No monocle3 needed.

test_that("the placeholder is a small classed, named character vector with metadata", {
  p <- make_placeholder("cds_main_adults", "myDataPackage")
  expect_type(p, "character")
  expect_s3_class(p, "projectData_monocle3_placeholder")
  expect_identical(attr(p, "object_name"), "cds_main_adults")
  expect_identical(attr(p, "package"), "myDataPackage")
  expect_false(is.null(names(p)))
  expect_false(anyNA(p))
  expect_lt(length(p), 16L)
  expect_false(any(grepl("\n", p, fixed = TRUE)))
  text <- paste(p, collapse = "\n")
  expect_match(text, "placeholder, not the actual", fixed = TRUE)
  expect_match(text, "rm(cds_main_adults)", fixed = TRUE)
  expect_match(text, "projectData::data_attach(\"myDataPackage\")", fixed = TRUE)
  expect_match(text, "projectData.monocle3", fixed = TRUE)
})

test_that("a written placeholder holds exactly one correctly named object and is recognized", {
  pkg <- new_pkg_source()
  dir.create(file.path(pkg, "data"))
  path <- file.path(pkg, "data", "cds_a.rda")
  write_placeholder(path, "cds_a", "fakedata")
  expect_lt(file.size(path), 2000)

  loaded <- load_placeholder(pkg, "cds_a")
  expect_identical(loaded$names, "cds_a")
  expect_identical(loaded$object, make_placeholder("cds_a", "fakedata"))

  info <- inspect_rda(path)
  expect_true(info$readable)
  expect_true(info$single)
  expect_true(is_recognized_placeholder(info, "cds_a"))
  # Identification is tied to the object name.
  expect_false(is_recognized_placeholder(info, "cds_b"))
})

test_that("classed placeholders are recognized only when complete, legacy ones still are", {
  pkg <- new_pkg_source()
  recognized <- function(value, name = "x") {
    add_placeholder(pkg, name, value)
    is_recognized_placeholder(inspect_rda(file.path(pkg, "data", paste0(name, ".rda"))), name)
  }
  good <- make_placeholder("x", "fakedata")
  expect_true(recognized(good))
  expect_true(recognized(legacy_placeholder))

  no_class <- good; class(no_class) <- NULL
  expect_false(recognized(no_class))
  other_class <- good; class(other_class) <- "something_else"
  expect_false(recognized(other_class))
  no_pkg <- good; attr(no_pkg, "package") <- NULL
  expect_false(recognized(no_pkg))
  wrong_name <- good; attr(wrong_name, "object_name") <- "y"
  expect_false(recognized(wrong_name))
  unnamed <- good; names(unnamed) <- NULL
  expect_false(recognized(unnamed))
  expect_false(recognized(c("some", "text")))
  expect_false(recognized(data.frame(a = 1)))
})

test_that("discovery pairs a CDS directory with the new placeholder", {
  pkg <- new_pkg_source()
  add_fake_cds(pkg, "cds_a")
  dir.create(file.path(pkg, "data"))
  write_placeholder(file.path(pkg, "data", "cds_a.rda"), "cds_a", "fakedata")
  found <- discover_monocle_resources(pkg)
  expect_identical(found$status, "discovered")
})

test_that("the placeholder explains itself with base R printing only", {
  skip_on_cran()
  skip_if_not_installed("withr")
  pkg <- new_pkg_source("myDataPackage")
  dir.create(file.path(pkg, "data"))
  path <- file.path(pkg, "data", "cds_main_adults.rda")
  write_placeholder(path, "cds_main_adults", "myDataPackage")

  out <- rscript_output(c(
    sprintf("load(%s)", deparse(path)),
    "print(cds_main_adults)",
    "cat('LOADED:', any(c('projectData', 'projectData.monocle3') %in% loadedNamespaces()), '\\n')"
  ))
  text <- paste(out, collapse = "\n")
  expect_match(text, "cds_main_adults", fixed = TRUE)
  expect_match(text, "not the actual", fixed = TRUE)
  expect_match(text, "rm(cds_main_adults)", fixed = TRUE)
  expect_match(text, "data_attach(\\\"myDataPackage\\\")", fixed = TRUE)
  expect_match(text, "Required packages: projectData, projectData.monocle3", fixed = TRUE)
  expect_match(text, "LOADED: FALSE", fixed = TRUE)
  # Instructions are separate elements, not escaped newlines.
  expect_false(grepl("\\n", text, fixed = TRUE))
  # Printed for the record when running the tests interactively.
  if (interactive()) cat(out, sep = "\n")
})
