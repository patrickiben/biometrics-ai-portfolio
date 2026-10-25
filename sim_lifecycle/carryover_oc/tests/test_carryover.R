#!/usr/bin/env Rscript
################################################################################
# carryover_oc/tests/test_carryover.R: known-answer checks and controls (base R, stopifnot).
# SYNTHETIC DATA ONLY.
#
#   Rscript sim_lifecycle/carryover_oc/tests/test_carryover.R      (from the repository root)
#
# T1 superposition | T2 NCA by hand (+ PKNCA if installed) | T3 2x2 estimator = lm() |
# T4 KA3 exact closed form | T5 KA2 symmetry | T6 KA1 adequate washout | T7 NC1 and NC2 |
# T8 M13A floor of 12 and the 5% threshold on hand-built profiles | T9 KA4 cross-implementation
# (judge A's Python check, including the kept fraction) | T10 G1 invariance of
# sim_lifecycle/simulate_adam.R with washout_h unset | T11 arm wiring (every arm recomputed from
# its definition, subtraction against the oracle, exclusions recounted by sequence) | T12 MCSE
# formulas and replicate sizing.
# Writes out/known_answer_checks.csv (the page's pass table) and out/known_answer_details.csv,
# then stops with an error if any check fails. Rows marked INFO compare against numbers from
# the unvalidated pilot; they are reported, not enforced.
################################################################################
args <- commandArgs(trailingOnly = FALSE)
me <- sub("^--file=", "", args[grep("^--file=", args)])
mod <- if (length(me)) dirname(dirname(normalizePath(me))) else normalizePath("sim_lifecycle/carryover_oc")
setwd(dirname(dirname(mod)))                                   # repository root
for (f in c("dgm.R", "nca_m13a.R", "analyze.R")) source(file.path(mod, "R", f))
t_start <- proc.time()[["elapsed"]]

CHECKS <- list(); DETAILS <- list()
check <- function(test, name, criterion, observed, ok, info = FALSE) {
  res <- if (info) "INFO" else if (isTRUE(ok)) "PASS" else "FAIL"
  CHECKS[[length(CHECKS) + 1]] <<- data.frame(test = test, check = name, criterion = criterion,
                                             observed = observed, result = res, stringsAsFactors = FALSE)
  cat(sprintf("[%s] %s %s: %s\n", res, test, name, observed))
  invisible(ok)
}
detail <- function(test, ...) DETAILS[[length(DETAILS) + 1]] <<- data.frame(test = test, ..., stringsAsFactors = FALSE)
fmt <- function(x, d = 3) trimws(formatC(x, format = "g", digits = d))

set <- oc_settings(); configs <- oc_configs(set); cells <- oc_cells()
streams <- oc_streams(nrow(cells))
cell_of <- function(theta, disp) which(abs(cells$theta - theta) < 1e-12 & cells$disposition == disp)
use_stream(streams[[nrow(cells) + 1L]]); lloq <- lloq_from_population(100000L, set)

## ---- T1 superposition --------------------------------------------------------------
## Independent route: propagate the two-compartment (gut, central) amounts from the period-1
## dose to time W, add the period-2 dose to the gut, and propagate again. For linear PK this
## must equal the own-dose profile plus c_i1(t + W).
use_stream(streams[[1]]); pop <- draw_population(5, set)
for (disp in c("mono", "biexp")) {
  theta <- 1.25; W <- 3 * set$t_half; tt <- set$times
  prof <- true_profiles(pop, theta, tt, disp, set)
  resid <- residual_profile(pop, prof, W, set)
  y2 <- observe(prof$c2 + resid, pop$e2, FALSE, lloq, set)
  dv <- set$dose_over_v; k <- pop$k; ka <- pop$ka
  analytic <- prof$amt1 * dv * ka / (ka - k) * (exp(-outer(k, tt + W)) - exp(-outer(ka, tt + W)))
  if (disp == "biexp") analytic <- analytic + prof$amt1 * set$slow_frac *
    exp(-outer(k * set$slow_k_ratio, tt + W)) * (1 - exp(-outer(ka, tt + W)))
  e1 <- max(abs((y2 - prof$c2) - analytic))
  if (disp == "mono") {   # state propagation (amounts scaled by D/V): gut g, central a
    g_W <- prof$amt1 * dv * exp(-ka * W); a_W <- prof$amt1 * dv * ka / (ka - k) * (exp(-k * W) - exp(-ka * W))
    g0 <- g_W + prof$amt2 * dv
    prop <- a_W * exp(-outer(k, tt)) + g0 * ka / (ka - k) * (exp(-outer(k, tt)) - exp(-outer(ka, tt)))
    e2 <- max(abs(y2 - prop))
    check("T1", "superposition (mono)", "period-2 profile minus own-dose profile equals c_i1(t + W), and the period-2 profile equals state propagation of the gut and central amounts, within 1e-12",
          sprintf("max abs difference %s (analytic), %s (state propagation)", fmt(e1), fmt(e2)), e1 < 1e-12 && e2 < 1e-12)
  } else {                # the slow phase is a misspecification term with no compartment form here
    check("T1", "superposition (biexp)", "period-2 profile minus own-dose profile equals c_i1(t + W) within 1e-12 (state propagation: not applicable, biexponential)",
          sprintf("max abs difference %s (analytic); state propagation not applicable (biexponential)", fmt(e1)), e1 < 1e-12)
  }
}

