# projectData.monocle3 — Project memory and engineering guidance

## Purpose
Build `projectData.monocle3`, a separate R package that integrates disk-backed Monocle 3 `cell_data_set` (CDS) objects with `projectData`. Distribute initially through GitHub and R-universe. Keep the `projectData` core independent of Monocle and BPCells.

## Source of truth
- Target core: `projectData` version `0.0.0.9005`; consult its current source before depending on undocumented internals.
- Read `projectData` vignette `vignettes/adapters.Rmd`, especially the version-1 loader contract and manifest authoring rules.
- Historical reference implementations: `blaserlab/blaseRtools` files `R/save_monocle_disk.R` and `R/project_data.R`. Preserve their *goals*, not their older implementation details.
- Consult the installed versions/source of `monocle3` and `BPCells` before assuming arguments, serialization layout, or copying semantics.

## Settled architecture
- Separate adapter package named `projectData.monocle3` (the name of the repo, DESCRIPTION and GitHub remote; supersedes the earlier working name `projectData.monocle`).
- Loader ID: `projectData.monocle3::cds`; export `projectData_loaders()` to return a `projectData::data_loader()` or list thereof.
- Loader must use existing `data_loader(open, discover, validate, storage, needs_work_dir)` version-1 contract, with `storage = "disk-backed"` and `needs_work_dir = TRUE`.
- Manifest (`inst/projectData/manifest.dcf`) identifies each CDS resource, its source under `extdata/`, object name, loader, and `AdapterPackage: projectData.monocle3`/`AdapterExport: projectData_loaders`. Use source paths in the **installed** layout (`extdata/name`, not `inst/extdata/name`).
- Require one CDS object per resource initially. Explicit manifest-backed discovery is sufficient for the first milestone.
- Use Monocle's supported native persistence APIs (`save_monocle_objects()`/`load_monocle_objects()`), not `saveRDS()` as a substitute for a backed CDS.
- Installed resource directories are immutable/read-only. Never `setwd()` or write to the user's working directory.
- On first access only, open the saved Monocle directory via the loader, passing an isolated path under `paths$work_dir` for BPCells restoration; verify exact `matrix_control` semantics against the installed Monocle version.
- Do not eagerly load during registration/validation. `validate()` inspects existence/cheap metadata only. `open()` returns a named list matching the descriptor's `objects`.
- The core controls laziness, resource caching, retry, and working-directory allocation. The adapter should not implement its own registry or caching layer.
- Do not delete BPCells backing files on detach, when objects are removed, or with `on.exit()`. They may still be referenced by retained CDS objects. Session-temp storage is the v0.1 default; persistent cache is deferred.
- Object independence from installed source must be verified experimentally; do not claim it until all needed external references have been checked.

## Save/package authoring design (agreed, but **second implementation phase**)
- Provide a high-level `save_monocle_cds(cds, name, package_dir = ".", convert_to_bpcells = FALSE, overwrite = FALSE)` (signature may be refined after inspecting Monocle APIs).
- BPCells conversion is **optional, opt-in**; do not silently convert in-memory or alternative assays. Preservation and round-trip behavior of alternative assays need testing.
- Authoring helper should create the native saved CDS under `inst/extdata/<name>/`, a manifest entry, and a small `data/<name>.rda` placeholder.
- Placeholders are **mandatory** (not configurable) for adapter-created data packages, for conventional `data()` discoverability and familiar `R/data.R`/roxygen2 documentation. Documentation itself is authored by the data-package developer.
- Placeholder is a classed, self-explanatory character vector (working class `projectData_monocle_placeholder`). Its *base R printout*, without any adapter or projectData loaded, must tell the user that this is not the CDS; to remove the masking object from `.GlobalEnv` using `rm(<name>)`; then to use `projectData::data_attach("<package>")` and access `<name>`; and how to install missing packages. No S3 print method is required for instructions to remain legible. Prefer one line per vector element over a single escaped-newline string.
- Manifest registration must take precedence over `.rda` placeholder candidates for the same resource name; test this.
- `data()` itself will not automatically print the placeholder, and loading it after `data_attach()` can mask the attached real object. Explain this accurately.

