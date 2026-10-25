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

## ---- scenarios -------------------------------------------------------------------
## Every scenario has n active participants and, unless placebo = "within", a pooled
## placebo group of n_pbo whose time-matched mean dQTcF defines ddQTcF (as in the
## TLF shells). methods per scenario:
##   t          signed area on ddQTcF itself (identical to the linear-f residual area),
##              placebo-adjusted t-test (the primary test)
##   signflip   the same area, participant-level sign-flip test (exact only when
##              ddQTcF errors are independent across participants)
##   emax       area on residuals from the Emax direct-effect fit, placebo-adjusted t
##   select     area on residuals from the f chosen by the linearity check
##   boot       parametric bootstrap from the fitted direct-effect model (secondary)
##   tmax       the two tmax-gap conventions (> 1 h)
##   day_m1     Day -1 pseudo-loop check (Day -1 QTcF paired with Day 1 x), placebo-adjusted t
##   day_m1_sf  the same check with the one-sample sign-flip test
sc <- function(id, label, n, n_pbo = 8L, model = "linear", ke0 = Inf, methods = c("t"),
               boot_form = "linear", placebo = "pooled", ...)
  list(id = id, label = label, n = as.integer(n), n_pbo = as.integer(if (placebo == "within") n else n_pbo),
       placebo = placebo, model = model, ke0 = ke0, methods = methods, boot_form = boot_form, extra = list(...))
