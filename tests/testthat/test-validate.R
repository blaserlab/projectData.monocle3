# validate_monocle_cds() works on file structure only, so these tests use
# synthetic directories and need neither monocle3 nor BPCells.

descriptor <- function(source = "extdata/cds", objects = "cds") {
  list(resource = "cds", loader = "projectData.monocle3::cds", source = source,
       objects = objects)
}

write_index <- function(dir, files, save_function = "save_monocle_objects") {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(list(save_function = save_function, files = files),
          file.path(dir, "file_index.rds"))
}

good_files <- function() {
  data.frame(
    cds_object = c("cds", "bpcells_matrix_dir", "reduce_dim_aux"),
    file_format = c("rds", "BPCells:MatrixDir", "umap_annoy_index"),
    file_path = c("cds_object.rds", "bpcells_matrix_dir", "umap.idx")
  )
}

local_saved_dir <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  dir <- file.path(root, "extdata", "cds")
  write_index(dir, good_files())
  writeLines("x", file.path(dir, "cds_object.rds"))
  writeLines("x", file.path(dir, "umap.idx"))
  make_fake_matrix_dir(file.path(dir, "bpcells_matrix_dir"))
  root
}

test_that("a plausible saved structure validates without reading data", {
  skip_if_not_installed("withr")
  root <- local_saved_dir()
  expect_true(validate_monocle_cds(descriptor(), root, list()))
})

test_that("structural problems return informative messages", {
  skip_if_not_installed("withr")
  msg <- function(root, d = descriptor()) validate_monocle_cds(d, root, list())

  root <- local_saved_dir()
  expect_match(msg(root, descriptor(source = NA_character_)), "Source")
  expect_match(msg(root, descriptor(objects = c("a", "b"))), "exactly one object")
  expect_match(msg(root, descriptor(objects = NULL)), "exactly one object")
  expect_match(msg(root, descriptor(source = "extdata/nope")), "does not exist")

  root <- local_saved_dir()
  unlink(file.path(root, "extdata", "cds", "file_index.rds"))
  file.create(file.path(root, "extdata", "cds", "cds.tar"))
  expect_match(msg(root), "no file_index.rds")
  expect_match(msg(root), "archive_type")

  root <- local_saved_dir()
  writeLines("not rds", file.path(root, "extdata", "cds", "file_index.rds"))
  expect_match(msg(root), "cannot read")

  root <- local_saved_dir()
  write_index(file.path(root, "extdata", "cds"), good_files(), save_function = "other")
  expect_match(msg(root), "not written by")

  root <- local_saved_dir()
  unlink(file.path(root, "extdata", "cds", "umap.idx"))
  expect_match(msg(root), "missing saved file.*umap.idx")

  root <- local_saved_dir()
  files <- good_files()[c(1, 3), ]
  write_index(file.path(root, "extdata", "cds"), files)
  expect_match(msg(root), "not a disk-backed CDS")

  root <- local_saved_dir()
  files <- good_files()
  files$file_format[1] <- "hdf5"
  write_index(file.path(root, "extdata", "cds"), files)
  expect_match(msg(root), "rds format")

  root <- local_saved_dir()
  files <- good_files()
  files$file_path[3] <- "../outside.idx"
  write_index(file.path(root, "extdata", "cds"), files)
  expect_match(msg(root), "not relative")

  root <- local_saved_dir()
  unlink(file.path(root, "extdata", "cds", "bpcells_matrix_dir"), recursive = TRUE)
  file.create(file.path(root, "extdata", "cds", "bpcells_matrix_dir"))
  expect_match(msg(root), "not a directory")
})

test_that("malformed index columns fail with validation messages", {
  skip_if_not_installed("withr")
  msg <- function(root) validate_monocle_cds(descriptor(), root, list())
  with_files <- function(modify) {
    root <- local_saved_dir(parent.frame())
    files <- good_files()
    files <- modify(files)
    write_index(file.path(root, "extdata", "cds"), files)
    msg(root)
  }

  expect_match(with_files(function(f) { f$file_path <- factor(f$file_path); f }),
               "`file_path` must be character, not <factor>")
  expect_match(with_files(function(f) { f$file_format <- 1:3; f }),
               "`file_format` must be character, not <integer>")
  expect_match(with_files(function(f) { f$cds_object <- as.list(f$cds_object); f }),
               "`cds_object` must be character")
  expect_match(with_files(function(f) { f$cds_object[2] <- NA; f }),
               "`cds_object` has missing or empty")
  expect_match(with_files(function(f) { f$file_format[1] <- NA; f }),
               "`file_format` has missing or empty")
  expect_match(with_files(function(f) { f$file_path[3] <- NA; f }),
               "`file_path` has missing or empty")
  expect_match(with_files(function(f) { f$file_path[3] <- ""; f }),
               "`file_path` has missing or empty")
  expect_match(with_files(function(f) { f$file_path[3] <- "cds_object.rds"; f }),
               "more than once")
  expect_match(with_files(function(f) { f$file_path[3] <- "/etc/passwd"; f }),
               "not relative")
  expect_match(with_files(function(f) f[0, ]), "does not list any saved files")
})

test_that("invalid CDS entries fail without incidental errors", {
  skip_if_not_installed("withr")
  msg <- function(root) validate_monocle_cds(descriptor(), root, list())
  root <- local_saved_dir()
  files <- good_files()
  files$cds_object[1] <- "other"
  write_index(file.path(root, "extdata", "cds"), files)
  expect_match(msg(root), "exactly one CDS")

  root <- local_saved_dir()
  files <- rbind(good_files(), data.frame(cds_object = "cds", file_format = "rds",
                                          file_path = "umap.idx2"))
  write_index(file.path(root, "extdata", "cds"), files)
  expect_match(msg(root), "exactly one CDS")

  root <- local_saved_dir()
  write_index(file.path(root, "extdata", "cds"), "not a list")
  expect_match(msg(root), "does not list any saved files")
  saveRDS(1:3, file.path(root, "extdata", "cds", "file_index.rds"))
  expect_match(msg(root), "not written by")
})

# Symbolic-link and containment behavior is covered in test-filesystem.R.
