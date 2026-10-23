# projectData.monocle — Project memory and engineering guidance

## Purpose
Build `projectData.monocle`, a separate R package that integrates disk-backed Monocle 3 `cell_data_set` (CDS) objects with `projectData`. Distribute initially through GitHub and R-universe. Keep the `projectData` core independent of Monocle and BPCells.

## Source of truth
- Target core: `projectData` version `0.0.0.9005`; consult its current source before depending on undocumented internals.
- Read `projectData` vignette `vignettes/adapters.Rmd`, especially the version-1 loader contract and manifest authoring rules.
- Historical reference implementations: `blaserlab/blaseRtools` files `R/save_monocle_disk.R` and `R/project_data.R`. Preserve their *goals*, not their older implementation details.
- Consult the installed versions/source of `monocle3` and `BPCells` before assuming arguments, serialization layout, or copying semantics.

## Settled architecture
- Separate adapter package named `projectData.monocle` (working name).
- Loader ID: `projectData.monocle::cds`; export `projectData_loaders()` to return a `projectData::data_loader()` or list thereof.
- Loader must use existing `data_loader(open, discover, validate, storage, needs_work_dir)` version-1 contract, with `storage = "disk-backed"` and `needs_work_dir = TRUE`.
- Manifest (`inst/projectData/manifest.dcf`) identifies each CDS resource, its source under `extdata/`, object name, loader, and `AdapterPackage`/`AdapterExport`. Use source paths in the **installed** layout (`extdata/name`, not `inst/extdata/name`).
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
