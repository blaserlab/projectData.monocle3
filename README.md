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

A longer, task-oriented guide is in the vignette
`vignette("using-monocle3-data", package = "projectData.monocle3")`
(source: [vignettes/using-monocle3-data.Rmd](vignettes/using-monocle3-data.Rmd)).
For the general adapter mechanism, see `vignette("adapters", package = "projectData")`.

## Installation

`projectData` is on CRAN; `monocle3` and `BPCells` are not (monocle3 is on
GitHub and Bioconductor-dependent, BPCells compiles C++ and needs the HDF5
headers: `libhdf5-dev` on Debian/Ubuntu, `brew install hdf5 pkg-config` on
macOS). With `pak`, which also resolves monocle3's Bioconductor dependencies for
your R version:

``` r
install.packages("pak")
pak::pak(c(
  "projectData",
  "bnprks/BPCells/r",
  "cole-trapnell-lab/monocle3",
  "blaserlab/projectData.monocle3"
))
```

`monocle3` and `BPCells` are listed in `Suggests` (and `Remotes`) so that
resource validation and registration work without them; opening a CDS requires
both and fails with an explicit message if they are missing. The tested
combinations are in [Compatibility](#compatibility).

**R-universe.** The package itself builds and installs from a universe because
its hard dependencies (`projectData`, base packages) are on CRAN. `monocle3` and
`BPCells` are GitHub-only `Suggests`: whether a universe resolves `Remotes` for
check-time Suggests has not been verified here, so without them in the same
universe the end-to-end tests are skipped there (ordinary mode) and the
universe check verifies nothing about the Monocle stack. The CI workflows in
`.github/workflows/` are the verification, not the universe build.

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
  and only if this package can show it wrote the existing directory: a native
  Monocle file index, a manifest entry of this loader or a recognized
  placeholder, at least two of the three, with nothing else in the directory. A
  directory that merely contains a file named like a Monocle save, a directory
  that another loader's manifest entry claims, and a `data/<name>.rda` that
  holds anything other than a placeholder are never replaced (see
  `?save_monocle_cds`). Files are built in a hidden staging directory
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

### Symbolic links

monocle3 and BPCells follow symbolic links when they copy a matrix directory
and do not check where a link leads, so this package refuses them instead. The
loader refuses a resource in which anything inside the saved directory is a
symbolic link (internal, escaping or dangling), whose BPCells directory is not
flat or lacks the files BPCells writes, or whose index lists an absolute path, a
`..` path or a directory where a file is expected. `save_monocle_cds()` applies
the same rule to your original counts directory before it stages anything (error
class `projectData.monocle3_unsafe_backing`) and never replaces a resource that
is, or contains, a link. The library, the package directory and parents such as
`inst/extdata` may themselves be symbolic links. Resources written by
`save_monocle_cds()` never contain links. Base R cannot tell a FIFO or device
file from a regular file, so those are not detected.

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

## Compatibility

Status of each configuration:

* **Verified**: the complete required integration suite passed in that exact
  configuration (`tools/compat-matrix.R`: every test run, no skip other than a
  labelled platform skip, declared versions found) and, where stated, `R CMD check`.
* **Expected**: technically plausible, but not fully tested.
* **Unsupported**: known incompatibility or outside the supported scope.

Installing a dependency successfully, or a run in which tests were skipped, is
not verification. The workflows in `.github/workflows/` have **not been run
yet**, so no Windows or macOS configuration is verified.

| projectData | monocle3 | BPCells | R / Bioconductor | OS | Status |
|---|---|---|---|---|---|
| 0.1.0 (CRAN) | 1.4.27 | 0.3.1 | 4.5.2 / 3.22 | Linux (Ubuntu 22.04) | Verified: 235 tests, 2,548 expectations, 0 failures, 0 skips, with the historical fixtures |
| 0.1.0 (CRAN) | 1.4.27 | 0.3.0 (release tag) | 4.5.2 / 3.22 | Linux | Verified: same counts, with the historical fixtures |
| 0.0.0.9008 (GitHub `31ff415`) | 1.4.27 | 0.3.0 | 4.5.2 / 3.22 | Linux | Verified: same counts, with the historical fixtures (the stack of the Issue 3 report) |
| 0.1.0 (CRAN) | 1.4.27 | 0.3.0 development snapshot (`f2026c3`) | 4.5.2 / 3.22 | Linux | Verified: `R CMD check --as-cran` Status: 2 NOTEs, no errors or warnings (the NOTEs are the development version number with GitHub-only `Remotes`/`Suggests`, and "unable to verify current time"); 2,332 expectations passed, 0 failures, 15 historical-fixture skips (fixtures not installed in that run) |
| 0.1.0 | 1.4.27 | 0.3.1 | release | Windows | Expected: workflow written, never run |
| 0.1.0 | 1.4.27 | 0.3.1 | release | macOS | Expected: workflow written, never run |
| 0.1.0 | 1.4.27 | 0.3.1 | 4.5 | Linux (GitHub Actions) | Expected: workflow written, never run |
| 0.0.0.9005 to 0.0.0.9007 | any | any | any | any | Expected: the declared minimum `0.0.0.9005` has not been run; 0.0.0.9008 and 0.1.0 have |
| any | other 1.4.x | 0.3.x | other R | Linux | Expected |
| any | any | BPCells main | any | Linux | Expected: allowed-failure CI job, never run (`all_matrix_inputs()` is experimental upstream) |
| any | any | counts or alternative assays in HDF5, `DelayedArray` or BPCells storage; tar archives | any | any | Unsupported (refused before anything is written, or rejected on load) |

The symbolic-link, read-only installation, relocation between libraries and
fresh-process tests are part of the suite, so each *Verified* Linux row includes
them. On Windows they run only where links can be created and `Sys.readlink()`
reports them (probed, not assumed), and the read-only test cannot make
directories read-only there; this is untested.

Assumptions about monocle3 and BPCells that the package cannot control (the
layout written by `save_monocle_objects()`, the BPCells matrix directory files, the
`matrix_control` interface of `load_monocle_objects()`) are stated by
`test-e2e-dependency-contract.R`; an upgrade that changes one fails there by name.
The supported BPCells directory has `version`, `storage_order`, `shape`,
`row_names`, `col_names`, `idxptr` and `val` or `val_data`, flat, with no symbolic links.

## Development

``` r
devtools::test()   # needs monocle3, BPCells, SingleCellExperiment, SummarizedExperiment, withr
```

### Integration tests

There are two families of integration tests with separate prerequisites and
separate strictness switches.

| | Self-contained end-to-end tests | Historical compatibility tests |
|---|---|---|
| Files | `test-e2e-*.R`, `test-save-*.R`, `test-integration.R`, `test-filesystem.R` (real-CDS parts) | `test-historical-*.R` |
| Data | generated by the current code in a temporary package | resources written by an earlier version, in the installed package `projectData.monocle3.testdata` |
| Needs | the Monocle stack and `projectData` | the fixture package (and, for one file, its source tree) |
| Strict with | `PDM3_INTEGRATION_TESTS=true` | `PDM3_HISTORICAL_TESTS=true` |

A contributor needs nothing beyond the declared runtime dependencies
(`projectData`, `monocle3`, `BPCells`, `SingleCellExperiment`,
`SummarizedExperiment`, `Matrix`, `withr`; `pkgload` when running under
`devtools::test()`) to verify the whole workflow:

``` sh
NOT_CRAN=true PDM3_INTEGRATION_TESTS=true Rscript -e 'devtools::test(filter = "e2e", reporter = "summary")'
```

The `test-e2e-*.R` files (about 2.5 minutes, 1,174 expectations) do this, in a
throwaway directory removed at the end of the run (about 100 KB of data, plus the
temporary libraries):

1. build a small synthetic CDS (24 x 16 and 30 x 12; sparse integer counts,
   cell and gene metadata, `logcounts` and `spliced` assays, an ADT alternative
   experiment, PCA and UMAP reductions with fixed values) with public monocle3,
   SingleCellExperiment and BPCells APIs (`helper-synthetic.R`);
2. scaffold a data package (`DESCRIPTION`, `R/data.R`, `man/`) and author two
   resources with `save_monocle_cds()`: one from in-memory counts (converted
   automatically), one from BPCells-backed counts;
3. `R CMD build` the package and `R CMD INSTALL` the tarball into two separate
   temporary libraries (names with spaces and non-ASCII characters where the
   locale allows);
4. check discovery, reconstruction, `data_attach()`/`data_detach()`, work
   directories and retained objects in this session, the same package in each
   library (and through a symbolic link) in fresh R processes, independence
   from the authoring directory, and damaged installations with `data_retry()`
   recovery on disposable copies.

Only the live package libraries are read, never modified. Fresh processes
(`run_child()` in `helper-synthetic.R`) load the adapter with `pkgload` under
`devtools::test()` and from the installed package otherwise.

### Continuous integration

| Workflow | What it runs |
|---|---|
| `R-CMD-check.yaml` | Ubuntu, Windows, macOS (R release) and Ubuntu (R 4.5): `tools/verify-stack.R`, the strict suite (`tools/compat-matrix.R current`, `PDM3_INTEGRATION_TESTS=true`), then `R CMD check --as-cran`. A fifth job checks without the Monocle stack (skips expected). |
| `compat-matrix.yaml` | Linux, weekly and on demand: the `legacy` and `bpcells_030` configurations; the historical fixtures; BPCells `main` (allowed failure). |

CI installs `projectData` from CRAN, and `monocle3` and `BPCells` from GitHub at
the tags in the workflow's `MONOCLE3_REF`/`BPCELLS_REF` (written into `Remotes` of
the CI checkout by `tools/ci-pin-remotes.R`; the package's own `Remotes` stay
unpinned). monocle3's Bioconductor dependencies are resolved by `pak` for the R
version in use. The historical job checks out `projectData.monocle3.testdata` at a
pinned commit (`TESTDATA_REF`), installs it from that source tree, and the tests
verify its identity: version floor plus the md5 of every resource's
`file_index.rds` and `cds_object.rds` (`testdata_fingerprint`), identical to the
installed copy. The checksum is what matters, not an exact version. Note that
fixtures contain binary files: check them out without line-ending conversion.