SCEN <- list(
  sc("KA1", "Linear direct effect, no delay", 32,
     methods = c("t", "signflip", "select", "boot", "tmax", "day_m1", "day_m1_sf")),
  sc("KA1-p16", "Linear direct effect, no delay; 16 placebo", 32, 16, methods = c("t", "signflip")),
  sc("KA1-p32", "Linear direct effect, no delay; 32 placebo", 32, 32, methods = c("t", "signflip")),
  sc("KA1-within", "Linear direct effect, no delay; crossover, own placebo period", 32,
     placebo = "within", methods = c("signflip", "t", "day_m1_sf")),
  sc("KA2", "Emax direct effect, no delay", 32, model = "emax",
     methods = c("t", "emax", "select", "boot", "tmax"), boot_form = "emax"),
  sc("KA2-delay", "Emax effect, delay ke0 = 0.7 per h", 32, model = "emax", ke0 = 0.7, methods = c("t", "emax", "select")),
  sc("KA3-k4",   "Linear, delay ke0 = 4 per h",    32, ke0 = 4,    methods = c("t", "boot", "tmax")),
  sc("KA3-k2",   "Linear, delay ke0 = 2 per h",    32, ke0 = 2,    methods = c("t", "boot", "tmax")),
  sc("KA3-k1",   "Linear, delay ke0 = 1 per h",    32, ke0 = 1,    methods = c("t", "boot", "tmax")),
  sc("KA3-k0.7", "Linear, delay ke0 = 0.7 per h",  32, ke0 = 0.7,  methods = c("t", "boot", "tmax")),
  sc("KA3-k0.5", "Linear, delay ke0 = 0.5 per h",  32, ke0 = 0.5,  methods = c("t", "boot", "tmax")),
  sc("KA3-k0.35","Linear, delay ke0 = 0.35 per h", 32, ke0 = 0.35, methods = c("t", "boot", "tmax")),
  sc("KA3-k4-p32",   "Linear, delay ke0 = 4 per h; 32 placebo",    32, 32, ke0 = 4,    methods = c("t")),
  sc("KA3-k2-p32",   "Linear, delay ke0 = 2 per h; 32 placebo",    32, 32, ke0 = 2,    methods = c("t")),
  sc("KA3-k1-p32",   "Linear, delay ke0 = 1 per h; 32 placebo",    32, 32, ke0 = 1,    methods = c("t")),
  sc("KA3-k0.7-p32", "Linear, delay ke0 = 0.7 per h; 32 placebo",  32, 32, ke0 = 0.7,  methods = c("t")),
  sc("KA3-k0.5-p32", "Linear, delay ke0 = 0.5 per h; 32 placebo",  32, 32, ke0 = 0.5,  methods = c("t")),
  sc("KA3-k0.35-p32","Linear, delay ke0 = 0.35 per h; 32 placebo", 32, 32, ke0 = 0.35, methods = c("t")),
  sc("KA3-k0.7-p16", "Linear, delay ke0 = 0.7 per h; 16 placebo",  32, 16, ke0 = 0.7,  methods = c("t")),
  sc("KA3-k0.7-within", "Linear, delay ke0 = 0.7 per h; crossover, own placebo period", 32,
     placebo = "within", ke0 = 0.7, methods = c("signflip")),
  sc("KA4-direct", "One SAD cohort of 6, linear direct effect", 6, methods = c("t", "signflip", "tmax")),
  sc("KA4-k4",   "One SAD cohort of 6, ke0 = 4 per h",    6, ke0 = 4,    methods = c("t")),
  sc("KA4-k2",   "One SAD cohort of 6, ke0 = 2 per h",    6, ke0 = 2,    methods = c("t")),
  sc("KA4-k1",   "One SAD cohort of 6, ke0 = 1 per h",    6, ke0 = 1,    methods = c("t")),
  sc("KA4-k0.7", "One SAD cohort of 6, ke0 = 0.7 per h",  6, ke0 = 0.7,  methods = c("t")),
  sc("KA4-k0.5", "One SAD cohort of 6, ke0 = 0.5 per h",  6, ke0 = 0.5,  methods = c("t")),
  sc("KA4-k0.35","One SAD cohort of 6, ke0 = 0.35 per h", 6, ke0 = 0.35, methods = c("t", "tmax")),
  sc("KA5", "Tolerance (gamma = 3, k_m = 0.35 per h): clockwise", 32, model = "tolerance", methods = c("t"),
     gamma = 3, k_m = 0.35),
  sc("NC1-phi0",  "Residual time pattern, phi = 0 h",  32, methods = c("t", "day_m1"), diurnal_amp = 3, phi = 0),
  sc("NC1-phi6",  "Residual time pattern, phi = 6 h",  32, methods = c("t", "day_m1"), diurnal_amp = 3, phi = 6),
  sc("NC1-phi12", "Residual time pattern, phi = 12 h", 32, methods = c("t", "day_m1"), diurnal_amp = 3, phi = 12),
  sc("NC1-phi18", "Residual time pattern, phi = 18 h", 32, methods = c("t", "day_m1"), diurnal_amp = 3, phi = 18)
)

