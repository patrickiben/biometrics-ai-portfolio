################################################################################
# study/R/snapshot_lock.R: rewrite study/renv.lock from the packages this example uses.
# renv scans the study/ code for library(), require() and pkg:: calls ("implicit"
# snapshot) and records the installed version of each package and its dependencies.
# Minimal records (lockfile version 1): package, version, source, repository, hash.
#   Rscript study/R/snapshot_lock.R        (from the repository root)
################################################################################
options(repos = c(CRAN = "https://cloud.r-project.org"), renv.lockfile.version = 1)
renv::snapshot(project = "study", library = .libPaths(), lockfile = "study/renv.lock",
               type = "implicit", prompt = FALSE, force = TRUE)