## ---- T2 NCA on hand-checked profiles (+ PKNCA cross-check if installed) --------------------
p <- nca_one_profile(c(0, 1, 2, 4, 6, 8, 12), c(0, 6, 10, 8, 4, 2, 0))
## by hand: AUC(0-8) = 3 + 8 + 18 + 12 + 6 = 47 (the BLQ at 12 h ends the AUC at 8 h);
## Cmax 10 at 2 h; the last three positive concentrations (8, 4, 2 at 4, 6, 8 h) halve every
## 2 h, so lambda_z = ln 2 / 2 exactly; AUC(0-inf) = 47 + 2 / (ln 2 / 2) = 47 + 4 / ln 2.
want <- c(auclast = 47, cmax = 10, tmax = 2, lambda_z = log(2) / 2, aucinf = 47 + 4 / log(2))
e <- max(abs(p[names(want)] - want))
## a BLQ inside the profile counts as 0: AUC(0-4) of 0, 4, BLQ, 2, 1 at 0..4 h = 2 + 2 + 1 + 1.5 = 6.5
q <- nca_one_profile(0:4, c(0, 4, 0, 2, 1))
lzq <- unname(-coef(lm(log(c(4, 2, 1)) ~ c(1, 3, 4)))[2])
e <- max(e, abs(q[["auclast"]] - 6.5), abs(q[["lambda_z"]] - lzq))
check("T2", "NCA by hand", "AUC(0-t) 47, Cmax 10 at 2 h, lambda_z ln 2/2, AUC(0-inf) 47 + 4/ln 2; inner BLQ as 0 (AUC 6.5); within 1e-12",
      sprintf("max abs difference %s", fmt(e)), e < 1e-12)
if (requireNamespace("PKNCA", quietly = TRUE)) {
  suppressPackageStartupMessages(library(PKNCA))
  use_stream(streams[[2]]); pp <- draw_population(1, set)
  prof <- true_profiles(pp, 1, set$times, "mono", set)
  Y <- observe(prof$c2 + residual_profile(pp, prof, 4 * set$t_half, set), pp$e2, TRUE, lloq, set)
  mine <- nca_matrix(Y, set$times)
  d <- data.frame(id = rep(seq_len(nrow(Y)), each = ncol(Y)), time = rep(set$times, nrow(Y)), conc = as.vector(t(Y)))
  d$hl <- ave(d$conc, d$id, FUN = function(v) { s <- rep(FALSE, length(v)); i <- tail(which(v > 0), 3); s[i] <- TRUE; s }) > 0
  o <- PKNCA.options(); on.exit(PKNCA.options(o), add = TRUE)
  PKNCA.options(conc.blq = list(first = "keep", middle = "keep", last = "keep"), auc.method = "linear", min.hl.points = 3, allow.tmax.in.half.life = TRUE)
  cobj <- PKNCAconc(d, conc ~ time | id, include_half.life = "hl")
  iv <- data.frame(start = 0, end = Inf, auclast = TRUE, cmax = TRUE, lambda.z = TRUE)
  r <- as.data.frame(pk.nca(PKNCAdata(cobj, intervals = iv)))
  g <- function(param) r$PPORRES[r$PPTESTCD == param][order(r$id[r$PPTESTCD == param])]
  rel <- max(abs(g("auclast") / mine$auclast - 1), abs(g("cmax") / mine$cmax - 1), abs(g("lambda.z") / mine$lambda_z - 1))
  check("T2", sprintf("PKNCA %s cross-check", as.character(utils::packageVersion("PKNCA"))),
        "AUC(0-t), Cmax and lambda_z (last 3 positive points) agree with PKNCA (linear, BLQ kept as 0) within 1e-8 relative on 24 profiles with assay error",
        sprintf("max relative difference %s", fmt(rel)), rel < 1e-8)
} else {
  check("T2", "PKNCA cross-check", "run when PKNCA is installed", "skipped: PKNCA not installed", TRUE, info = TRUE)
}

## ---- T3 closed-form 2x2 estimator equals lm() on 100 datasets ---------------------------
use_stream(streams[[3]]); pop <- draw_population(100, set)
prof <- true_profiles(pop, 1.25, set$times, "mono", set)
y2 <- prof$c2 + residual_profile(pop, prof, 5 * set$t_half, set)
n1 <- nca_matrix(prof$c1, set$times); n2 <- nca_matrix(y2, set$times)
keep <- !m13a_exclude(y2, n2$cmax, set)
keep[pop$rep <= 50] <- TRUE                     # 50 complete datasets, 50 unbalanced after exclusion
cf <- be_2x2(log(n1$auclast), log(n2$auclast), pop$seq, keep, pop$n, set)
emax <- 0
for (r in seq_len(100)) {
  i <- which(pop$rep == r & keep); if (length(i) < 4 || !cf$evaluable[r]) next
  dd <- data.frame(id = factor(rep(i, 2)), period = factor(rep(1:2, each = length(i))),
                   y = log(c(n1$auclast[i], n2$auclast[i])),
                   form = factor(c(ifelse(pop$seq[i] == 1, "T", "R"), ifelse(pop$seq[i] == 1, "R", "T")), levels = c("R", "T")))
  fit <- lm(y ~ id + period + form, data = dd); co <- summary(fit)$coefficients["formT", ]
  qq <- qt(0.95, fit$df.residual)
  emax <- max(emax, abs(co[1] - cf$est[r]), abs(co[1] - qq * co[2] - cf$lo[r]), abs(co[1] + qq * co[2] - cf$hi[r]),
              abs(fit$df.residual - cf$df[r]))
}
check("T3", "2x2 estimator equals lm()", "estimate and 90% CI limits equal the participant + period + formulation OLS fit within 1e-10 (50 complete, 50 unbalanced datasets)",
      sprintf("max abs difference %s over %d datasets", fmt(emax), sum(cf$evaluable)), emax < 1e-10)