## ---- one replicate --------------------------------------------------------------
one_rep <- function(s) {
  d <- do.call(sim_trial, c(list(n = s$n, n_pbo = s$n_pbo, placebo = s$placebo,
                                 model = s$model, ke0 = s$ke0), s$extra))
  X <- scale_conc(d$C); r <- list()
  Pp <- if (s$placebo == "pooled") d$P else NULL          # what the test is told about the correction
  Dp <- if (s$placebo == "pooled") d$D1P else NULL
  hX <- function(PP) if (is.null(PP)) NULL else placebo_areas(X, PP)
  A_raw <- loop_areas(X, d$Y)
  t_raw <- pbo_t_test(A_raw, hX(Pp))
  if ("t" %in% s$methods) {
    r$area_t_one_sided <- t_raw$p_one <= ALPHA
    r$area_t_two_sided <- t_raw$p_two <= ALPHA
  }
  if ("signflip" %in% s$methods) {
    t_sf <- signflip_test(A_raw, B_SF)
    r$area_signflip_one_sided <- t_sf$p_one <= ALPHA
    r$area_signflip_two_sided <- t_sf$p_two <= ALPHA
  }
  if ("emax" %in% s$methods) {
    fe <- fit_emax(d$C, d$Y)
    t_e <- pbo_t_test(resid_areas(d$C, d$Y, fe, X), hX(Pp))
    r$emax_resid_t_one_sided <- t_e$p_one <= ALPHA
    r$emax_resid_t_two_sided <- t_e$p_two <= ALPHA
  }
  if ("select" %in% s$methods) {
    lc <- linearity_check(d$C, d$Y)
    r$linearity_check_picks_emax <- lc$selected$form == "emax"
    p_sel <- if (lc$selected$form == "linear") t_raw$p_one else
      pbo_t_test(resid_areas(d$C, d$Y, lc$selected, X), hX(Pp))$p_one
    r$selected_f_resid_t_one_sided <- p_sel <= ALPHA
  }
  if ("boot" %in% s$methods) {
    fb <- fit_direct(d$C, d$Y, s$boot_form)
    r$param_boot_one_sided <- param_boot_test(d$C, d$Y, fb, B_BOOT, X, Pp)$p_one <= ALPHA
  }
  if ("tmax" %in% s$methods) {
    g <- tmax_gap(d$times, d$C, d$Y)
    r$tmax_gap_individual_gt_1h   <- g[["individual"]] > 1
    r$tmax_gap_mean_profile_gt_1h <- g[["mean_profile"]] > 1
  }
  if ("day_m1" %in% s$methods) {
    t1 <- pbo_t_test(loop_areas(X, d$D1), hX(Dp))
    r$day_m1_t_two_sided <- t1$p_two <= ALPHA
    r$day_m1_t_one_sided <- t1$p_one <= ALPHA
  }
  if ("day_m1_sf" %in% s$methods) {
    r$day_m1_signflip_two_sided <- signflip_test(loop_areas(X, d$D1), B_SF)$p_two <= ALPHA
  }
  x <- unlist(r); storage.mode(x) <- "double"; x
}

## exact (Clopper-Pearson) 95% interval for x rejections in R replicates
cp_ci <- function(x, R) cbind(low  = ifelse(x == 0, 0, qbeta(0.025, x, R - x + 1)),
                              high = ifelse(x == R, 1, qbeta(0.975, x + 1, R - x)))

run_all <- function() {
  rows <- list()
  for (k in seq_along(SCEN)) {
    s <- SCEN[[k]]
    set.seed(SEED + k)                                  # scenario k uses seed 20261025 + k
    t0 <- proc.time()[["elapsed"]]
    nm <- one_rep_names(s)
    M <- t(vapply(seq_len(REPS), function(i) one_rep(s), setNames(numeric(length(nm)), nm)))
    x <- colSums(M); rate <- x / REPS; ci <- cp_ci(x, REPS)
    rows[[k]] <- data.frame(scenario = s$id, label = s$label, n = s$n, n_pbo = s$n_pbo,
                            placebo = s$placebo, seed = as.integer(SEED + k), method = names(rate),
                            replicates = as.integer(REPS), rejections = as.integer(x),
                            rejection_rate = rate,
                            ## at 0 or REPS rejections sqrt(p(1 - p) / R) is 0: report NA and use the CI
                            mcse = ifelse(x == 0 | x == REPS, NA_real_, sqrt(rate * (1 - rate) / REPS)),
                            ci95_low = ci[, "low"], ci95_high = ci[, "high"], row.names = NULL)
    cat(sprintf("%-15s %5.1fs  %s\n", s$id, proc.time()[["elapsed"]] - t0,
                paste(sprintf("%s=%.3f", names(rate), rate), collapse = " ")))
  }
  do.call(rbind, rows)
}
## method names a scenario produces (fixed order; used to size vapply)
one_rep_names <- function(s) {
  nm <- character(0)
  if ("t" %in% s$methods) nm <- c(nm, "area_t_one_sided", "area_t_two_sided")
  if ("signflip" %in% s$methods) nm <- c(nm, "area_signflip_one_sided", "area_signflip_two_sided")
  if ("emax" %in% s$methods) nm <- c(nm, "emax_resid_t_one_sided", "emax_resid_t_two_sided")
  if ("select" %in% s$methods) nm <- c(nm, "linearity_check_picks_emax", "selected_f_resid_t_one_sided")
  if ("boot" %in% s$methods) nm <- c(nm, "param_boot_one_sided")
  if ("tmax" %in% s$methods) nm <- c(nm, "tmax_gap_individual_gt_1h", "tmax_gap_mean_profile_gt_1h")
  if ("day_m1" %in% s$methods) nm <- c(nm, "day_m1_t_two_sided", "day_m1_t_one_sided")
  if ("day_m1_sf" %in% s$methods) nm <- c(nm, "day_m1_signflip_two_sided")
  nm
}