Reproduce a configuration locally (each takes about 7 minutes after the libraries exist):

``` sh
Rscript tools/compat-libs.R projectdata_cran bpcells_031   # libraries; BPCells compiles (about 10 minutes)
Rscript tools/compat-matrix.R bpcells_031                  # self-contained suite, strict
PDM3_TESTDATA_SOURCE=/path/to/projectData.monocle3.testdata \
  Rscript tools/compat-matrix.R --historical bpcells_031   # plus the historical fixtures
Rscript tools/compat-matrix.R --list
```

The runner prints R, OS, Bioconductor and package versions, counts, and a status
(`VERIFIED`, `NOT VERIFIED (skips)`, `FAILED`); its exit status is 0 only if all
requested configurations are verified.

### Strictness

By default (both variables unset or `false`) every integration test is optional:
it skips when a prerequisite is missing (and on CRAN, unless `NOT_CRAN=true`).
Setting a variable to `true` turns missing prerequisites of *that family* into
errors (class `projectData.monocle3_integration_prerequisite`), which testthat
records as failures, so a run cannot look successful because tests were
skipped. Any other value is an error.

- `PDM3_INTEGRATION_TESTS=true`: the self-contained tests must run. This never
  requires the fixture package: a missing `projectData.monocle3.testdata` only
  skips the historical tests, with the reason prefixed `[historical fixtures]`.
