library(projectData)
library(SingleCellExperiment)
devtools::load_all()
# blaseRtemplates::install_one_package("projectData.monocle3.testdata")


# tests
data("cds_bpcells_a",
     package = "projectData.monocle3.testdata")

cds_bpcells_a# we still have the old placeholder text in there, but this is expected

rm(cds_bpcells_a)


data_attach("projectData.monocle3.testdata")

cds_bpcells_a
cds_bpcells_b
ordinary_data

data_attach()
data_detach()
cds_bpcells_a
cds_bpcells_b
ordinary_data

data_attach("projectData.monocle3.testdata")
cds_bpcells_a


cds <- projectData::data_get(
  "cds_bpcells_a",
  package = "projectData.monocle3.testdata"
)

mat <- counts(cds)

class(mat)
BPCells::dir(mat)
mat

test_counts <- as.matrix(mat[1:10, 1:10])

stopifnot(
  identical(dim(test_counts), c(10L, 10L)),
  all(is.finite(test_counts))
)

cds <- projectData::data_get(
  "cds_bpcells_a",
  package = "projectData.monocle3.testdata"
)

projectData::data_detach()

# Should still work
counts(cds)[1:5, 1:5]