## ---- T4 KA3 exact closed form ----------------------------------------------------------
for (case in c("constant r (sd_ka = 0)", "participant-specific r (sd_ka = 0.20)")) {
  s0 <- oc_settings(sd_k = 0, sd_w = 0, sd_ka = if (grepl("constant", case)) 0 else 0.20)
  use_stream(streams[[4]]); pop <- draw_population(50, s0)
  emax <- 0; worst_approx <- 0
  for (theta in c(0.80, 1.25)) for (Wm in c(2, 3, 5)) {
    prof <- true_profiles(pop, theta, s0$times, "mono", s0)
    resid <- residual_profile(pop, prof, Wm * s0$t_half, s0)
    n1 <- nca_matrix(prof$c1, s0$times); n2 <- nca_matrix(prof$c2 + resid, s0$times)
    est <- be_2x2(log(n1$auclast), log(n2$auclast), pop$seq, rep(TRUE, pop$m), pop$n, s0)$est
    r_i <- matrix(residual_fraction(prof$c1, resid, s0$times), pop$R, pop$n, byrow = TRUE)
    S <- matrix(pop$seq, pop$R, pop$n, byrow = TRUE)
    exact <- if (grepl("constant", case)) closed_form_log_gmr(theta, r_i[, 1]) else
      log(theta) + 0.5 * (rowMeans(ifelse(S == 2, log(1 + r_i / theta), NA), na.rm = TRUE) -
                          rowMeans(ifelse(S == 1, log(1 + r_i * theta), NA), na.rm = TRUE))
    emax <- max(emax, abs(est - exact))
    if (grepl("constant", case)) worst_approx <- max(worst_approx, abs(closed_form_approx(theta, r_i[1, 1]) - closed_form_log_gmr(theta, r_i[1, 1])))
    detail("T4", case = case, theta = theta, W_over_thalf = Wm, r = mean(r_i), bias_exact = mean(exact) - log(theta),
           bias_approx = if (grepl("constant", case)) closed_form_approx(theta, r_i[1, 1]) - log(theta) else NA)
  }
  check("T4", sprintf("KA3 closed form, %s", case), "with sigma_k = sigma_w = 0 and no assay error, the naive log GMR-hat of every study equals the closed form within 1e-10",
        sprintf("max abs difference %s over 300 studies%s", fmt(emax),
                if (grepl("constant", case)) sprintf("; first-order approximation within %s of the exact form", fmt(worst_approx, 2)) else ""),
        emax < 1e-10)
}

## ---- T5 KA2 symmetry at theta = 1 (500 replicates) ----------------------------------------
for (disp in c("mono", "biexp")) {
  use_stream(streams[[cell_of(1, disp)]]); pop <- draw_population(500, set)
  x <- run_cell(pop, 1, disp, configs["base"], OC_WASHOUTS, lloq, adequate = FALSE, set)$results
  x <- x[x$arm %in% c("A1", "A2", "A2s") & x$endpoint %in% c("AUC", "CMAX"), ]
  est <- !is.na(x$bias_mcse)
  z <- abs(x$bias[est]) / x$bias_mcse[est]
  for (i in which(est)) detail("T5", disposition = disp, washout = x$washout[i], arm = x$arm[i], endpoint = x$endpoint[i],
                               n_eval = x$n_eval[i], bias = x$bias[i], mcse = x$bias_mcse[i])
  check("T5", sprintf("KA2 symmetry (%s)", disp), "at theta = 1, bias of A1, A2 and A2s within 3 MCSE of 0 at every washout (AUC and Cmax); 500 replicates",
        sprintf("max |bias|/MCSE %.2f over %d checks; not estimable (no evaluable study): %s", max(z), length(z),
                paste(unique(paste0(x$arm[!est], " at W = ", x$washout[!est])), collapse = ", ")), all(z <= 3))
}

## ---- T6 KA1 adequate washout and T7 negative controls (500 replicates) --------------------
use_stream(streams[[cell_of(1.25, "mono")]]); pop <- draw_population(500, set)
xc <- run_cell(pop, 1.25, "mono", configs["base"], OC_WASHOUTS, lloq, adequate = TRUE, set, keep_studies = TRUE)
pop6 <- pop                                     # reused by T11
x <- xc$results; ad <- x[x$washout == "adequate" & x$endpoint %in% c("AUC", "CMAX"), ]
dz <- c(); for (ep in c("AUC", "CMAX")) {
  a <- ad[ad$endpoint == ep, ]; a0 <- a[a$arm == "A0", ]
  dz <- c(dz, abs(a$bias - a0$bias) / a0$bias_mcse, abs(a$be_rate - a0$be_rate) / a0$be_rate_mcse)
}
a0 <- ad[ad$arm == "A0" & ad$endpoint == "AUC", ]
check("T6", "KA1 adequate washout", "W = 10 x the largest individual t1/2: every arm within 3 MCSE of A0 (bias and BE rate, AUC and Cmax); A0 consumer risk within 0.05 +/- 0.015; zero exclusions",
      sprintf("max |arm - A0|/MCSE %.2f; A0 consumer risk %.3f (MCSE %.3f); exclusions %d", max(dz), a0$be_rate, a0$be_rate_mcse,
              sum(xc$studies[["base adequate"]]$excl)),
      max(dz) <= 3 && abs(a0$be_rate - 0.05) <= 0.015 && sum(xc$studies[["base adequate"]]$excl) == 0)

st <- xc$studies
a0_est <- lapply(st, function(s) s$arms$A0$AUC$est)
same <- all(vapply(a0_est, identical, logical(1), a0_est[[1]]))
nexcl <- sum(vapply(st, function(s) sum(s$a0_excl), numeric(1)))
check("T7", "NC1 oracle invariance", "A0 gives identical estimates at every washout, zero exclusions when the rule is applied to A0 data, and nominal consumer risk (0.05 +/- 0.015)",
      sprintf("identical across %d washouts: %s; exclusions %d; consumer risk %.3f", length(st), same, nexcl, a0$be_rate),
      same && nexcl == 0 && abs(a0$be_rate - 0.05) <= 0.015)
