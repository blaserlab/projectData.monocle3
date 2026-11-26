# projectData.monocle3 0.0.0.9013

Cross-platform CI and dependency compatibility. No change to production code,
the public API, the serialization format or the loader contract.

* **CI:** `.github/workflows/R-CMD-check.yaml` runs the strict self-contained
  integration suite (`PDM3_INTEGRATION_TESTS=true`) and `R CMD check --as-cran`
  on Ubuntu, Windows and macOS (R release) and Ubuntu with R 4.5, with
  `projectData` from CRAN and monocle3 and BPCells from GitHub at pinned tags
  (`tools/ci-pin-remotes.R`; DESCRIPTION itself stays unpinned). A second job
  runs `R CMD check` without the Monocle stack (skips expected).
  `.github/workflows/compat-matrix.yaml` runs the suite for each configuration of
  `tools/compat-matrix.R` (`legacy`: projectData 0.0.0.9008 with BPCells 0.3.0;
  `bpcells_030`), a separate Linux job with the historical fixtures from the
  pinned commit of `projectData.monocle3.testdata`, and an allowed-failure job
  against BPCells main. **No workflow has run yet:** see the README compatibility
  table for what has actually been verified.
* **Tools:** `tools/compat-matrix.R` (strict run per configuration; a declared
  version mismatch, a failure or an unlabelled skip fails it), `tools/compat-libs.R`
  (builds the alternative libraries), `tools/verify-stack.R`,
  `tools/ci-pin-remotes.R`. `tools/` and `.github/` are build-ignored.
* **DESCRIPTION:** `github::blaserlab/projectData` removed from `Remotes`:
  projectData 0.1.0 on CRAN satisfies `projectData (>= 0.0.0.9005)` and the
  whole suite passes against it. `monocle3` and `BPCells` are still GitHub-only.
* **Tests:** new `test-e2e-dependency-contract.R` states the assumptions about
  monocle3 and BPCells (native index layout, BPCells directory files, the
  `matrix_control` interface, restored matrices under the work directory) so that
  an upgrade that changes one fails with a message naming it. The symbolic-link
  tests are no longer skipped by operating system: they run wherever links can be
  created and `Sys.readlink()` reports them (`skip_if_no_symlinks()`; a skip is
  labelled as a platform skip). `system2(env = )` (which does not work on
  Windows) replaced by `withr::with_envvar()` in the helpers that start R
  subprocesses. The test that deletes an installed resource while an UMAP index
  is mapped is a labelled Windows platform skip.

# projectData.monocle3 0.0.0.9012

Test infrastructure only: no change to production code, the public API, the
serialization format or the loader contract.

* New self-contained end-to-end suite (`test-e2e-*.R`, `helper-synthetic.R`,
  `child-probe.R`) that needs no `projectData.monocle3.testdata`: a small
  deterministic synthetic CDS (sparse integer counts, metadata, `logcounts` and
  `spliced` assays, an ADT alternative experiment, PCA/UMAP reductions) is
  authored into a generated data package with `save_monocle_cds()` (in-memory
  counts that are converted automatically, and BPCells-backed counts), built
  with `R CMD build`, installed with `R CMD INSTALL` into two temporary
  libraries and loaded through projectData. Covered: layout, placeholders,
  manifest and idempotent `write_monocle_manifest()`; discovery without opening;
  exact reconstruction; `data_attach()`/`data_detach()`; work-directory and
  backing-file lifecycle; fresh-process loading from each library and through a
  symbolic link; independence from the authoring directory; and failure and
  `data_retry()` recovery (missing resource directory, `file_index.rds` or
  BPCells file, invalid manifest source, unsupported external assay, failed
  restoration, missing optional dependency) on disposable copies.
* The tests that use `projectData.monocle3.testdata` are now the *historical
  compatibility* family, renamed `test-historical-*.R` (contents unchanged
  apart from gating). Fixture identity is a version floor (0.0.0.9004 or later)
  plus checksums of each resource instead of an exact version.
