# projectData.monocle3

<!-- badges: start -->
<!-- badges: end -->

`projectData.monocle3` is an adapter for [projectData](https://github.com/blaserlab/projectData).
It lets a data package ship a saved, disk-backed Monocle 3 `cell_data_set`
(CDS) and have `projectData` restore it on first access, without attaching
Monocle 3 or this package.

Current functionality:

* `save_monocle_cds()` saves a CDS into a data package source tree, converting
  in-memory counts to BPCells automatically and keeping counts that are already
  BPCells-backed as they are.
* A mandatory, informational `.rda` placeholder is written for every saved CDS,
  so `data()` and roxygen documentation behave conventionally.
* The `projectData` manifest is generated and reconciled automatically.
* The CDS is loaded lazily, on first access, through `projectData::data_attach()`;
  restored BPCells files go to the working directory managed by `projectData`
  (session-temporary by default; no persistent cache).
* In-memory additional assays and alternative experiments are preserved.
* **Limitation:** assays that are independently disk-backed (BPCells or
  delayed), in the main CDS or inside any alternative experiment, are rejected
  at save time because Monocle would store only a reference to files that are
  not part of the data package.

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

Minimal workflow:

``` r
projectData.monocle3::save_monocle_cds(
  cds,
  name = "example_cds",
  package_dir = "."
)
```

then, after documenting the dataset and installing the package:

``` r
projectData::data_attach("myDataPackage")
example_cds
```

Ordinary `data("example_cds")` retrieves only an informational placeholder, not
the CDS.

In more detail: from the root of the data package source directory, one call saves the CDS,
writes the placeholder and registers the resource:

``` r
projectData.monocle3::save_monocle_cds(
  cds_main_adults,                  # a monocle3 cell_data_set
  name = "cds_main_adults",
  package_dir = ".",
  overwrite = FALSE
)
```

This creates

```
data/cds_main_adults.rda                 placeholder (one classed character vector)
inst/extdata/cds_main_adults/            native monocle3::save_monocle_objects() directory
inst/projectData/manifest.dcf            entry added or updated
```

Then document the dataset the usual way in `R/data.R` (the function never edits
that file, and tells you if no topic is found), keep the generating script in
`inst/data-raw/` if you like, and rebuild the package:

``` r
#' Example disk-backed Monocle dataset
#'
#' A synthetic single-cell dataset.
#'
#' @format A Monocle 3 cell_data_set with BPCells-backed counts.
#' @details Access using projectData::data_attach().
"cds_main_adults"
```

``` r
devtools::document()
devtools::install()
```

Add `projectData.monocle3` to the data package's `Suggests` (and `Remotes`).

Points to know:

* The saved counts are always a BPCells on-disk matrix, and conversion is
  automatic. In-memory counts (`dgCMatrix`/`dgTMatrix`, or a BPCells matrix held
  in memory) are converted on a *copy* of the CDS with
  `monocle3::convert_counts_matrix()` (only `counts`; the intermediate matrix
  goes to a session temporary directory that is removed afterwards). Counts that
  are already BPCells-backed are saved as they are, without reconversion. Any
  other representation (a dense matrix, `DelayedMatrix`, HDF5-backed BPCells)
  is an error raised before anything is written. Monocle adds its internal
  `counts_row_order` assay to a converted copy; it is derived from the counts
  and is not a separate assay.
* Extra in-memory assays (for example `logcounts`, `spliced`) and alternative
  experiments (`SingleCellExperiment::altExp()`, e.g. ADT and CRISPR) are stored
  with the CDS and are tested to survive a save and a load for synthetic data;
  other extensions are not assumed to be supported.
* The manifest is reconciled with the package on every save (see below):
  entries whose saved directory or placeholder was deleted are removed.
* An existing dataset or placeholder is replaced only with `overwrite = TRUE`,
  and a `data/<name>.rda` that holds anything other than a placeholder is never
  replaced. Files are built in a hidden staging directory
  (`.projectData.monocle3-stage-*`), checked with the loader's own validation, and
  only then moved into place; if that fails the previous files are restored. It
  is not a filesystem transaction (a crash can leave the staging directory
  behind).
* Independently disk-backed assays are **rejected**, with an error raised before
  anything is written. Monocle saves such an assay (for example a BPCells
  `spliced` matrix, or the `counts` of an ADT alternative experiment) only as a
  reference to its original directory, which does not exist for the users of the
  package. All alternative experiments are inspected, at any nesting depth, and
  the error lists each offender with its location, such as
  `altExp 'ADT' / altExp 'normalized' / assay 'counts'`. Only the main CDS's
  Monocle-managed `counts` (and the derived `counts_row_order`) may be on disk.
  Convert the offending assays to in-memory matrices, or drop them; the package
  never does this automatically because it could need a lot of memory.
  `DelayedArray` assays and BPCells wrappers not known to be in memory are also
  refused; other exotic matrix classes are not checked.
* The caller's CDS is never modified, and nothing is written to the working
  directory.

### What users of the package see

``` r
data("cds_main_adults", package = "myDataPackage")
```

only loads the **placeholder**, a named character vector that prints its own
instructions with base R (no `projectData` needed): it is not the CDS, remove it
with `rm(cds_main_adults)`, then attach the package. If it masks the real
object, remove it and use:

``` r
projectData::data_attach("myDataPackage")
cds_main_adults    # resolved by the adapter, opened on first access
```

### Registering directories saved by other means

If you saved a CDS yourself (`save_monocle_objects(cds, "inst/extdata/human_cds",
archive_control = list(archive_type = "none"))`, counts BPCells-backed) and
created a matching `data/human_cds.rda` placeholder (a classed placeholder from
`save_monocle_cds()` or the historical string `"This is a placeholder
object."`), register it from the package source directory with:

``` r
projectData.monocle3::write_monocle_manifest(
  package_dir = "."
)
```

This is a package-authoring step; installed packages never generate manifests.
It finds each saved CDS directory under `inst/extdata/` that has a matching
placeholder in `data/` (ordinary `.rda` datasets and other directories are
ignored), and adds or updates its manifest entry.

It also **reconciles** the manifest: the saved directories and placeholders
that are present are the source of truth for the entries owned by this package
(loader `projectData.monocle3::cds`). If you delete a saved directory (or its
placeholder) while developing, the next call removes the stale entry instead of
failing:

```
projectData.monocle3: manifest updated
  Added: cds_bpcells_a
  Removed stale: cds_bpcells_b
  Preserved: 2 unrelated resources
```

Nothing is printed when nothing changes. Entries of other loaders are kept
unchanged and never repaired or removed (a resource or object name owned by
another adapter is reported as a conflict and left alone, and an invalid entry of
another adapter makes the call fail rather than be edited). A manifest that
cannot be parsed is never overwritten. Reconciliation edits only the manifest:
it never deletes a saved CDS directory or a placeholder. If no entry remains,
the manifest file is removed. Running it again changes nothing, and no CDS is
loaded or BPCells file created. See `?write_monocle_manifest` for details.
`save_monocle_cds()` runs the same reconciliation after it has saved the CDS.

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
The default (`"counts"`) assay is the one that is loaded from disk. Other
in-memory assays and alternative experiments are tested with synthetic data.

## Development

``` r
devtools::test()   # integration tests need monocle3, BPCells, SingleCellExperiment, SummarizedExperiment
```

Tests build two small real CDS fixtures in a subprocess (about 20 seconds)
and install them into throwaway libraries.

### Ordinary and full integration runs

By default (`PDM3_INTEGRATION_TESTS` unset or `false`) the integration tests
are optional: they skip when `monocle3`, `BPCells` or the other Monocle
packages are missing, when `projectData.monocle3.testdata` is not installed or
lacks the fixture resources, and when its source tree is not found (the
`PDM3_TESTDATA_SOURCE` environment variable, or a sibling directory of this
package). This keeps `R CMD check` usable anywhere.

Setting `PDM3_INTEGRATION_TESTS=true` requests a **full integration run**, in
which none of those conditions may skip. A missing or incompatible
prerequisite is raised as an error inside the test (class
`projectData.monocle3_integration_prerequisite`), which testthat records as a
failure, so the run fails and `Rscript` exits non-zero. The run requires:

- `projectData` (>= 0.0.0.9005), `monocle3`, `BPCells`,
  `SingleCellExperiment`, `SummarizedExperiment` and `withr`;
- `projectData.monocle3.testdata` **0.0.0.9004** installed, with exactly the
  resources `cds_bpcells_a`, `cds_bpcells_b`, `cds_multiassay` (each a saved
  CDS directory), a manifest registering them with
  `projectData.monocle3::cds`, and `data()` items for them and `ordinary_data`;
- `PDM3_TESTDATA_SOURCE` pointing at the fixture source tree (no sibling
  fallback), at that same version, with the same `inst/extdata` and
  `inst/projectData` file contents as the installed package (checked by
  checksum). The source-dependent tests install a disposable copy of it.

Platform-specific skips (`skip_on_platform()`) remain, and their reason is
labelled `[full integration: platform skip]` in the test summary. The test
`full integration prerequisites are met` lists every unmet prerequisite at once.

To run it in a clean R session, install the fixture package from its source
tree and run the tests in a fresh process:

``` sh
export PDM3_INTEGRATION_TESTS=true
export PDM3_TESTDATA_SOURCE=/path/to/projectData.monocle3.testdata   # at version 0.0.0.9004

R CMD INSTALL "$PDM3_TESTDATA_SOURCE"
Rscript -e 'devtools::test(reporter = "summary", stop_on_failure = TRUE)'

# or, as an installed-package check
R CMD build . && NOT_CRAN=true R CMD check projectData.monocle3_*.tar.gz
```

Check the reporter summary for skips: in a full run only platform skips
should appear.
