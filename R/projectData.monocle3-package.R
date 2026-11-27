#' @details
#' `projectData.monocle3` is an adapter for the \pkg{projectData} framework. It
#' lets an R data package ship a Monocle 3 `cell_data_set` (CDS) whose counts are
#' a BPCells on-disk matrix, and has projectData restore it on first access from
#' any library, without attaching Monocle 3 or this package. An adapter is needed
#' only for such disk-backed objects: a CDS that fits in memory can be shipped as
#' an ordinary `.rda` dataset.
#'
#' **Users of a data package** need no function from this package. The data
#' package's manifest names the loader `projectData.monocle3::cds`
#' ([projectData_loaders()]); use [projectData::data_attach()] or
#' [projectData::data_get()]. Opening a CDS needs monocle3 and BPCells, which
#' are suggested, not required, so that registration and validation work
#' without them.
#'
#' **Authors of a data package** use [save_monocle_cds()] (save a CDS, write the
#' mandatory `.rda` placeholder and register the manifest entry, converting
#' in-memory counts to BPCells automatically) and [write_monocle_manifest()]
#' (reconcile the manifest with the saved directories).
#'
#' @section Vignettes:
#' * `vignette("authoring-monocle3-data")`: create and install a data package.
#' * `vignette("using-monocle3-data")`: discover, load, detach and troubleshoot.
#' * `vignette("storage")`: what is stored, what loading copies, and lifetimes.
#'
#' For the adapter mechanism see `vignette("adapters", package = "projectData")`.
#'
#' @section Condition classes:
#' Authoring errors have class `projectData.monocle3_save_error`, with one of
#' `_exists`, `_damaged`, `_not_owned`, `_ambiguous_ownership`, `_conflict`,
#' `_placeholder_not_recognized`, `_external_assay`, `_unsafe_backing` or
#' `_manifest_error`. A bad `package_dir` gives
#' `projectData.monocle3_package_dir_error`. See [save_monocle_cds()] and
#' [write_monocle_manifest()].
#'
#' @keywords internal
"_PACKAGE"
