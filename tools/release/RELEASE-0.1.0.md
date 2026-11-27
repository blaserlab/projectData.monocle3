# projectData.monocle3 0.1.0: release preparation (draft, nothing published)

Proposed tag: `v0.1.0`, created only after the maintainer approves, on the commit
that contains these changes and after the Actions workflow has passed on that
exact commit. No tag or GitHub release has been made; the adapter, BPCells and monocle3 are built on the blaserlab R-universe (see below).

## Install (final commands)

```r
install.packages("projectData")                       # 1. core (CRAN)
install.packages("pak")
pak::pak("blaserlab/projectData.monocle3")            # 2. the adapter (GitHub)
pak::pak(c("bnprks/BPCells/r",                        # 3. GitHub only; needs HDF5 headers
           "cole-trapnell-lab/monocle3"))
```

A data package that uses the adapter is installed like any package. Installing the
adapter alone does not install monocle3 or BPCells.

Hard dependency: `projectData (>= 0.1.0)` (CRAN; same as `projectData.Seurat`). `monocle3` and `BPCells` are `Suggests` + `Remotes`: needed to author and
to open a CDS, not to install, register or validate.

## Draft GitHub release notes

### projectData.monocle3 0.1.0

An adapter that lets a `projectData` data package ship a Monocle 3
`cell_data_set` whose counts are a BPCells on-disk matrix, and open it lazily from
the installed package.

* **Integration with projectData.** The loader `projectData.monocle3::cds` is
  named by the data package's manifest; projectData loads the adapter on first
  access. Users never call `library(projectData.monocle3)` and never need to
  attach Monocle 3 for the restoration.
* **Portable, disk-backed distribution.** The CDS is saved with Monocle's native
  `save_monocle_objects()` inside `inst/extdata/`, and restored with
  `load_monocle_objects()` into a working directory allocated by projectData. The
  installed package is immutable and the working directory is never changed.
* **Deferred loading.** Registration and validation read no matrix data and need
  neither monocle3 nor BPCells.