## ---- noise-free typical-participant areas (no simulation noise) ---------------------
noise_free <- function() {
  dense <- seq(0, 24, by = 0.01)
  cases <- list(
    list("Linear, direct effect", "linear", Inf, list()),
    list("Emax, direct effect", "emax", Inf, list()),
    list("Linear, ke0 = 0.7 per h", "linear", 0.7, list()),
    list("Tolerance, gamma = 3, k_m = 0.35 per h", "tolerance", Inf, list(gamma = 3, k_m = 0.35)),
    list("Residual time pattern only, phi = 0 h", "linear", Inf, list(slope = 0, diurnal_amp = 3, phi = 0)),
    list("Residual time pattern only, phi = 6 h", "linear", Inf, list(slope = 0, diurnal_amp = 3, phi = 6)),
    list("Residual time pattern only, phi = 12 h", "linear", Inf, list(slope = 0, diurnal_amp = 3, phi = 12)),
    list("Residual time pattern only, phi = 18 h", "linear", Inf, list(slope = 0, diurnal_amp = 3, phi = 18)))
  do.call(rbind, lapply(cases, function(cs) {
    a <- function(tt) { p <- do.call(typical_profile, c(list(times = tt, model = cs[[2]], ke0 = cs[[3]]), cs[[4]]))
                        loop_area(p$C / max(p$C), p$E) }
    data.frame(case = cs[[1]], area_12_point_ms = a(DEFAULT_TIMES), area_dense_grid_ms = a(dense))
  }))
}

## ---- worked example: one synthetic trial through hysteresis_check() -----------------
example_check <- function() {
  set.seed(SEED)
  rows <- list()
  for (cs in list(list("Linear, no delay", "linear", Inf, "linear"),
                  list("Linear, ke0 = 0.7 per h", "linear", 0.7, "linear"),
                  list("Emax, no delay: raw area", "emax", Inf, "linear"),
                  list("Emax, no delay: Emax residual area", "emax", Inf, "emax"))) {
    if (!grepl("Emax residual", cs[[1]])) d <- sim_trial(32, 8, model = cs[[2]], ke0 = cs[[3]])
    h <- hysteresis_check(d$times, d$C, d$Y, d$P, form = cs[[4]], D1 = d$D1, D1P = d$D1P)
    rows[[length(rows) + 1]] <- data.frame(
      dataset = cs[[1]], n = h$n, n_pbo = h$n_pbo, model_for_f = h$model, Abar_ms = h$Abar,
      se_ms = h$se, df = h$df, ci95_low = h$ci95[1], ci95_high = h$ci95[2],
      p_one_sided = h$p_one, p_two_sided = h$p_two,
      test = h$test, boot_p_one_sided = h$boot$p_one,
      tmax_gap_individual_h = h$tmax_gap[["individual"]], tmax_gap_mean_profile_h = h$tmax_gap[["mean_profile"]],
      day_m1_Abar_ms = h$day_m1$Abar, day_m1_p_two_sided = h$day_m1$p_two)
  }
  do.call(rbind, rows)
}

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
