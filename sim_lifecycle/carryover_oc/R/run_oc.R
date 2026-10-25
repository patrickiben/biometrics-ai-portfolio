#!/usr/bin/env Rscript
################################################################################
# carryover_oc/R/run_oc.R: run the full operating-characteristics grid and the ADaM
# single-study demonstration. SYNTHETIC DATA ONLY. Exploratory (synthetic); not a validated
# method and not regulatory guidance.
#
#   Rscript sim_lifecycle/carryover_oc/R/run_oc.R        (from the repository root)
#   OC_CORES=1 Rscript ...                                (serial; same results)
#
# Grid: theta in {0.80, 0.95, 1.00, 1.25} x disposition in {mono, biexp} (8 cells, one
# L'Ecuyer-CMRG stream each, seed 20261025) x W / t1/2 in {2, 3, 4, 5, 6, 8, 10} plus the
# KA1 control (W = 10 x the largest individual t1/2) x 3 configurations (base, assay error,
# extended sampling) x 6 arms. Within a cell every washout, arm and configuration reuses the
# same simulated participants (common random numbers), so results do not depend on the
# number of cores.
# Replicates: sized from a target MCSE of 0.005 for a rate of 0.05 (1,900, rounded up to 2,000).
# Outputs (out/): oc_results.csv, oc_bias_decomposition.csv, run_info.csv, adam_demo/adpc.csv and adpp.csv.
# Then run tests/test_carryover.R and R/tables.R (tables, figures, page).
################################################################################
args <- commandArgs(trailingOnly = FALSE)
me <- sub("^--file=", "", args[grep("^--file=", args)])
mod <- if (length(me)) dirname(dirname(normalizePath(me))) else normalizePath("sim_lifecycle/carryover_oc")
setwd(dirname(dirname(mod)))                                   # repository root
for (f in c("dgm.R", "nca_m13a.R", "analyze.R")) source(file.path(mod, "R", f))
out_dir <- file.path(mod, "out"); dir.create(out_dir, showWarnings = FALSE)

set <- oc_settings(); configs <- oc_configs(set); cells <- oc_cells()
R <- reps_for_mcse(p = 0.05, target = 0.005)                   # 2000
cores <- max(1L, as.integer(Sys.getenv("OC_CORES", "4")))
streams <- oc_streams(nrow(cells))
use_stream(streams[[nrow(cells) + 1L]]); lloq <- lloq_from_population(100000L, set)

cat(sprintf("Residual-carryover OC grid: %d cells x %d washouts (+ KA1 control) x %d configurations x %d arms, R = %d per cell (MCSE %.4f at a rate of 0.05), %d core(s)\n",
            nrow(cells), length(OC_WASHOUTS), length(configs), length(OC_ARMS), R, mcse_rate(0.05, R), cores))
work <- function(i) {
  use_stream(streams[[i]])
  pop <- draw_population(R, set)
  run_cell(pop, cells$theta[i], cells$disposition[i], configs, OC_WASHOUTS, lloq, adequate = TRUE, set)
}
t0 <- proc.time()[["elapsed"]]
res <- if (cores > 1) {
  parallel::mclapply(seq_len(nrow(cells)), work, mc.cores = cores, mc.preschedule = FALSE)
} else lapply(seq_len(nrow(cells)), work)
bad <- vapply(res, function(x) inherits(x, "try-error") || is.null(x$results), logical(1))
if (any(bad)) stop("cell(s) failed: ", paste(which(bad), collapse = ", "), "\n", paste(unlist(res[bad]), collapse = "\n"))
elapsed <- proc.time()[["elapsed"]] - t0

results <- do.call(rbind, lapply(res, `[[`, "results"))
decomp  <- do.call(rbind, lapply(res, `[[`, "decomposition"))
results$arm_label <- unname(OC_ARMS[results$arm])
write_oc_csv(results, file.path(out_dir, "oc_results.csv"))
write_oc_csv(decomp,  file.path(out_dir, "oc_bias_decomposition.csv"))
write_oc_csv(data.frame(
  item = c("R version", "RNG", "seed", "replicates per cell", "MCSE of a rate of 0.05", "largest MCSE of a rate (at 0.5)",
           "participants per study", "cells", "configuration-B LLOQ (0.5% of median Cmax)", "cores", "grid run time (s)", "run date"),
  value = c(R.version.string, "L'Ecuyer-CMRG, one parallel::nextRNGStream per (theta, disposition) cell", OC_SEED, R,
            sprintf("%.4f", mcse_rate(0.05, R)), sprintf("%.4f", mcse_rate(0.5, R)), set$n, nrow(cells),
            sprintf("%.6g", lloq), cores, sprintf("%.1f", elapsed), format(Sys.Date()))),
  file.path(out_dir, "run_info.csv"))
cat(sprintf("Grid finished in %.1f s; wrote oc_results.csv (%d rows) and oc_bias_decomposition.csv (%d rows)\n",
            elapsed, nrow(results), nrow(decomp)))

## --- headline numbers (base configuration, monoexponential, AUC(0-t)) ------------------
hd <- results[results$config == "base" & results$disposition == "mono" & results$endpoint == "AUC" &
              results$theta == 1.25 & results$arm %in% c("A0", "A1", "A2", "A3"), ]
for (w in c("2", "3", "5")) {
  h <- hd[hd$washout == w, ]
  cat(sprintf(" theta 1.25, W = %s t1/2: consumer risk %s; M13A rule excludes %.0f%% of participants, %.1f%% of studies not evaluable\n", w,
              paste(sprintf("%s %.3f (%.3f)", h$arm, h$be_rate, h$be_rate_mcse), collapse = ", "),
              100 * h$excl_frac[h$arm == "A2"], 100 * h$noneval_rate[h$arm == "A2"]))
}

## --- ADaM single-study demonstration (sim_lifecycle generator with washout_h set) -----
## The sandbox's own PK model (median t1/2 about 8 h) with a 48 h washout, about six median
## half-lives. The generator draws with R's default RNG, as in sim_lifecycle/run_lifecycle.R.
RNGkind("Mersenne-Twister", "Inversion", "Rejection")
source("sim_lifecycle/simulate_adam.R")
demo <- simulate_study(sample_design(archetype = "BE", N = 40), seed = 2026, washout_h = 48)
dd <- file.path(out_dir, "adam_demo"); dir.create(dd, showWarnings = FALSE)
## only ADPC and ADPP change; the other six domains equal sim_lifecycle/out (test T10 checks this)
for (nm in c("adpc", "adpp")) write_oc_csv(demo[[nm]], file.path(dd, sprintf("%s.csv", nm)))
x <- demo$adpp[demo$adpp$PARAMCD == "PDCMXR" & demo$adpp$APERIOD == 2, ]
cat(sprintf("ADaM demonstration (washout_h = 48): %d of %d participants have a period-2 pre-dose above 5%% of Cmax and are excluded from the bioequivalence analysis (ANL02FL null); written to out/adam_demo/\n",
            sum(x$AVAL > 0.05), nrow(x)))