nc2 <- 0; for (cn in c("base", "assay")) {
  prof <- true_profiles(pop, 1.25, configs[[cn]]$times, "mono", set)
  o1 <- observe(prof$c1, pop$e1, configs[[cn]]$assay, lloq, set); o2 <- observe(prof$c2, pop$e2, configs[[cn]]$assay, lloq, set)
  n1 <- nca_matrix(o1, configs[[cn]]$times); n2 <- nca_matrix(o2, configs[[cn]]$times)
  y3 <- subtract_residual(o2, configs[[cn]]$times, n1$lambda_z); n3 <- nca_matrix(y3, configs[[cn]]$times)
  b0 <- be_2x2(log(n1$auclast), log(n2$auclast), pop$seq, rep(TRUE, pop$m), pop$n, set)
  b3 <- be_2x2(log(n1$auclast), log(n3$auclast), pop$seq, rep(TRUE, pop$m), pop$n, set)
  c0 <- be_2x2(log(n1$cmax), log(n2$cmax), pop$seq, rep(TRUE, pop$m), pop$n, set)
  c3 <- be_2x2(log(n1$cmax), log(n3$cmax), pop$seq, rep(TRUE, pop$m), pop$n, set)
  nc2 <- max(nc2, abs(y3 - o2), abs(b3$est - b0$est), abs(b3$lo - b0$lo), abs(c3$est - c0$est), abs(c3$hi - c0$hi))
}
check("T7", "NC2 subtraction on oracle data", "A3 applied to A0 data (no residual) leaves every concentration and estimate unchanged within 1e-12 (base and assay-error configurations)",
      sprintf("max abs difference %s", fmt(nc2)), nc2 <= 1e-12)

## ---- T8 M13A floor of 12 evaluable participants ------------------------------------------
use_stream(streams[[5]]); dd <- rnorm(24, 0.1, 0.2); sq <- rep(1:2, each = 12)
floor_case <- function(keep) be_2x2(dd, rep(0, 24), sq, keep, 24L, set)
k11 <- c(rep(TRUE, 6), rep(FALSE, 6), rep(TRUE, 5), rep(FALSE, 7))
k12 <- c(rep(TRUE, 6), rep(FALSE, 6), rep(TRUE, 6), rep(FALSE, 6))
k13 <- c(rep(TRUE, 7), rep(FALSE, 5), rep(TRUE, 6), rep(FALSE, 6))
k_empty <- c(rep(TRUE, 12), rep(FALSE, 12))
r11 <- floor_case(k11); r12 <- floor_case(k12); r13 <- floor_case(k13); re <- floor_case(k_empty)
ok8 <- !r11$evaluable && !r11$be && is.na(r11$est) && r12$evaluable && r13$evaluable && !re$evaluable && !re$be
check("T8", "M13A floor", "11 evaluable participants: not evaluable and not BE; 12 and 13: evaluable; 12 in one sequence and 0 in the other: not evaluable",
      sprintf("11: %s; 12: %s; 13: %s; empty sequence: %s", r11$evaluable, r12$evaluable, r13$evaluable, re$evaluable), ok8)

## The 5% threshold, with the expected decisions written out here rather than read from
## oc_settings(). (i) The rule at the boundary: pre-dose 0.98, 1.00 and 1.02 against a Cmax of 20
## (4.9%, exactly 5.0% and 5.1%); only 5.1% is excluded, because the rule is "above 5%".
yb <- rbind(c(0.98, 20, 5), c(1, 20, 5), c(1.02, 20, 5))
eb <- m13a_exclude(yb, nca_matrix(yb, c(0, 1, 2))$cmax, set)
## (ii) The rule as analyze_washout() applies it, on hand-built profiles: identical participants
## (k, ka fixed, no noise) carry the same residual into period 2; each period-2 own-dose profile
## is scaled so that the pre-dose level is 4.9% or 5.1% of that period's Cmax, and the period-1
## profile is set to 2 or 0.5 times the period-2 Cmax. Against the period-1 Cmax the ratios
## would be about 2.5% or 10%, so a wrong denominator changes the decisions.
hb <- local({
  n <- set$n; tt <- set$times; J <- length(tt)
  pop <- list(R = 1L, n = n, m = n, rep = rep(1L, n), seq = rep(1:2, each = n / 2),
              k = rep(log(2) / set$t_half, n), ka = rep(set$ka, n), F = rep(1, n), w1 = rep(1, n), w2 = rep(1, n),
              e1 = matrix(0, n, J), e2 = matrix(0, n, J))
  prof <- list(times = tt, amt1 = rep(1, n), amt2 = rep(1, n), disposition = "mono")
  W <- 5 * set$t_half
  shape <- own_conc(tt, rep(1, n), pop$k, pop$ka, "mono", set)
  resid <- residual_profile(pop, prof, W, set)
  ratio <- rep(c(0.049, 0.051), length.out = n)                     # pre-dose / own-period Cmax
  a <- vapply(seq_len(n), function(i) uniroot(function(s) max(s * shape[i, ] + resid[i, ]) - resid[i, 1] / ratio[i],
                                               c(0, 1e3), tol = 1e-15)$root, 0)
  prof$c2 <- a * shape
  cm2 <- apply(prof$c2 + resid, 1, max)
  f1 <- rep(rep(c(2, 0.5), each = n / 4), 2)                        # period-1 Cmax / period-2 Cmax
  prof$c1 <- (f1 * cm2 / apply(shape, 1, max)) * shape
  n1 <- nca_matrix(prof$c1, tt); n2own <- nca_matrix(prof$c2, tt)
  r <- analyze_washout(pop, prof, prof$c1, prof$c2, n1, n2own, W, list(times = tt, assay = FALSE), lloq, set)
  list(excl = r$excl, want = ratio > 0.05, own = r$y2[, 1] / apply(r$y2, 1, max), p1 = r$y2[, 1] / n1$cmax,
       n_tr = sum(r$excl[pop$seq == 1]), n_rt = sum(r$excl[pop$seq == 2]))
})
ok8b <- identical(eb, c(FALSE, FALSE, TRUE)) && identical(hb$excl, hb$want) && max(abs(hb$own - rep(c(0.049, 0.051), 12))) < 1e-12
check("T8", "M13A 5% threshold", "pre-dose at 4.9%, exactly 5.0% and 5.1% of Cmax: only 5.1% excluded; through analyze_washout() on 24 hand-built profiles (4.9% or 5.1% of the period's own Cmax, period-1 Cmax 2 or 0.5 times the period-2 Cmax): exactly the 5.1% participants excluded",
      sprintf("boundary decisions %s; hand-built: %d of %d decisions as expected (%d excluded, %d TR and %d RT; own-period ratios %.4f and %.4f; against the period-1 Cmax they would be %.4f to %.4f)",
              paste(eb, collapse = ", "), sum(hb$excl == hb$want), length(hb$want), sum(hb$excl), hb$n_tr, hb$n_rt,
              min(hb$own), max(hb$own), min(hb$p1), max(hb$p1)), ok8b)