- `PDM3_HISTORICAL_TESTS=true`: the historical tests must run. It requires
  `projectData.monocle3.testdata` (version 0.0.0.9004 or later) installed with
  exactly the resources `cds_bpcells_a`, `cds_bpcells_b`, `cds_multiassay`, a
  manifest registering them with `projectData.monocle3::cds`, `data()` items for
  them and `ordinary_data`, and the original content (checksums of each
  resource's `file_index.rds` and `cds_object.rds`; a later version with
  unchanged resources is accepted). It also requires `PDM3_TESTDATA_SOURCE`
  pointing at the fixture source tree (no sibling fallback), with the same
  `inst/extdata` and `inst/projectData` contents as the installed package. The
  source-dependent tests install a disposable copy of it. The fixtures are never
  regenerated.

Platform-specific skips (`skip_on_platform()`) remain in strict runs, labelled
`[strict integration: platform skip]`. The tests `strict ... integration
prerequisites are met` list every unmet prerequisite at once.

A complete run, from a clean process:

``` sh
export NOT_CRAN=true PDM3_INTEGRATION_TESTS=true PDM3_HISTORICAL_TESTS=true
export PDM3_TESTDATA_SOURCE=/path/to/projectData.monocle3.testdata

R CMD INSTALL "$PDM3_TESTDATA_SOURCE"
Rscript -e 'devtools::test(reporter = "summary", stop_on_failure = TRUE)'

# or, as an installed-package check
R CMD build . && R CMD check projectData.monocle3_*.tar.gz
```

Check the reporter summary for skips: in a strict run only platform skips
should appear. When a fresh-process, build or install step fails, the error
contains the complete output of the subprocess.
