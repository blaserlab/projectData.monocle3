# projectData.monocle3 0.1.0: release preparation (draft, nothing published)

Proposed tag: `v0.1.0`, created only after the maintainer approves, on the commit
that contains these changes and after the Actions workflow has passed on that
exact commit. No tag, GitHub release or R-universe publication has been made.

## Install (final commands)

```r
install.packages("pak")
pak::pak(c(
  "projectData",                          # CRAN
  "bnprks/BPCells/r",                     # GitHub only; needs HDF5 headers
  "cole-trapnell-lab/monocle3",           # GitHub only
  "blaserlab/projectData.monocle3"
))
```

Hard dependency: `projectData (>= 0.0.0.9008)` (0.1.0 from CRAN is the tested
release). `monocle3` and `BPCells` are `Suggests` + `Remotes`: needed to author and
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
| Same, BPCells 0.3.0; projectData 0.0.0.9008 (the declared minimum) | Local, earlier commit (`85b68c7` plus uncommitted changes): 235 tests, 0 failures, 0 skips |
| BPCells `main`; historical-fixture and legacy jobs on GitHub | Never run on GitHub (`compat-matrix.yaml` has no run) |

## R-universe

Status: **Expected to work for the adapter alone; not ready for the Monocle stack.**

* Repository is public, `DESCRIPTION` is valid, license is `MIT + file LICENSE`
  (GitHub shows "Other" because `LICENSE` is the two-line CRAN stub; the MIT text is
  in `LICENSE.md`).
* The adapter's only hard dependency is `projectData`, on CRAN (verified by a clean
  install into an empty library); the `no-stack` CI job verifies that it builds and
  checks without monocle3 and BPCells (skips only).
* **Blocker for the Monocle stack in the existing `blaserlab` universe:** its
  `packages.json` lists BPCells as `https://github.com/bnprks/BPCells` without
  `"subdir": "r"`, and its builds of BPCells and monocle3 currently fail
  (https://github.com/r-universe/blaserlab/actions/runs/45384380124 and
  `.../45384407201`: "dependency BPCells is not available for package monocle3").
  `tools/release/r-universe-packages.json` is the proposed addition
  (projectData.monocle3, and BPCells with `subdir` and a tag). Edit the
  `blaserlab/universe` repository by hand; nothing there was changed. Whether a
  universe resolves `Remotes` for Suggests during `R CMD check` is unverified.
* Not verified: any hosted build. Do not call it "Verified on R-universe" until one
  succeeds and `install.packages("projectData.monocle3", repos = c("https://blaserlab.r-universe.dev", "https://cloud.r-project.org"))` works.

## Release checklist

1. Review and commit the changes (propose the message below), merge to `main`.
2. Push; wait for `R-CMD-check` to pass on all five jobs for that commit; update the
   README table (run id and commit) if it differs from `d3f2683`.
3. Dispatch `compat-matrix` once (never run); record the result or adjust the README.
4. Update the universe `packages.json` (see above); wait for its build.
5. Tag `v0.1.0`, publish the release with the notes above.
6. Afterwards, bump to `0.1.0.9000` and add a NEWS heading.

Proposed commit line for `R/regenerated_git_commands.R`:

```r
gert::git_commit("Prepare 0.1.0: vignettes, README, NEWS, docs, minimum projectData 0.0.0.9008")
```

## Outstanding manual steps

* Maintainer approval of the version, tag and notes.
* Universe `packages.json` change and verification of a hosted build.
* Rerunning CI on the release commit (the CI evidence above is for `d3f2683`,
  which predates the documentation changes and the version bump).
* Decide whether to require `projectData (>= 0.1.0)` (Seurat does). Kept at
  `0.0.0.9008` here because raising it would also retire the `legacy` configuration
  in `tools/compat-matrix.R` and the compat workflow.
* `pak::pak()` of the BPCells GitHub subdirectory failed locally with "Failed to
  uncompress BPCells" (this machine; reproduced three times, also with an internal
  `untar`). It works on the GitHub runners of all four platforms. Cause not found.
