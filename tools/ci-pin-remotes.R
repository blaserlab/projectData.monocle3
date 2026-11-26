# CI only: pins the GitHub entries of DESCRIPTION's Remotes to the refs the
# workflow tests. Only monocle3 is pinned: monocle3's own DESCRIPTION lists
# BPCells/r (unpinned) in Remotes, and pak reports a dependency conflict when this
# package pins BPCells to a tag or commit (verified: pak 2026-11). BPCells is
# therefore whatever the default branch is; verify-stack.R prints its version and
# commit and compat-matrix.R checks the version prefix. A specific BPCells version
# is tested through tools/compat-libs.R instead. The package itself keeps
# unpinned Remotes.
# Rewrites DESCRIPTION in the CI checkout; never run it in a working copy you
# want to keep.
#
#   MONOCLE3_REF=v1.4.27 Rscript tools/ci-pin-remotes.R

pins <- c("cole-trapnell-lab/monocle3" = Sys.getenv("MONOCLE3_REF"))
if (any(!nzchar(pins))) stop("Set MONOCLE3_REF.")

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