## ---- T9 KA4 cross-implementation against judge A's Python check -----------------------------
## Judge A (numpy, seed 2026, 2,000 replicates per line, theta = 1.25, W = 120 h, base settings)
## drops replicates that are not evaluable, so its rates are conditional on evaluable studies;
## the comparison uses the same definition (be_rate_eval). Values from checks.py part (A).
## "kept" is the mean share of participants kept by the rule among evaluable studies; checks.py
## does not print its MCSE, so it is taken equal to R's (same design and replicate count).
judge <- data.frame(arm = c("A0", "A2s", "A1", "A2"),
                    bias = c(-0.000213, -0.005428, -0.010829, -0.006020), bias_mcse = c(0.000976, 0.001207, 0.000938, 0.001232),
                    cr = c(0.055500, 0.057543, 0.082500, 0.062307), cr_mcse = c(0.005120, 0.005302, 0.006152, 0.005485),
                    kept = c(1, 0.6655, 1, 0.6656))
use_stream(streams[[cell_of(1.25, "mono")]]); pop <- draw_population(2000, set)
xk <- run_cell(pop, 1.25, "mono", configs["base"], 5, lloq, adequate = FALSE, set, keep_studies = TRUE)
x <- xk$results[xk$results$endpoint == "AUC", ]
s5 <- xk$studies[["base 5"]]
kept_study <- 1 - rowMeans(matrix(s5$excl, pop$R, pop$n, byrow = TRUE))
kp <- mc_mean(ifelse(s5$arms$A2$AUC$evaluable, kept_study, NA))
zk <- abs(kp[["est"]] - judge$kept[judge$arm %in% c("A2s", "A2")]) / (sqrt(2) * kp[["mcse"]])
zz <- zk
for (i in seq_len(nrow(judge))) {
  a <- x[x$arm == judge$arm[i], ]
  zb <- abs(a$bias - judge$bias[i]) / sqrt(a$bias_mcse^2 + judge$bias_mcse[i]^2)
  zc <- abs(a$be_rate_eval - judge$cr[i]) / sqrt(a$be_rate_eval_mcse^2 + judge$cr_mcse[i]^2)
  zz <- c(zz, zb, zc)
  detail("T9", arm = judge$arm[i], bias_R = a$bias, bias_R_mcse = a$bias_mcse, bias_judge = judge$bias[i],
         cr_R = a$be_rate_eval, cr_R_mcse = a$be_rate_eval_mcse, cr_judge = judge$cr[i], z_bias = zb, z_cr = zc)
}
a2 <- x[x$arm == "A2", ]
detail("T9", arm = "A2 and A2s", kept_R = kp[["est"]], kept_R_mcse = kp[["mcse"]], kept_judge_A2 = judge$kept[4], kept_judge_A2s = judge$kept[2])
check("T9", "KA4 cross-implementation", "A0, A2s, A1 and A2 bias and consumer risk, and the share of participants the rule keeps in evaluable studies (theta 1.25, 5 mean t1/2), within 3 combined MCSE of judge A's Python check",
      sprintf("max |R - Python| / combined MCSE %.2f over %d comparisons; R bias A2s %.4f, A2 %.4f, A1 %.4f; consumer risk A2 %.3f, A1 %.3f, A0 %.3f; kept %.4f (MCSE %.4f) (Python: %.4f, %.4f, %.4f; %.3f, %.3f, %.3f; kept %.4f and %.4f)",
              max(zz), length(zz), x$bias[x$arm == "A2s"], a2$bias, x$bias[x$arm == "A1"], a2$be_rate_eval,
              x$be_rate_eval[x$arm == "A1"], x$be_rate_eval[x$arm == "A0"], kp[["est"]], kp[["mcse"]], judge$bias[2], judge$bias[4], judge$bias[3],
              judge$cr[4], judge$cr[3], judge$cr[1], judge$kept[2], judge$kept[4]), max(zz) <= 3)

## ---- misspecification and the pilot's expected pattern (reported, not enforced) -------------
use_stream(streams[[cell_of(1.25, "biexp")]]); pop <- draw_population(2000, set)
xb <- run_cell(pop, 1.25, "biexp", configs["base"], c(2, 3), lloq, adequate = FALSE, set, keep_studies = TRUE)
for (w in c("2", "3")) {
  s <- xb$studies[[paste("base", w)]]
  dlt <- mc_mean(s$arms$A3$AUC$be - s$arms$A0$AUC$be); dlo <- mc_mean(s$arms$A3o$AUC$be - s$arms$A0$AUC$be)
  check("INFO", sprintf("misspecification, W = %s t1/2", w),
        "biexponential disposition: subtraction's consumer risk exceeds A0's at short washouts (the pilot, which subtracted with the true k as A3o does, reported 0.069 at 3 mean t1/2)",
        sprintf("A3o (true k, as the pilot) %.4f, paired difference from A0 %+.4f (MCSE %.4f); A3 (lambda_z from period 1) %.4f, paired difference %+.4f (MCSE %.4f); A0 %.4f",
                mean(s$arms$A3o$AUC$be), dlo[["est"]], dlo[["mcse"]], mean(s$arms$A3$AUC$be), dlt[["est"]], dlt[["mcse"]],
                mean(s$arms$A0$AUC$be)), NA, info = TRUE)
}