## First milestone: loader only
1. Scaffold an R package with `DESCRIPTION`, `NAMESPACE`, documented exported adapter factory, internal `validate` and `open` callbacks, tests, and README.
2. Use an **existing saved disk-backed** Monocle CDS as a fixture or small synthetic fixture. Start with a handwritten manifest and no high-level save helper.
3. Test loader discovery/resolution with `projectData`, registration without opening, first-access reconstruction, object naming/class, working-directory location, nonmutation of `getwd()`, and multiple independent datasets.
4. Test counts/metadata/reductions and external path references where available; verify a retained object continues working after `data_detach()`; test recovery via `data_retry()`.
5. Run appropriate checks/tests, report limitations and assumptions, and keep `projectData` source unchanged unless an independently demonstrated defect requires a narrowly scoped proposal.

## Non-goals for first milestone
- No automatic BPCells conversion; no save helper, placeholder generator, or manifest writer yet.
- No persistent cache, external file lifecycle manager, reference counting, explicit deletion, or custom lazy-binding framework.
- No support for Seurat, AnnData, arbitrary SummarizedExperiment, or multiple object outputs.
- No silent loss or conversion of alternative assays. Report unsupported states clearly.

## Engineering standards
- Prefer exported APIs to `:::`; inspect source only to understand behavior, not to couple to private implementation.
- Use `testthat` and temporary fixture libraries/packages; clean up only disposable source/test directories, never a live object's backing files mid-session.
- Validate path containment and installed layout carefully; avoid fixed names such as `tempdir()/BPCells` that collide across resources.
- Check optional dependencies and error messages. The adapter package should not unexpectedly attach Monocle or projectData onto the user's search path.
- Do not assert that disk-backed means RAM-free: just that matrix data can remain on disk.
- Update README and this AGENTS.md when architecture decisions change; document remaining uncertainties explicitly.

## Phase 1 status and verified findings (monocle3 1.4.27, BPCells 0.3.0, projectData 0.0.0.9005)

Implemented: `projectData_loaders()` (exported), internal `validate_monocle_cds()` / `validate_file_index()` / `open_monocle_cds()` / `with_attached()` / `is_scalar_string()`. Tests: `tests/testthat/` (declaration, validate on synthetic dirs, end-to-end with real CDS in disposable installed libraries). `R CMD check` with `NOT_CRAN=true`: Status OK, 87 expectations, 0 skipped.

- `monocle3` and `BPCells` are `Suggests` + `Remotes` (GitHub-only), checked with `requireNamespace()` in `open()` with an actionable message. `validate` needs neither.
- `load_monocle_objects()` **copies** the BPCells dir; `matrix_path` must exist and monocle3 creates `monocle.bpcells.<date>.<id>.tmp` children (counts and a `_r` row-order copy). `paths$work_dir` is therefore passed directly as `matrix_path`, via `monocle3::set_matrix_control()` to fill required defaults (a partial `matrix_control` is rejected). Default `matrix_path` is `"."` (cwd), so it must always be set.
- monocle3 unlinks those dirs at R exit via its own hook; the adapter does not delete anything.
- `load_monocle_objects()` needs monocle3 (Depends) attached (`assay` is called unqualified). `with_attached()` attaches for the call and detaches only what it newly attached.
- Validation requires `file_index.rds` (`save_function == "save_monocle_objects"`), exactly one rds CDS, exactly one `bpcells_matrix_dir`, relative contained paths, all files present. In-memory-counts saves and hdf5 saves are rejected (design choice: loader is declared disk-backed).
- Saves must use `archive_control = list(archive_type = "none")`; the default makes a tar.
- Independence: counts and row-order copy are in `work_dir`. The UMAP Annoy index is memory-mapped from the installed file (not copied); survives unlink on Linux (tested), not guaranteed elsewhere. `model_path` identity metadata records the install path but is informational.
- No incompatibility with `projectData` found; no changes to it. Notes: a validate rejection happens before `on_open`; catalog `storage` reads `unknown` (loader_status `unresolved`) until the loader is registered; a failed `data_get(package=)` leaves the collection registered but unattached, so retry with `package=`.

## Manifest generation (0.0.0.9003, implemented)

