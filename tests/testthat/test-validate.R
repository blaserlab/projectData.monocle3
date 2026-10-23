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
  dir.create(file.path(dir, "bpcells_matrix_dir"))
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