## ---- T10 G1 invariance of sim_lifecycle/simulate_adam.R ---------------------------------------
RNGkind("Mersenne-Twister", "Inversion", "Rejection")         # the generator's default RNG
gen <- new.env(); sys.source("sim_lifecycle/simulate_adam.R", envir = gen)
s0 <- with(gen, simulate_study(sample_design("BE", N = 40), seed = 2026))
sN <- with(gen, simulate_study(sample_design("BE", N = 40), seed = 2026, washout_h = NULL))
td <- tempfile("g1_"); dir.create(td)
doms <- c("adsl", "adex", "adpc", "adpp", "adae", "advs", "adlb", "adeg")
for (nm in doms) write_oc_csv(s0[[nm]], file.path(td, paste0(nm, ".csv")))   # as run_lifecycle.R writes them
same <- vapply(doms, function(nm) identical(readLines(file.path(td, paste0(nm, ".csv"))),
                                            readLines(file.path("sim_lifecycle/out", paste0(nm, ".csv")))), logical(1))
base_ref <- "515b092"   # last commit before washout_h existed; compared in full precision when git has it
ref_ok <- NA
if (nzchar(Sys.which("git")) && system2("git", c("cat-file", "-e", paste0(base_ref, ":sim_lifecycle/simulate_adam.R")),
                                        stdout = FALSE, stderr = FALSE) == 0) {
  old <- new.env(); src <- tempfile(fileext = ".R")
  writeLines(system2("git", c("show", paste0(base_ref, ":sim_lifecycle/simulate_adam.R")), stdout = TRUE), src)
  sys.source(src, envir = old)
  ref_ok <- identical(with(old, simulate_study(sample_design("BE", N = 40), seed = 2026)), s0)
}
check("T10", "G1 invariance (washout_h unset)", "simulate_study(sample_design(\"BE\", N = 40), seed = 2026) regenerates the 8 committed CSVs byte for byte; washout_h = NULL is identical; identical to the generator before washout_h existed",
      sprintf("%d of 8 files byte-identical; explicit NULL identical: %s; full-precision match with %s: %s", sum(same),
              identical(s0, sN), base_ref, if (is.na(ref_ok)) "not run (commit not available)" else ref_ok),
      all(same) && identical(s0, sN) && !isFALSE(ref_ok))

sW <- with(gen, simulate_study(sample_design("BE", N = 40), seed = 2026, washout_h = 48))
other <- vapply(c("adsl", "adex", "adae", "advs", "adlb", "adeg"), function(nm) identical(s0[[nm]], sW[[nm]]), logical(1))
## With washout_h set every sample below the LLOQ is BLQ, the pre-dose one included (M13A: BLQ
## counts as 0). Period 1 therefore matches the default after the pre-dose sample, and its NCA
## (AUC(0-t) from the pre-dose zero) matches the default exactly.
lloq_g <- get("PK", envir = gen)$lloq
post1 <- function(a) { x <- a[a$APERIOD == 1 & a$ATPTN > 0, ]; rownames(x) <- NULL; x }
p1same <- identical(post1(s0$adpc), post1(sW$adpc))
pp1 <- function(p) { x <- p[p$APERIOD == 1 & p$PARAMCD != "PDCMXR", names(s0$adpp)]; rownames(x) <- NULL; x }
nca1_same <- identical(pp1(s0$adpp), pp1(sW$adpp))
pre1 <- sW$adpc[sW$adpc$APERIOD == 1 & sW$adpc$ATPTN == 0, ]
pre2 <- sW$adpc[sW$adpc$APERIOD == 2 & sW$adpc$ATPTN == 0, ]
q2 <- pre2$AVALC != "<LLOQ"
pp <- sW$adpp; r2 <- pp[pp$PARAMCD == "PDCMXR" & pp$APERIOD == 2, ]
blq_ok <- all(is.na(pre1$AVAL) & pre1$AVALC == "<LLOQ") && all(is.na(pre2$AVAL[!q2])) && all(pre2$AVAL[q2] >= lloq_g) &&
  sum(q2) > 0 && all(r2$AVAL[r2$USUBJID %in% pre2$USUBJID[!q2]] == 0) && all(pp$AVAL[pp$PARAMCD == "PDCMXR" & pp$APERIOD == 1] == 0)
xs <- r2$USUBJID[r2$AVAL > 0.05]
flag_ok <- all(is.na(pp$ANL02FL[pp$USUBJID %in% xs])) && all(pp$ANL02FL[!pp$USUBJID %in% xs] == "Y") &&
  all(!is.na(pp$PKEXRSN[pp$USUBJID %in% xs & pp$APERIOD == 2])) && all(is.na(pp$PKEXRSN[pp$APERIOD == 1]))