* **Manifest-based registration.** `save_monocle_cds()` writes the saved
  directory, the mandatory `.rda` placeholder and the manifest entry;
  `write_monocle_manifest()` reconciles the manifest (adds, updates, removes
  stale entries, preserves other adapters' entries, idempotent).
* **Automatic BPCells conversion** of supported sparse counts (`dgCMatrix`,
  `dgTMatrix`, BPCells in-memory), on a copy of the CDS; BPCells counts are saved
  as they are.
* **Retained content:** in-memory alternative assays, alternative experiments,
  metadata and reductions.
* **Safe authoring.** Everything is validated before anything is written; saving is
  staged, verified with the loader's own checks and rolled back on failure;
  `overwrite = TRUE` replaces only what the package can show it wrote; symbolic
  links and malformed BPCells directories are refused.
* **Cross-platform validation.** Strict self-contained suite plus
  `R CMD check --as-cran` on Ubuntu (R 4.6.2 and 4.5.3), macOS (arm64) and
  Windows with projectData 0.1.0, monocle3 1.4.27, BPCells 0.3.1
  (run 46025240109, commit `d3f2683`; to be repeated on the release commit).
* Documentation: three vignettes (authoring, using, storage and lifecycle).

**Known limitations.** One CDS per resource. Secondary assays stored on disk
(BPCells, HDF5, `DelayedArray`) and HDF5 or dense counts are refused, not converted.
Native loading copies the matrix twice into the session temporary directory per
opening ("disk-backed" is not RAM-free or free of temporary disk cost); there is no
persistent cache. The UMAP Annoy index is read from the installed file. Saving is
not a filesystem transaction. On Windows, symbolic-link behaviour could not be
tested. monocle3 and BPCells are GitHub-only and BPCells' `all_matrix_inputs()` is
experimental upstream.

## Compatibility summary

| Configuration | Evidence |
|---|---|
| Ubuntu 26.04, R 4.6.2 / Bioc 3.24; R 4.5.3 / Bioc 3.22; macOS 26 arm64; Windows Server 2022 (R 4.6.2) with projectData 0.1.0, monocle3 1.4.27, BPCells 0.3.1 | GitHub Actions run 46025240109 at `d3f2683`: strict suite VERIFIED, `R CMD check --as-cran` Status OK on all four |
| Ubuntu 22.04, R 4.5.2, projectData 0.1.0, monocle3 1.4.27, BPCells 0.3.1 | Local `tools/compat-matrix.R --historical`: 240 tests, 2,570 expectations, 0 failures, 0 skips (2026-11-27, at the release-preparation working tree) |
| Same, BPCells 0.3.0; projectData 0.0.0.9008 (historical regression only, unsupported) | Local, earlier commit (`85b68c7` plus uncommitted changes): 235 tests, 0 failures, 0 skips |
| BPCells `main`; historical-fixture and legacy jobs on GitHub | Never run on GitHub (`compat-matrix.yaml` has no run) |

## R-universe

Status: **Verified for the Monocle stack on Linux R 4.5.2 (source install); other platforms not tested.**

* Repository is public, `DESCRIPTION` is valid, license is `MIT + file LICENSE`
  (GitHub shows "Other" because `LICENSE` is the two-line CRAN stub; the MIT text is
  in `LICENSE.md`).
* The adapter's only hard dependency is `projectData`, on CRAN; the `no-stack` CI job
  verifies that it builds and checks without monocle3 and BPCells (skips only).
* **Registry change (2026-11-27):** `blaserlab/blaserlab.r-universe.dev` commit
  `140e9e0` ("Configure BPCells and projectData.monocle3 for R-universe") set
  `"subdir": "r"` on the existing BPCells entry (tracking the default branch, no
  `branch`) and added `projectData.monocle3`. The earlier proposal
  `tools/release/r-universe-packages.json` (with `branch: v0.3.1`) was not used; the
  applied diff is `tools/release/r-universe-packages.patch`.
* **Cause of the earlier failure:** the universe built BPCells commit `b96a440`
  (2024-05, 110 commits behind `main`) which fails on GCC 15.2 in `libdivide.h`;
  monocle3 then failed with "dependency BPCells is not available". After the change
  BPCells builds `5f2a5d2` (0.3.1) from `r/`.
* **Hosted builds** (source packages and binaries published; blaserlab universe):

  | Package | Version / commit | Hosted status |
  |---|---|---|
  | BPCells | 0.3.1, `5f2a5d2`, `RemoteSubdir: r` | success; binaries for Linux, macOS, Windows. Per-platform check jobs report an examples error (`UseMethod("colVars")`), upstream; the Wasm build fails in `hdf5.h`. |
  | monocle3 | 1.4.27, `536f103` | success (published 22:59Z, after BPCells; it was not rebuilt automatically, the dependents-trigger job was skipped) |
  | projectData.monocle3 | 0.1.0, `ea36cd7` | success |

  `ea36cd7` is the commit the universe built. It predates later local working-tree
  changes; rebuild status for the final release commit is unverified.
* **Clean-library verification** (Linux, R 4.5.2, empty library, repos: blaserlab
  universe plus `BiocManager::repositories()`, everything compiled from source):
  `projectData.monocle3` 0.1.0, `BPCells` 0.3.1 (`RemoteSubdir: r`), `monocle3` 1.4.27
  and `projectData` 0.1.0 (CRAN) installed with no errors. The self-contained `e2e`
  tests (strict, `PDM3_INTEGRATION_TESTS=true`, from a scratch copy of the source,
  libraries only from the clean library, no historical fixtures) gave 30 tests, 1,232
  expectations, 0 failures, 0 errors, 0 skips, 0 warnings. They cover authoring with
  `save_monocle_cds()`, building and installing the generated package, retrieval in
  fresh processes, and counts/metadata/dimensions after reconstruction; the
  work-directory assertions were not inspected individually.
* Not verified: installation of the hosted Linux binaries (R 4.6.2/4.7.0), macOS or
  Windows binaries; the hosted binaries of BPCells/monocle3 on any platform; the
  universe's "Update universe" sync still fails (ChrAccR/ChrAccRex 401 and an
  "Update submodules" error), unrelated to this change.

## Release checklist

1. Review and commit the changes (propose the message below), merge to `main`.
2. Push; wait for `R-CMD-check` to pass on all five jobs for that commit; update the
   README table (run id and commit) if it differs from `d3f2683`.
3. Dispatch `compat-matrix` once (never run); record the result or adjust the README.
4. Done (2026-11-27): universe `packages.json` updated and built (see above); recheck the hosted build after the release commit is pushed.
5. Tag `v0.1.0`, publish the release with the notes above.
6. Afterwards, bump to `0.1.0.9000` and add a NEWS heading.

Proposed commit line for `R/regenerated_git_commands.R`:

```r
gert::git_commit("Prepare 0.1.0: vignettes, README, NEWS, docs, minimum projectData 0.1.0")
```

## Outstanding manual steps

* Maintainer approval of the version, tag and notes.
* Re-verify the hosted adapter build once the release commit is pushed (the hosted build is `ea36cd7`).
* Rerunning CI on the release commit (the CI evidence above is for `d3f2683`,
  which predates the documentation changes and the version bump).
* Done: `projectData (>= 0.1.0)` is required (as Seurat); the former `legacy`
  configuration is now the unsupported historical regression `regression_9008`.
* `pak::pak()` of the BPCells GitHub subdirectory failed locally with "Failed to
  uncompress BPCells" (this machine; reproduced three times, also with an internal
  `untar`). It works on the GitHub runners of all four platforms. Cause not found.
