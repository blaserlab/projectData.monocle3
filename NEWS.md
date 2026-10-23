# projectData.monocle3 0.0.0.9004

* New exported `save_monocle_cds(cds, name, package_dir, convert_to_bpcells,
  overwrite)`. One call validates the inputs, saves the CDS with
  `monocle3::save_monocle_objects()` (no archive) under `inst/extdata/<name>/`,
  writes the mandatory `data/<name>.rda` placeholder and registers the
  resource in `inst/projectData/manifest.dcf` using the same planning and
  writing code as `write_monocle_manifest()`.
* Placeholder: a named character vector of instructions (one per element),
  class `projectData_monocle3_placeholder`, attributes `object_name` and
  `package`; legible with base R printing alone. Discovery recognizes it in
  addition to the legacy string.
* Files are staged in a hidden directory, verified with the loader's
  validation, then moved into place with the previous files kept aside; failures
  restore them. Existing targets need `overwrite = TRUE`, and real datasets or
  foreign directories are never replaced.
* Optional `convert_to_bpcells = TRUE` converts `counts` of a copy with
  `monocle3::convert_counts_matrix()` into a session temporary directory.
  In-memory counts without conversion are rejected before writing.
* On-disk (BPCells) alternative assays raise a
  `projectData.monocle3_external_assay` warning; in-memory ones are preserved.
* Internal: `with_loader_registered()` and `write_planned_manifest()` factored
  out of `write_monocle_manifest()`. No loader changes.

# projectData.monocle3 0.0.0.9003

* New exported `write_monocle_manifest(package_dir = ".")` for data-package
  authors. It discovers saved Monocle CDS directories under `inst/extdata/`,
  pairs each with a `data/<name>.rda` placeholder, and creates or updates
  `inst/projectData/manifest.dcf` through `projectData::data_manifest_write()`.
  Existing entries of other loaders are preserved, conflicts are reported and
  left unchanged, an unchanged manifest is not rewritten, and nothing is
  loaded during discovery.
* Placeholders are verified by parsing the `.rda` serialization header, without
  evaluating anything. The legacy string `"This is a placeholder object."` is
  recognized; further representations can be added as recognizers.
* Added unit tests (synthetic and real fixtures) and an end-to-end test that
  regenerates the manifest of a disposable copy of
  `projectData.monocle3.testdata`, installs it and opens a CDS through
  `projectData`. No loader changes.

# projectData.monocle3 0.0.0.9002

* Added integration tests against the installed `projectData.monocle3.testdata`
  fixture package (two BPCells-backed CDS resources, one ordinary data frame).
  They cover `.rda` placeholder behavior, manifest-over-index resolution in
  `data_catalog()`, lazy opening (via `data_config(on_open =)` and catalog
  state), BPCells `MatrixDir` counts, restoration under the allocated
  `projectData-work` directory with the installed package and `getwd()`
  untouched, use of a retained CDS after `data_detach()`, reattachment, and
  ordinary dataset compatibility. Tests skip when `projectData`, the fixture
  package, `monocle3`, `BPCells`, `SummarizedExperiment` or `withr` is
  unavailable. No loader changes.

# projectData.monocle3 0.0.0.9001

* Phase 1: loader-only adapter. `projectData_loaders()` declares
  `projectData.monocle3::cds`, which validates and opens one saved,
  BPCells-backed Monocle 3 CDS per manifest resource.
