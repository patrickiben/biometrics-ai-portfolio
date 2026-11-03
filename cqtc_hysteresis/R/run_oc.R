################################################################################
# cqtc_hysteresis/R/run_oc.R
# Operating characteristics (OC) of the C-QTc hysteresis check on synthetic data.
# 1,000 replicates per scenario (MCSE 0.007 at a rate of 0.05). Scenario k (its
# position in SCEN below, k = 1, 2, ...) is seeded with 20261025 + k so that each
# scenario reproduces on its own; the worked example uses 20261025 and the F2
# figure data 20261025 + 900.
#
# Run from the repository root:
#   Rscript cqtc_hysteresis/R/run_oc.R              # simulate, write out/, build index.html
#   Rscript cqtc_hysteresis/R/run_oc.R --page-only  # rebuild index.html from out/
#   Rscript cqtc_hysteresis/R/run_oc.R --reps 200   # quicker run (writes to a temp dir)
# Base R only (nlme is used only in the tests). About 3 minutes on a laptop.
################################################################################

args <- commandArgs(trailingOnly = FALSE)
here <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", args, value = TRUE)[1])))
MOD  <- normalizePath(file.path(here, ".."))
source(file.path(here, "sim.R")); source(file.path(here, "area.R")); source(file.path(here, "page.R"))

targs <- commandArgs(trailingOnly = TRUE)
REPS  <- if ("--reps" %in% targs) as.integer(targs[which(targs == "--reps") + 1]) else 1000L
PAGE_ONLY <- "--page-only" %in% targs
OUT <- if (REPS == 1000L) file.path(MOD, "out") else file.path(tempdir(), "cqtc_out")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

SEED   <- 20261025L
ALPHA  <- 0.05
B_SF   <- 9999L     # random sign vectors when n > 20 (exact enumeration otherwise)
B_BOOT <- 999L      # parametric bootstrap draws
RNGkind("Mersenne-Twister", "Inversion", "Rejection")

source(file.path(here, "oc_core.R"))

## ---- write ------------------------------------------------------------------------
fmt_df <- function(df, digits = 4) {             # fixed decimals so outputs are byte-stable;
  for (nm in names(df)) if (is.double(df[[nm]])) { # integer columns (n, seeds, counts) stay integers
    v <- formatC(round(df[[nm]], digits) + 0, format = "f", digits = digits)   # "+ 0": no "-0"
    v[is.na(df[[nm]])] <- NA
    df[[nm]] <- v
  }
  df
}
if (!PAGE_ONLY) {
  cat(sprintf("C-QTc hysteresis OC: %d replicates per scenario, scenario k seeded with %d + k\n", REPS, SEED))
  oc <- run_all()
  write.csv(fmt_df(oc), file.path(OUT, "oc_results.csv"), row.names = FALSE)
  write.csv(fmt_df(noise_free()), file.path(OUT, "noise_free_areas.csv"), row.names = FALSE)
  write.csv(fmt_df(example_check()), file.path(OUT, "example_check.csv"), row.names = FALSE)
  writeLines(c("{",
    sprintf('  "generated_by": "cqtc_hysteresis/R/run_oc.R",'),
    sprintf('  "seed": %d,', SEED), sprintf('  "replicates": %d,', REPS),
    sprintf('  "scenario_seeds": "scenario k uses %d + k (column seed in oc_results.csv)",', SEED),
    sprintf('  "pooled_placebo_n_default": 8,'),
    sprintf('  "primary_test": "placebo-adjusted t (Welch-Satterthwaite df)",'),
    sprintf('  "alpha": %.2f,', ALPHA), sprintf('  "sign_vectors_monte_carlo": %d,', B_SF),
    sprintf('  "exact_enumeration_max_n": 20,'), sprintf('  "bootstrap_draws": %d,', B_BOOT),
    sprintf('  "r_version": "%s",', R.version.string),
    sprintf('  "data": "synthetic only; not trial data"'), "}"), file.path(OUT, "oc_meta.json"))
}
if (REPS == 1000L) {
  build_page(MOD)
  cat("Wrote", file.path(MOD, "out"), "and", file.path(MOD, "index.html"), "\n")
} else cat("Wrote", OUT, "(reps != 1000, so the committed page is not rebuilt)\n")