* **Behavior change in test gating:** strictness has two independent switches.
  `PDM3_INTEGRATION_TESTS=true` makes the self-contained tests mandatory and
  no longer requires the fixture package; the new
  `PDM3_HISTORICAL_TESTS=true` makes the historical tests mandatory (fixture
  package, `PDM3_TESTDATA_SOURCE`, content match). Set both for the previous
  "full integration run". Without the fixture package the historical tests skip
  with a `[historical fixtures]` reason, or fail under `PDM3_HISTORICAL_TESTS=true`.
* `pkgload` added to `Suggests` (fresh-process tests under `devtools::test()`).

# projectData.monocle3 0.0.0.9011

Filesystem and symbolic-link safety. No change to the serializer, the resource
layout, the loader contract, the public signatures, manifest reconciliation or
the overwrite ownership rule; resources written by earlier versions keep
working.

* Confirmed risks: monocle3 and BPCells follow symbolic links when they copy a
  matrix directory (verified on load and, through `write_matrix_dir()`, on
  save) and never complain about links that leave the directory, so a link in an
  author's counts directory or in an installed resource would put the bytes of
  an unrelated file into the data package or into the work directory.
  `list.files(recursive = TRUE)`, used by the ownership check, also follows link
  cycles.
* One rule, in the new `R/filesystem.R`, shared by `validate`, `open`,
  authoring and ownership: nothing inside a saved Monocle directory or an
  external BPCells directory may be a symbolic link (internal, escaping or
  dangling), and a BPCells directory must be flat, with the files BPCells
  writes. Trees are walked without following links and with a bound on the
  number of entries. The directory a path starts from, the library, and parents
  such as `inst/extdata` may be symbolic links.
* **Behavior change:** the loader previously accepted a link that stayed inside
  the resource; it now refuses all links inside a resource (a resource written
  by `save_monocle_cds()` never has one). `validate` also now requires the
  listed BPCells directory to hold the files BPCells writes (previously an empty
  directory passed), requires listed non-matrix paths to be files, and rejects a
  manifest `Source` that is absolute or contains `..`.
* `file_index.rds` path rules now use the same `is_plain_relative()` as
  everything else; the earlier inline copy accepted UNC paths such as
  `\\server\share`.
* `save_monocle_cds()` judges the author's counts directory before staging
  anything and refuses it with `projectData.monocle3_unsafe_backing` (a missing
  directory, which Monocle would only warn about, is now caught here too). A
  symbolic link (or dangling link) in place of `inst/extdata/<name>` or of the
  placeholder, or a link anywhere inside an existing `inst/extdata/<name>`, is
  refused (`projectData.monocle3_not_owned`) before anything is written.
* The staging directory is created exclusively, checked to lie in the package,
  and removed only if this call created it, without following links.
  `open_monocle_cds()` repeats the directory check and refuses a work directory
  inside the installed resource. A dangling placeholder link no longer emits a
  gzfile warning from `inspect_rda()`.
* Tests: `test-filesystem.R` (synthetic trees and real fixtures; symbolic
  links, containment, entry types, spaces and non-ASCII paths, symlinked
  libraries, commit failure and failed restore, retained objects, two resources
  loaded from a read-only symlinked library). `helper-authoring.R` fake saves now
  contain a BPCells-looking directory.

# projectData.monocle3 0.0.0.9010

* Stricter overwrite authorization in `save_monocle_cds()`. Previously an
  existing `inst/extdata/<name>` was replaceable with `overwrite = TRUE` if it
  held any one of `file_index.rds`, `cds_object.rds` or `bpcells_matrix_dir`
  (or was empty); these names only identify a *candidate*. Now at least two of
  a native Monocle file index, a manifest entry of this loader and a recognized
  placeholder are required, nothing unaccounted for may be in the directory, and
  a manifest entry of another loader (or one that disagrees with the directory)
  always refuses. Damaged saves are recoverable when that evidence exists. The
  manifest is read before the targets are judged, and every refusal happens
  before anything is staged. New error classes (all also
  `projectData.monocle3_save_error`): `_exists`, `_damaged`, `_not_owned`,
  `_ambiguous_ownership`, `_placeholder_not_recognized`; `_conflict` now also
  covers an existing directory. Resources made by earlier versions keep working
  (classed or historical placeholder, with or without a manifest entry). No
  change to the signature, return value, serialization or loader.

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
