# CI only: pins the GitHub entries of DESCRIPTION's Remotes to the refs the
# workflow tests, so every run installs the same monocle3 and BPCells. The
# package itself keeps unpinned Remotes (users get the current default branch).
# Rewrites DESCRIPTION in the CI checkout; never run it in a working copy you
# want to keep.
#
#   MONOCLE3_REF=v1.4.27 BPCELLS_REF=v0.3.1 Rscript tools/ci-pin-remotes.R

pins <- c(
  "cole-trapnell-lab/monocle3" = Sys.getenv("MONOCLE3_REF"),
  "bnprks/BPCells/r" = Sys.getenv("BPCELLS_REF")
)
if (any(!nzchar(pins))) stop("Set MONOCLE3_REF and BPCELLS_REF.")

desc <- read.dcf("DESCRIPTION", keep.white = "Remotes")
remotes <- trimws(strsplit(desc[1, "Remotes"], ",")[[1]])
remotes <- remotes[nzchar(remotes)]
for (repo in names(pins)) {
  i <- grep(paste0("^github::", repo, "(@.*)?$"), remotes)
  if (length(i) != 1L) stop("Remotes must contain exactly one entry for ", repo, ": ", paste(remotes, collapse = ", "))
  remotes[[i]] <- paste0("github::", repo, "@", pins[[repo]])
}
desc[1, "Remotes"] <- paste(remotes, collapse = ", ")
write.dcf(desc, "DESCRIPTION", keep.white = "Remotes")
cat("Remotes:", desc[1, "Remotes"], "\n")
