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
