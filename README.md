# projectData.monocle3

<!-- badges: start -->
<!-- badges: end -->

`projectData.monocle3` is an adapter for [projectData](https://github.com/blaserlab/projectData).
It lets a data package ship a saved, disk-backed Monocle 3 `cell_data_set`
(CDS) and have `projectData` restore it on first access, without attaching
Monocle 3 or this package.

Status: **phase 1 (loading) plus manifest registration.** `save_monocle_cds()`
and placeholder generation are not implemented yet.

## Installation

None of the dependencies below are on CRAN. Install them from GitHub:

``` r
install.packages("pak")
pak::pak(c(
  "blaserlab/projectData",
  "bnprks/BPCells/r",
  "cole-trapnell-lab/monocle3",
  "blaserlab/projectData.monocle3"
))
```

`monocle3` and `BPCells` are listed in `Suggests` (and `Remotes`) so that
resource validation and registration work without them; opening a CDS requires
both and fails with an explicit message if they are missing.

## Using a data package that ships a CDS

``` r
library(projectData)
data_attach("my.datapkg")   # registers; reads nothing
human_cds <- data_get("human_cds")   # first access: validates, then opens
```

There is no `library(projectData.monocle3)`. The data package's manifest names
the adapter, and `projectData` loads its namespace (without attaching it) on
first access of an object that needs it.

## Authoring a data package

Save a CDS whose counts are a BPCells on-disk matrix. Use `archive_type =
"none"` so the directory itself ships, not a tar file, and give the data
package a matching `data/human_cds.rda` placeholder (the historical
placeholder is the string `"This is a placeholder object."`):

``` r
library(monocle3)
cds <- convert_counts_matrix(cds, matrix_control = list(matrix_class = "BPCells"))
save_monocle_objects(cds, "inst/extdata/human_cds",
                     archive_control = list(archive_type = "none"))
```

Then register everything in `inst/projectData/manifest.dcf` with one call from
the package source directory:

``` r
projectData.monocle3::write_monocle_manifest(
  package_dir = "."
)
```

This is a package-authoring step; installed packages never generate manifests.
It finds each saved CDS directory under `inst/extdata/` that has a matching
placeholder in `data/` (ordinary `.rda` datasets and other directories are
ignored), and adds or updates its manifest entry. It reports what was added,
updated, unchanged, skipped (for example a CDS with no placeholder, or a `.rda`
that holds real data) or in conflict (a resource already assigned to another
loader, which is left alone). Entries for other loaders are preserved, running
it again changes nothing, and no CDS is loaded or BPCells file created. See
`?write_monocle_manifest` for details.

The future `save_monocle_cds()` will save the CDS, create the placeholder and
invoke this same registration logic automatically.

### The manifest it writes

The result is the same file you could write by hand. `Source` is the
**installed** layout (`extdata/...`, not `inst/extdata/...`):

```
ManifestVersion: 1

Resource: human_cds
Loader: projectData.monocle3::cds
Source: extdata/human_cds
Objects: human_cds
AdapterPackage: projectData.monocle3
AdapterExport: projectData_loaders
RecordedClass: cell_data_set
HelpTopic: human_cds
```

(`AdapterExport: projectData_loaders` is the default, so the generated file
omits that line; it means the same.) Each resource must declare exactly one
object. Add `projectData.monocle3` to the data package's `Suggests` (and
`Remotes`).

## What the loader does

* **validate** (at registration if the loader is already registered, and
  before every uncached open): checks that the `Source` directory has a
  `file_index.rds` written by `save_monocle_objects()`, exactly one rds-format
  CDS, exactly one BPCells matrix directory, relative paths only, and that every
  listed file exists. It does not build the CDS or read matrix data. CDS saved
  with in-memory counts or `hdf5_assays = TRUE` are rejected with an explanation.
* **open**: calls `monocle3::load_monocle_objects()` on the installed directory
  with `matrix_control$matrix_path` set to the unique `paths$work_dir` that
  `projectData` allocated, then checks the result is a valid `cell_data_set`.

### Where the files go

Verified with monocle3 1.4.27 and BPCells 0.3.0:

* `load_monocle_objects()` does not use the installed BPCells directory in
  place. It **copies** it. `matrix_path` must already exist; monocle3 creates
  uniquely named `monocle.bpcells.<date>.<id>.tmp` children in it, so
  `paths$work_dir` is passed directly (no extra subdirectory). Two copies are
  made: the counts and a row-ordered copy kept in the `counts_row_order` assay.
* Without `matrix_path`, the default is `"."`, the working directory. The
  adapter always sets it, never calls `setwd()`, and nothing is written to
  `getwd()`.
* monocle3 removes those directories when R exits (its own exit hook). The
  adapter never deletes them. The work directory is under the session
  temporary directory.
* `load_monocle_objects()` calls `SummarizedExperiment` generics unqualified,
  so monocle3 (and its `Depends`) must be attached while it runs. The adapter
  attaches monocle3 for that one call and restores the search path afterwards.
  You will still need `library(monocle3)` to use monocle3 functions on the
  result.

### Independence from the installed package

The restored counts and the row-ordered copy live under `work_dir`, so
removing the installed data package does not affect them. The UMAP
nearest-neighbour index is different: Annoy memory-maps it from the installed
file. A test removes the installation on Linux and confirms
`preprocess_transform()` and `reduce_dimension_transform()` (which use the PCA
model and the UMAP index) still work, since an unlinked file stays mapped.
That is platform behaviour, not a guarantee: do not replace or truncate an
installed package in place while a CDS from it is in use, and on Windows the
installation cannot be removed while the index is mapped. The CDS also records
the original install path as model-identity metadata; nothing reads it.
PCA/other reduction models stored in the CDS object itself are in memory.
Only the default (`"counts"`) assay is verified. Other assays are not
tested yet.

## Development

``` r
devtools::test()   # integration tests need monocle3, BPCells, SingleCellExperiment, SummarizedExperiment
```

Tests build two small real CDS fixtures in a subprocess (about 20 seconds)
and install them into throwaway libraries. The end-to-end manifest test copies
the source of `projectData.monocle3.testdata` (found through the
`PDM3_TESTDATA_SOURCE` environment variable, or as a sibling directory of this
package) and skips if it is unavailable.
