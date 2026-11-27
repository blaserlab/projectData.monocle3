# projectData.monocle3

<!-- badges: start -->
[![R-CMD-check](https://github.com/blaserlab/projectData.monocle3/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/blaserlab/projectData.monocle3/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

`projectData.monocle3` lets an R data package ship a **Monocle 3
`cell_data_set` (CDS) whose counts are a BPCells on-disk matrix**, and
restores it on first access from any package library, without attaching Monocle 3
and without writing to the installed package or the working directory.

It is an adapter for [projectData](https://github.com/blaserlab/projectData),
which does the general work (registering installed data packages, resolving
names and conflicts, opening resources lazily, caching and retrying). This
package adds the Monocle-specific part: how to *save* a CDS into a data package so
that it is portable, and how to *restore* it.

A CDS with BPCells counts holds a reference to a directory on the author's disk,
so `save()` or `saveRDS()` produce a file that is useless on another machine.
Use this adapter when the counts are large enough to stay on disk and the object
will be distributed in a data package; if the CDS fits comfortably in memory, ship
it as an ordinary `.rda` dataset.

## Installation

Four separate things may need installing. `monocle3` and `BPCells` are GitHub-only
(BPCells compiles C++ and needs the HDF5 headers: `libhdf5-dev` on Debian/Ubuntu,
`brew install hdf5 pkg-config` on macOS).

``` r
# 1. projectData core (CRAN)
install.packages("projectData")

# 2. The adapter (GitHub)
install.packages("pak")
pak::pak("blaserlab/projectData.monocle3")

# 3. Optional runtime and analysis dependencies; pak also resolves monocle3's
#    Bioconductor dependencies for your version of R
pak::pak(c("bnprks/BPCells/r", "cole-trapnell-lab/monocle3"))
```

4. **A data package that uses the adapter** is installed like any package. You
   never call `library(projectData.monocle3)`: the package's manifest names the
   adapter and projectData loads it on first access.

Only `projectData` is a hard dependency of the adapter, so step 2 alone does not
install `monocle3` or `BPCells`. Registering, cataloguing and validating a data
package work without them; *authoring* and *opening* a CDS need both and fail with
a message naming the missing package. Authors also need `Matrix` if their counts
are sparse.

**Alternative: the blaserlab R-universe.** It hosts the adapter, `BPCells` and
`monocle3`, so one call installs the whole stack. Bioconductor's repositories are
needed for monocle3's dependencies, and HDF5 headers are still required when
packages are compiled from source (no Linux binary exists for every R version):

``` r
install.packages(
  c("projectData.monocle3", "BPCells", "monocle3"),
  repos = c(
    "https://blaserlab.r-universe.dev",
    BiocManager::repositories()
  )
)
```

This route was verified once, on Linux with R 4.5.2 and an empty library
(everything compiled from source, `projectData` 0.1.0 from CRAN). See
`tools/release/RELEASE-0.1.0.md` for what was and was not checked.

## Creating a data package

In the source directory of a data package (the one with `DESCRIPTION`):

``` r
projectData.monocle3::save_monocle_cds(cds, name = "my_cds", package_dir = ".")
```

This writes, without modifying `cds`:

``` text
data/my_cds.rda                  placeholder (prints instructions in base R)
inst/extdata/my_cds/             native monocle3::save_monocle_objects() directory
inst/projectData/manifest.dcf    entry for my_cds (created or reconciled)
```

Then document `"my_cds"` in `R/data.R` (never edited for you), run
`devtools::document()`, add `projectData.monocle3` to the package's `Suggests`,
and install the package. `write_monocle_manifest()` re-reconciles the manifest
with what is on disk and is idempotent. Saving is staged, verified with the
loader's own validation and rolled back on failure; `overwrite = TRUE` replaces
only a resource this package can show it wrote. The step-by-step version,
including building and installing, is `vignette("authoring-monocle3-data")`.

The `.rda` file is a **placeholder, not the CDS**. It lets the dataset appear in
`data(package = "myDataPackage")` and have help (`?my_cds`); loading it with
`data()` prints instructions. Use `projectData::data_attach()` or `data_get()` for
the real object. The placeholder must be part of the package source: if
`.gitignore` excludes `*.rda`, add `!data/my_cds.rda`.

## Using a data package

``` r
projectData::data_attach("myDataPackage")
projectData::data_catalog()        # metadata only: nothing is opened
my_cds                             # first access restores the CDS
projectData::data_get("my_cds", package = "myDataPackage")   # no attaching
```

The restored CDS keeps working after `data_detach()`. Opening copies the BPCells
matrix, plus a second row-ordered copy that Monocle keeps as `counts_row_order`,
into a working directory that projectData allocates under the session temporary
directory, so it costs temporary disk space and is not RAM-free; there is no
persistent cache. The UMAP index, if any, is read from the
installed file, so do not reinstall the data package while you use the object.
See `vignette("using-monocle3-data")`.

## Supported storage

| Representation | Handling |
|---|---|
| `counts` as a BPCells directory matrix (`MatrixDir`) | Saved as it is, through native Monocle saving |
| `counts` as `dgCMatrix` / `dgTMatrix` or a BPCells in-memory matrix | Converted to BPCells automatically, on a copy |
| In-memory alternative assays and alternative experiments, metadata, reductions | Retained |
| A secondary assay stored on disk (BPCells, HDF5, `DelayedArray`), anywhere in the object | **Refused** before anything is written |
| `counts` as a dense matrix, `DelayedMatrix`, HDF5-backed BPCells | **Refused** before anything is written |
| HDF5 or tar saves, in-memory-counts saves, several CDS in one resource | Not supported |

Unsupported storage is refused, never silently converted or left dangling.
`vignette("storage")` explains the details and limits.

Unlike `projectData.Seurat`, this adapter converts supported in-memory counts
automatically and restores by copying the matrix on first access; Seurat objects
must already be BPCells-backed and are read from the installed directories
without copying.

## Documentation and troubleshooting

* `vignette("authoring-monocle3-data")`: create and install a data package.
* `vignette("using-monocle3-data")`: discover, load, detach, troubleshoot.
* `vignette("storage")`: what is stored, what loading copies, lifetimes, limits.
* `?save_monocle_cds`, `?write_monocle_manifest`, `?projectData_loaders`:
  reference, including condition classes.
* projectData: `vignette("projectData", package = "projectData")` and
  `vignette("adapters", package = "projectData")`.

| Symptom | Cause | What to do |
|---|---|---|
| Error naming `monocle3` or `BPCells` as not installed | Opening and authoring need them | Install them (see above), then `projectData::data_retry("<collection>")` |
| Catalog shows `unavailable-loader` | The adapter is not installed | Install `projectData.monocle3`, then `data_retry()` |
| "required file(s) missing", or a validation error naming `file_index.rds`, in-memory counts, HDF5 or a symbolic link | Damaged installation, or a resource not written by `save_monocle_cds()` | Reinstall the data package; re-save if you are the author |
| An opening failed once and keeps failing | projectData caches failures | Fix the cause, then `data_retry("<collection>")` |
| `data("name")` prints text, not an object | The `.rda` placeholder | `rm(name)`, then `data_attach("<package>")` |
| `projectData.monocle3_external_assay` at save | A secondary assay is on disk | Convert it to an in-memory matrix, or drop it |
| `projectData.monocle3_exists` | The name is already saved | `overwrite = TRUE`, or choose another `name` |
| `projectData.monocle3_not_owned` / `_ambiguous_ownership` | The existing files cannot be shown to be written by this package | Choose another `name`, or move the files yourself; nothing was changed |
| `projectData.monocle3_conflict` / `_manifest_error` | The name belongs to another loader's entry, or the manifest is invalid | Rename the resource, or fix `inst/projectData/manifest.dcf` |
| `projectData.monocle3_unsafe_backing` | A symbolic link or malformed BPCells directory in your counts | Write the counts to a fresh directory with `BPCells::write_matrix_dir()` |
| Placeholder missing after a fresh `git clone` | `.gitignore` excludes `*.rda` | Add `!data/<name>.rda`, re-run `write_monocle_manifest()` |
| A `.projectData.monocle3-stage-*` directory in the package | R was killed during a save | Safe to delete once the package is in the state you want; it may hold the previous files |

## Compatibility

Status per configuration, from `tools/compat-matrix.R` (strict suite: no skip other
than a labelled platform skip) or a GitHub Actions run, and `R CMD check`:

* **Verified**: tested successfully in that exact configuration.
* **Expected**: technically plausible, not tested.
* **Unsupported**: known not to work, or out of scope.

GitHub Actions run
[46025240109](https://github.com/blaserlab/projectData.monocle3/actions/runs/46025240109)
(commit `d3f2683`) ran the strict self-contained suite, then `R CMD check --as-cran`
(including vignettes), on every platform below, with projectData 0.1.0, monocle3
1.4.27 (`536f103`) and BPCells 0.3.1 (`5f2a5d2`):

| R / Bioconductor | OS | Strict suite | `R CMD check` |
|---|---|---|---|
| 4.6.2 / 3.24 | Ubuntu 26.04 | 239 tests, 2,369 expectations, 0 failures | Status OK |
| 4.5.3 / 3.22 | Ubuntu 26.04 | 239 tests, 2,369 expectations, 0 failures | Status OK |
| 4.6.2 / 3.24 | macOS 26 arm64 | 239 tests, 2,367 expectations, 0 failures | Status OK |
| 4.6.2 / 3.24 | Windows Server 2022 | 239 tests, 2,197 expectations, 0 failures; 18 labelled platform skips | Status OK |

Each run also skipped the 15 historical-fixture tests (the fixture package is not
installed in that job). The Windows platform skips are the symbolic-link tests
(`Sys.readlink()` does not report links there) and the test that deletes an
installation while a UMAP index is mapped. A fifth job, without the Monocle stack,
checks that the package installs, builds and checks with skips only.

| projectData | monocle3 | BPCells | R / Bioconductor | OS | Status |
|---|---|---|---|---|---|
| 0.1.0 (CRAN) | 1.4.27 | 0.3.1 | 4.5.2 / 3.22 | Linux (Ubuntu 22.04) | Verified: 235 tests, 2,548 expectations, 0 failures, 0 skips, including the historical fixtures |
| 0.1.0 (CRAN) | 1.4.27 | 0.3.0 | 4.5.2 / 3.22 | Linux | Verified: same, with the historical fixtures |
| 0.0.0.9008 (GitHub) | 1.4.27 | 0.3.0 | 4.5.2 / 3.22 | Linux | Unsupported (below the declared minimum `projectData >= 0.1.0`); historical regression check only (`regression_9008`), see `tools/README.md` |
| other 1.4.x | | 0.3.x | other R | any | Expected |
| any | any | BPCells main | any | Linux | Expected: allowed-failure CI job, never run (`all_matrix_inputs()` is experimental upstream) |
| any | any | counts or secondary assays in HDF5, `DelayedArray` or BPCells storage; tar archives | any | any | Unsupported (refused, or rejected on load) |

The Linux rows were measured at an earlier commit and are re-run by
`.github/workflows/compat-matrix.yaml`, which has not yet run on GitHub. The
historical-fixture job, and Windows or macOS runs of other stacks, are therefore
unverified.

Assumptions about monocle3 and BPCells that this package cannot control (the
layout written by `save_monocle_objects()`, the BPCells directory files, the
`matrix_control` interface of `load_monocle_objects()`, and BPCells'
experimental `all_matrix_inputs()`) are stated by `test-e2e-dependency-contract.R`;
an upgrade that changes one fails there by name.

## Limitations

* Saving is staged and rolled back on failure, but it is not a filesystem
  transaction: if R is killed during the commit, a hidden
  `.projectData.monocle3-stage-*` directory may remain.
* One CDS per resource; no persistent cache; no support for HDF5, `DelayedArray`
  or on-disk secondary assays.
* Symbolic-link and file-locking behavior on Windows is covered only as far as the
  CI run above (links are not testable there).
* Check the size limits of wherever you distribute a data package: the BPCells
  files count towards it.

## Development

``` r
devtools::test()
devtools::check()
```

Strict integration runs, the dependency matrix and CI are described in
[tools/README.md](tools/README.md).
