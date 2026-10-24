blaseRtemplates::install_one_package("projectData.monocle3.testdata")
library(projectData)
library(SummarizedExperiment)
cds_reloaded <- projectData::data_get(
  "cds_already_bpcells",
  package = "projectData.monocle3.testdata"
)

data_attach("projectData.monocle3.testdata")

# Confirm the counts are still disk-backed
stopifnot(
  methods::is(
    SummarizedExperiment::assay(cds_reloaded, "counts"),
    "IterableMatrix"
  )
)

# Test alternate experiment preservation
compare_alt_exps(cds_multiassay, cds_reloaded)

# Test the main biological assays
for (nm in c("counts", "logcounts", "spliced")) {
  stopifnot(
    isTRUE(all.equal(
      as.matrix(assay(cds_multiassay, nm)),
      as.matrix(assay(cds_reloaded, nm)),
      check.attributes = FALSE
    ))
  )
}