Exported `write_monocle_manifest(package_dir = ".")` (R/write_manifest.R); internal `discover_monocle_resources(package_dir)`, `inspect_rda()`, `placeholder_recognizers()` (R/discover.R). `R CMD check` and all tests pass; the end-to-end test regenerates the manifest of a disposable copy of `projectData.monocle3.testdata`, installs it and opens a CDS.

- **Loader unchanged and still has no `discover`.** A `discover` would run at every `data_attach()` (runtime scanning, excluded). Discovery lives in the authoring function only; descriptors are built as plain lists in the documented shape and serialized by `projectData::data_manifest_write()`.
- **Recognizing a saved CDS directory:** a direct child of `inst/extdata/` is a *candidate* if it contains `file_index.rds`, `cds_object.rds` or `bpcells_matrix_dir`; it is *accepted* only if the loader's own `validate_monocle_cds()` passes (run with root `inst/` and source `extdata/<name>`), so authoring and runtime checks cannot drift. A bare `bpcells_matrix_dir` is a candidate that is rejected (`invalid_cds`) for lacking `file_index.rds`. Directories with none of the markers are ignored silently. Names must be syntactic R names. Only `file_index.rds` is read (via `readRDS`, same as the loader).
- **Placeholders:** `data/<name>.(rda|RData|rdata)`. `inspect_rda()` parses the XDR stream header by hand (object name, whether it is the only object, and for a small character vector its value and attributes) via `gzfile()`, which handles gzip/bzip2/xz/none. Nothing is unserialized or evaluated; a real dataset is rejected after its first few bytes. ASCII/native-format files and anything unexpected are reported as not-a-placeholder, never accepted. Recognition is a list of recognizer functions `f(info, name)` in `placeholder_recognizers()`; only the legacy `"This is a placeholder object."` (unclassed, length 1) exists. **To support the future classed placeholder, add a recognizer there** (info$attributes$class is available).
- **Discovery statuses:** `discovered`, `invalid_cds`, `no_placeholder`, `not_placeholder`, `bad_placeholder`. Report statuses: `added`, `updated`, `unchanged`, `skipped`, `conflict`. Skips and conflicts raise classed warnings (`projectData.monocle3_skipped`/`_conflict`).
- **Existing manifest:** read with `data_manifest_validate()` (an invalid manifest aborts, file untouched). The adapter loader is registered temporarily so its validation also runs, and removed afterwards only if this call added it. Other entries pass through with all fields and order; new entries append. A same-resource entry of another loader, or an object name already declared by another resource, is a `conflict` and left as is. An existing entry of our loader is updated in loader/source/objects/adapter/recorded_class (and HelpTopic only if missing); Title and Options are kept.
- **Writing:** only when something was added/updated, via `data_manifest_write(overwrite = file.exists())`, which validates, round-trips and renames from a temp file in the same directory (atomic). Unchanged runs do not touch the file. The writer re-emits every record in its canonical field order, so formatting of *untouched* entries is normalized when another entry is added; semantics are preserved. It omits `AdapterExport` when it equals the default, so generated entries lack that line (reads back identically; the old hand-written testdata manifest has it and is judged `unchanged`).
- **Limits:** an existing invalid Monocle entry (e.g. stale Source) makes the whole call fail rather than being repaired; stale entries for deleted directories are not removed; one resource per directory only; top-level directories of `inst/extdata/` only.
- **Test fixtures:** `tests/testthat/helper-authoring.R` (synthetic trees), `test-discover.R`, `test-write-manifest.R`, `test-write-manifest-integration.R` (needs the testdata *source* via `PDM3_TESTDATA_SOURCE` or a sibling directory; skips otherwise).
- **For `save_monocle_cds()`:** call `write_monocle_manifest()` (or factor out `plan_manifest()` + the write step) after saving the directory and creating the placeholder; the placeholder recognizer for the new class must be added first so it is accepted.

## Phase 2 TODO
`save_monocle_cds()`, optional BPCells conversion, placeholder generator (the matching/recognition and manifest writing now exist), placeholder-vs-manifest precedence tests, alternative-assay round-trip tests, Windows/macOS verification, decision on persistent cache.
