# projectData.monocle3 0.0.0.9009

* New vignette, "Using Monocle 3 Data with projectData"
  (`vignette("using-monocle3-data")`), covering the authoring and consumer
  workflows, lazy restoration, working-directory and backing-file lifetime,
  supported assays and common failure modes. The README links to it.
* `knitr` and `rmarkdown` added to `Suggests`, with `VignetteBuilder: knitr`.
  No functions, arguments or loader behaviour changed.
* Documentation only: the directory-tree illustrations in the help pages of
  `save_monocle_cds()` and `write_monocle_manifest()` now use ASCII characters
  (`|--`, `` `-- ``, `|`) instead of Unicode box-drawing characters, which
  LaTeX could not typeset and which made the PDF reference manual fail to build
  under `R CMD check --as-cran`.

# projectData.monocle3 0.0.0.9008

* Test infrastructure only: `PDM3_INTEGRATION_TESTS=true` starts a documented
  full integration run in which missing or incompatible prerequisites
  (`projectData.monocle3.testdata` 0.0.0.9004 and its structure, the Monocle
  stack, `PDM3_TESTDATA_SOURCE` and its agreement with the installed fixtures)
  fail instead of skipping. Ordinary runs keep their skips. No API changes.

* `file_index.rds` validation is more defensive: `cds_object`, `file_format` and
  `file_path` must be non-missing, non-empty character columns, duplicate paths
  are rejected, and indexed paths are resolved (following symlinks) and must
  stay inside the saved directory. Malformed indexes now give validation
  messages instead of base R errors. No format, API or loader changes.

# projectData.monocle3 0.0.0.9007

* `save_monocle_cds()` now **errors** (class `projectData.monocle3_external_assay`,
  before anything is written) when a secondary assay is independently
  disk-backed, instead of warning and saving a data package with dangling
  references. Alternative experiments are inspected recursively; the error names
  each location (e.g. `altExp 'ADT' / altExp 'normalized' / assay 'counts'`).
  Monocle-managed `counts` and `counts_row_order` of the main CDS and all
  in-memory assays are unaffected. No signature, loader or manifest changes.
* README brought up to date; new regression tests in `test-save-external-assays.R`.

# projectData.monocle3 0.0.0.9005

* `write_monocle_manifest()` now reconciles the manifest with the package. Entries
  owned by this package (loader `projectData.monocle3::cds`) whose saved CDS
  directory or placeholder no longer exists are removed as stale, so deleting a
  saved directory by hand no longer makes the next call fail. New valid resources
  are added, current ones updated, and entries of other adapters are preserved
  unchanged. The existing manifest is read with structural checks only (it need
  not pass source-existence validation); the complete proposed manifest is
  validated and written atomically only if valid. A malformed manifest, or an
  invalid entry of another adapter, stops the call and is left untouched. When no
  entry remains the manifest file is removed. Directories and placeholders are
  never deleted. A concise summary is printed only when the manifest changes.
* `save_monocle_cds()` uses the same reconciliation (one implementation, shared
  with `write_monocle_manifest()`), after the CDS and placeholder are in place;
  the result gains `removed_stale`. Entries of other adapters that fail validation
  stop the save before anything is written.
* **Breaking:** `save_monocle_cds()` no longer has `convert_to_bpcells`. Counts
  are inspected: on-disk BPCells counts are saved as they are, in-memory counts
  (dgCMatrix/dgTMatrix or a BPCells in-memory matrix) are converted automatically
  on a copy with `monocle3::convert_counts_matrix()`, and anything else
  (dense, DelayedArray, HDF5-backed) is an error before writing.
* New tests: reconciliation (stale directories and placeholders, unrelated and
  conflicting entries, malformed manifests, idempotence, empty result), automatic
  conversion, and round trips of extra assays and ADT/CRISPR alternative
  experiments. No loader changes.

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