td2 <- tempfile("demo_"); dir.create(td2)
for (nm in doms) write_oc_csv(sW[[nm]], file.path(td2, paste0(nm, ".csv")))
conf <- system2(file.path(R.home("bin"), "Rscript"), c("validation_harness/checks/conformance.R", td2), stdout = TRUE, stderr = TRUE)
conf_ok <- any(grepl("G3_VERDICT: PASS", conf))
check("T10", "washout_h = 48 demonstration", "no new random draws (the other six domains, and period-1 ADPC after the pre-dose sample, identical to the default); a pre-dose sample below the LLOQ is reported as <LLOQ and counts as 0 (period-1 ADPP identical to the default; PDCMXR 0); quantified period-2 pre-dose values at or above the LLOQ; PDCMXR rows, ANL02FL null and PKEXRSN set for excluded participants; G3 structural checks pass",
      sprintf("other domains identical: %d of 6; period 1 after pre-dose identical: %s; period-1 NCA identical: %s; period-1 pre-dose <LLOQ: %d of %d; period-2 pre-dose quantified (at or above the LLOQ of %.2f): %d of %d, <LLOQ: %d; excluded: %d of 40; flags consistent: %s; G3: %s",
              sum(other), p1same, nca1_same, sum(pre1$AVALC == "<LLOQ"), nrow(pre1), lloq_g, sum(q2), nrow(pre2), sum(!q2),
              length(xs), flag_ok, if (conf_ok) "PASS" else "FAIL"),
      all(other) && p1same && nca1_same && blq_ok && flag_ok && conf_ok && all(c("ANL02FL", "PKEXRSN") %in% names(pp)))

## ---- T11 arm wiring ----------------------------------------------------------------------
## Every arm of the T6 run (theta 1.25, monoexponential, base configuration, 500 replicates, every
## washout and the KA1 control) is recomputed outside analyze_washout() from its definition: the
## exclusion decision from the returned period-2 profiles with 0.05 written here, then be_2x2() on
## the endpoints that arm is defined to use. Subtraction is then compared with the oracle, and the
## exclusions are recounted by sequence, with the sequence read from the product each participant
## received in period 1. Tolerance for A3: lambda_z is fitted to the period-1 points at 36, 48
## and 72 h, which still carry a trace of the absorption phase, exp(-(ka - k) 36 h); that moves
## the log GMR by up to about 1e-9 at 2 half-lives, so A3 is held to 1e-8 and A3o (true k) to 1e-10.
tt <- set$times; prof6 <- true_profiles(pop6, 1.25, tt, "mono", set)
n1 <- nca_matrix(prof6$c1, tt); n2own <- nca_matrix(prof6$c2, tt); all_in <- rep(TRUE, pop6$m)
rec <- function(n2, keep) list(AUC = be_2x2(log(n1$auclast), log(n2$auclast), pop6$seq, keep, pop6$n, set),
                               CMAX = be_2x2(log(n1$cmax), log(n2$cmax), pop6$seq, keep, pop6$n, set))
dif <- function(a, b) if (!identical(is.na(a), is.na(b))) Inf else max(c(0, abs(a - b)), na.rm = TRUE)
seq_tr <- function(prof, pop, theta) abs(prof$amt1 / (pop$F * pop$w1) - theta) < 1e-12   # period 1 was the test product
by_seq <- function(excl, tr, rep) cbind(tr = tapply(excl & tr, rep, sum) / tapply(tr, rep, sum),
                                        rt = tapply(excl & !tr, rep, sum) / tapply(!tr, rep, sum))
is_tr <- seq_tr(prof6, pop6, 1.25)
w_rec <- 0; be_same <- TRUE; excl_same <- TRUE; w_a3 <- 0; w_a3o <- 0; be_flip <- 0; min_sep <- Inf; w_seq <- 0
for (wn in names(xc$studies)) {
  s <- xc$studies[[wn]]; y2 <- s$y2
  ex <- y2[, 1] > 0.05 * apply(y2, 1, max)
  excl_same <- excl_same && identical(s$excl, ex)
  n2 <- nca_matrix(y2, tt)
  ref <- list(A0 = rec(n2own, all_in), A1 = rec(n2, all_in), A2 = rec(n2, !ex), A2s = rec(n2own, !ex),
              A3 = rec(nca_matrix(subtract_residual(y2, tt, n1$lambda_z), tt), all_in),
              A3o = rec(nca_matrix(subtract_residual(y2, tt, pop6$k), tt), all_in))
  for (a in names(ref)) for (ep in c("AUC", "CMAX")) {
    for (v in c("est", "lo", "hi")) w_rec <- max(w_rec, dif(s$arms[[a]][[ep]][[v]], ref[[a]][[ep]][[v]]))
    be_same <- be_same && identical(s$arms[[a]][[ep]]$be, ref[[a]][[ep]]$be)
  }
  for (ep in c("AUC", "CMAX")) {
    A <- s$arms
    for (v in c("est", "lo", "hi")) { w_a3 <- max(w_a3, dif(A$A3[[ep]][[v]], A$A0[[ep]][[v]])); w_a3o <- max(w_a3o, dif(A$A3o[[ep]][[v]], A$A0[[ep]][[v]])) }
    be_flip <- be_flip + sum(A$A3[[ep]]$be != A$A0[[ep]]$be) + sum(A$A3o[[ep]]$be != A$A0[[ep]]$be)
    ev <- A$A2[[ep]]$evaluable
    if (any(ev)) min_sep <- min(min_sep, abs(A$A2[[ep]]$est - A$A2s[[ep]]$est)[ev])
  }
  bs <- by_seq(s$excl, is_tr, pop6$rep)
  r6 <- xc$results[xc$results$arm == "A2" & xc$results$endpoint == "AUC" & xc$results$washout == sub("^base ", "", wn), ]
  w_seq <- max(w_seq, abs(mean(bs[, "tr"]) - r6$excl_frac_tr), abs(mean(bs[, "rt"]) - r6$excl_frac_rt))
  if (wn == "base 5") d125 <- mc_mean(bs[, "tr"] - bs[, "rt"])
}
check("T11", "arms recomputed from their definitions", "for every washout: the exclusion decision equals pre-dose > 0.05 x the period-2 profile's own maximum; A0, A1, A2, A2s, A3 and A3o estimates, CI limits and BE decisions (AUC(0-t) and Cmax) equal be_2x2() on the endpoints each arm is defined to use, within 1e-12; A2 and A2s differ in every study evaluable under the rule (the residual is positive)",
      sprintf("exclusions identical: %s; max abs difference %s; BE decisions identical: %s; smallest |A2 - A2s| in an evaluable study %s (%d washouts)",
              excl_same, fmt(w_rec), be_same, fmt(min_sep), length(xc$studies)),
      excl_same && w_rec <= 1e-12 && be_same && min_sep > 1e-12)
