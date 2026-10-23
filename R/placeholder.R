# The `data/<name>.rda` placeholder written for every saved CDS.
#
# Its instructions must be legible with base R printing alone, for someone who
# has neither projectData nor this package installed. So the object is a plain
# character vector with one element per instruction and no S3 print method; the
# class and the `object_name` and `package` attributes are only there so that
# tools (see `placeholder_recognizers()`) can identify it.

placeholder_class <- "projectData_monocle3_placeholder"

make_placeholder <- function(name, package) {
  structure(
    c(
      dataset = name,
      package = package,
      status = "This object is a placeholder, not the actual Monocle 3 cell_data_set.",
      storage = "The real dataset is stored separately in disk-backed Monocle 3 format.",
      step_1 = sprintf("Remove this placeholder from the global environment: rm(%s)", name),
      step_2 = sprintf("Attach the data package: projectData::data_attach(\"%s\")", package),
      step_3 = sprintf("Use the real dataset: %s", name),
      requires = "Required packages: projectData, projectData.monocle3",
      install = "Install if missing: remotes::install_github(\"blaserlab/projectData.monocle3\")"
    ),
    class = placeholder_class,
    object_name = name,
    package = package
  )
}

# Version 2 serialization keeps the file free of encoding and R-version
# requirements; the content is plain ASCII.
write_placeholder <- function(path, name, package) {
  env <- new.env(parent = emptyenv())
  assign(name, make_placeholder(name, package), envir = env)
  save(list = name, envir = env, file = path, version = 2)
  invisible(path)
}