check("T11", "subtraction against the oracle", "monoexponential disposition, no assay error: A3 estimate and CI limits within 1e-8 of A0 (lambda_z from period 1) and A3o within 1e-10 (true k), every washout, AUC(0-t) and Cmax, with the same BE decision in every study",
      sprintf("max abs difference A3 - A0 %s, A3o - A0 %s; BE decisions that differ: %d", fmt(w_a3), fmt(w_a3o), be_flip),
      w_a3 <= 1e-8 && w_a3o <= 1e-10 && be_flip == 0)
use_stream(streams[[cell_of(0.80, "mono")]]); pop8 <- draw_population(500, set)
x8 <- run_cell(pop8, 0.80, "mono", configs["base"], 5, lloq, adequate = FALSE, set, keep_studies = TRUE)
bs8 <- by_seq(x8$studies[["base 5"]]$excl, seq_tr(true_profiles(pop8, 0.80, tt, "mono", set), pop8, 0.80), pop8$rep)
r8 <- x8$results[x8$results$arm == "A2" & x8$results$endpoint == "AUC", ]
w_seq <- max(w_seq, abs(mean(bs8[, "tr"]) - r8$excl_frac_tr), abs(mean(bs8[, "rt"]) - r8$excl_frac_rt))
d080 <- mc_mean(bs8[, "rt"] - bs8[, "tr"])
check("T11", "exclusions by sequence", "exclusion shares by sequence equal a recount with the sequence read from the period-1 product, within 1e-12 (every washout at a true GMR of 1.25, and 5 half-lives at 0.80); at 5 half-lives the sequence whose period-2 product gives lower exposure loses more participants: TR at a true GMR of 1.25 and RT at 0.80, each by more than 3 MCSE",
      sprintf("max abs difference %s; TR - RT at 1.25: %+.3f (MCSE %.3f); RT - TR at 0.80: %+.3f (MCSE %.3f)",
              fmt(w_seq), d125[["est"]], d125[["mcse"]], d080[["est"]], d080[["mcse"]]),
      w_seq <= 1e-12 && d125[["est"]] > 3 * d125[["mcse"]] && d080[["est"]] > 3 * d080[["mcse"]])

## ---- T12 MCSE formulas and replicate sizing ---------------------------------------------
## Hand-computed values: a rate of 0.05 in 100 studies has MCSE sqrt(0.05 x 0.95 / 100) =
## 0.0217945; the mean of 1..10 has MCSE sd(1:10) / sqrt(10) = 0.9574271; the grid's 2,000
## replicates come from a target MCSE of 0.005 at a rate of 0.05 (1,900, rounded up to 500s).
## The delta-method MCSE of a share is 0 when the part is an exact multiple of the total, and it
## agrees with a bootstrap of 2,000 synthetic study pairs within 10%.
r1 <- mc_rate(c(rep(TRUE, 5), rep(FALSE, 95))); m1 <- mc_mean(1:10)
use_stream(streams[[7]]); tot <- rnorm(2000, -0.005, 0.03); part <- 0.8 * tot + rnorm(2000, 0, 0.01)
sh <- mc_share(part, tot); sh0 <- mc_share(0.8 * tot, tot)
bs <- replicate(2000, { j <- sample.int(2000, replace = TRUE); mean(part[j]) / mean(tot[j]) })
e12 <- max(abs(r1[["est"]] - 0.05), abs(r1[["mcse"]] - 0.0217945), abs(m1[["mcse"]] - 0.9574271), abs(mcse_rate(0.05, 2000) - 0.0048734))
check("T12", "MCSE formulas and replicate sizing", "rate and mean MCSEs equal hand-computed values within 1e-7; reps_for_mcse(0.05, 0.005) = 2,000 (MCSE 0.0049); share MCSE 0 for an exact multiple and within 10% of a bootstrap",
      sprintf("max abs difference %s; replicates %d; share %.4f with MCSE %.4f against bootstrap SD %.4f; exact multiple: share %.4f, MCSE %s",
              fmt(e12), reps_for_mcse(0.05, 0.005), sh[["est"]], sh[["mcse"]], sd(bs), sh0[["est"]], fmt(sh0[["mcse"]])),
      e12 < 1e-7 && reps_for_mcse(0.05, 0.005) == 2000L && abs(sh0[["est"]] - 0.8) < 1e-12 && sh0[["mcse"]] < 1e-12 &&
        abs(sh[["mcse"]] / sd(bs) - 1) < 0.10)

## ---- write the pass table and stop on any failure -----------------------------------------
tab <- do.call(rbind, CHECKS)
out_dir <- file.path(mod, "out"); dir.create(out_dir, showWarnings = FALSE)
write.csv(tab, file.path(out_dir, "known_answer_checks.csv"), row.names = FALSE)
det <- do.call(rbind, lapply(DETAILS, function(d) { d[setdiff(unique(unlist(lapply(DETAILS, names))), names(d))] <- NA; d }))
write_oc_csv(det, file.path(out_dir, "known_answer_details.csv"))
cat(sprintf("\n%d checks: %d PASS, %d FAIL, %d INFO (%.0f s). Wrote out/known_answer_checks.csv\n", nrow(tab),
            sum(tab$result == "PASS"), sum(tab$result == "FAIL"), sum(tab$result == "INFO"), proc.time()[["elapsed"]] - t_start))
stopifnot(all(tab$result != "FAIL"))
