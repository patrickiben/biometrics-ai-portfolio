################################################################################
# carryover_oc/R/analyze.R: the 2x2 bioequivalence estimator, the six analysis arms and the
# operating characteristics with Monte Carlo standard errors. SYNTHETIC DATA ONLY.
#
# 2x2 estimator (closed form; tests/T3 shows it equals the participant + period + formulation
# OLS model fitted with lm()): d_i = log Y(period 1) - log Y(period 2);
#   log GMR-hat = (mean d_TR - mean d_RT) / 2,
#   SE = 0.5 s_p sqrt(1/n_TR + 1/n_RT), s_p the pooled within-sequence SD of d, df = n - 2,
#   90% CI = estimate +/- t(0.95, df) SE. BE is concluded if and only if the CI lies within
#   0.80 to 1.25 on unrounded limits.
# A study is not evaluable when fewer than 12 participants remain or a sequence is empty; a
# study that is not evaluable does not conclude BE.
################################################################################

OC_ARMS <- c(
  A0  = "Oracle: no residual",
  A1  = "Naive: all participants",
  A2  = "M13A exclusion",
  A2s = "Exclusion decision only (residual removed)",
  A3  = "Subtraction (sensitivity analysis)",
  A3o = "Subtraction with true k (diagnostic)")

be_2x2 <- function(l1, l2, seq, keep, n, set = oc_settings()) {
  R <- length(l1) %/% n
  D <- matrix(l1 - l2, R, n, byrow = TRUE)
  K <- matrix(keep, R, n, byrow = TRUE)
  S <- matrix(seq, R, n, byrow = TRUE)
  D[!K] <- 0
  wa <- K & S == 1; wb <- K & S == 2
  na <- rowSums(wa); nb <- rowSums(wb)
  ma <- rowSums(D * wa) / na; mb <- rowSums(D * wb) / nb
  ss <- rowSums((D - ma)^2 * wa) + rowSums((D - mb)^2 * wb)
  df <- na + nb - 2
  ev <- (na + nb) >= set$min_evaluable & na >= 1 & nb >= 1
  est <- (ma - mb) / 2
  se <- 0.5 * sqrt(ss / df * (1 / na + 1 / nb))
  q <- qt(1 - (1 - set$conf) / 2, pmax(df, 1))
  lo <- est - q * se; hi <- est + q * se
  est[!ev] <- NA; se[!ev] <- NA; lo[!ev] <- NA; hi[!ev] <- NA
  be <- ev & !is.na(lo) & lo >= log(set$be_limits[1]) & hi <= log(set$be_limits[2])
  list(est = est, se = se, lo = lo, hi = hi, df = df, n_tr = na, n_rt = nb,
       evaluable = ev, be = be)
}

## M13A single-dose rule: exclude the participant when the period-2 pre-dose concentration
## exceeds 5% of that period's own Cmax (period 1 pre-dose is 0 by design)
m13a_exclude <- function(y2, cmax2, set = oc_settings()) y2[, 1] > set$predose_frac * cmax2

## predict-then-subtract: y-hat(t) = max(0, y(t) - y(0) exp(-lambda t)); a participant whose
## lambda is missing is left unadjusted
subtract_residual <- function(y2, times, lambda) {
  adj <- !is.na(lambda)
  lam <- ifelse(adj, lambda, 0)
  y <- y2 - (y2[, 1] * adj) * exp(-outer(lam, times))
  y[y < 0] <- 0
  y
}

## per-study summaries of one arm: endpoints, BE, and the M13A AUC coverage condition
arm_studies <- function(n1, n2, pop, keep, set = oc_settings()) {
  out <- list(
    AUC  = be_2x2(log(n1$auclast), log(n2$auclast), pop$seq, keep, pop$n, set),
    CMAX = be_2x2(log(n1$cmax), log(n2$cmax), pop$seq, keep, pop$n, set))
  R <- pop$R; n <- pop$n
  b1 <- matrix(n1$coverage < 0.80, R, n, byrow = TRUE); b2 <- matrix(n2$coverage < 0.80, R, n, byrow = TRUE)
  K <- matrix(keep, R, n, byrow = TRUE)
  v1 <- K & !is.na(b1); v2 <- K & !is.na(b2)
  nb <- rowSums(ifelse(v1, b1, FALSE)) + rowSums(ifelse(v2, b2, FALSE))
  nv <- rowSums(v1) + rowSums(v2)
  share <- ifelse(nv > 0, nb / nv, NA_real_)
  out$coverage <- list(share_below80 = share, trigger = share > 0.20)
  out
}

## all six arms for one washout (W: scalar hours or a vector, one per participant row)
analyze_washout <- function(pop, prof, obs1, obs2own, n1, n2own, W, cfg, lloq, set = oc_settings()) {
  times <- prof$times
  resid <- residual_profile(pop, prof, W, set)
  y2 <- observe(prof$c2 + resid, pop$e2, cfg$assay, lloq, set)
  n2 <- nca_matrix(y2, times)
  excl <- m13a_exclude(y2, n2$cmax, set)
  keep_all <- rep(TRUE, pop$m)
  y3  <- subtract_residual(y2, times, n1$lambda_z)
  y3o <- subtract_residual(y2, times, pop$k)
  n3 <- nca_matrix(y3, times); n3o <- nca_matrix(y3o, times)
  r_i <- residual_fraction(prof$c1, resid, times)
  list(
    arms = list(
      A0  = arm_studies(n1, n2own, pop, keep_all, set),
      A1  = arm_studies(n1, n2, pop, keep_all, set),
      A2  = arm_studies(n1, n2, pop, !excl, set),
      A2s = arm_studies(n1, n2own, pop, !excl, set),
      A3  = arm_studies(n1, n3, pop, keep_all, set),
      A3o = arm_studies(n1, n3o, pop, keep_all, set)),
    excl = excl, r = r_i, a0_excl = m13a_exclude(obs2own, n2own$cmax, set),
    a3_nolambda = is.na(n1$lambda_z),
    y2 = y2, y3_on_a0 = subtract_residual(obs2own, times, n1$lambda_z), obs2own = obs2own)
}

## --- aggregation with Monte Carlo standard errors ---------------------------------
mc_mean <- function(x) { x <- x[!is.na(x)]; k <- length(x)
  c(est = if (k) mean(x) else NA_real_, mcse = if (k > 1) sd(x) / sqrt(k) else NA_real_, k = k) }
mc_rate <- function(x) { x <- x[!is.na(x)]; k <- length(x); p <- if (k) mean(x) else NA_real_
  c(est = p, mcse = if (k) sqrt(p * (1 - p) / k) else NA_real_, k = k) }

## rows of oc_results.csv for one washout
summarize_washout <- function(res, pop, theta, set = oc_settings()) {
  R <- pop$R; n <- pop$n; lt <- log(theta)
  Kx <- matrix(res$excl, R, n, byrow = TRUE); S <- matrix(pop$seq, R, n, byrow = TRUE)
  excl_frac <- rowMeans(Kx)
  excl_tr <- rowSums(Kx & S == 1) / (n / 2); excl_rt <- rowSums(Kx & S == 2) / (n / 2)
  rm <- matrix(res$r, R, n, byrow = TRUE)
  cf <- 0.5 * (rowMeans(ifelse(S == 2, log(1 + rm / theta), NA), na.rm = TRUE) -
               rowMeans(ifelse(S == 1, log(1 + rm * theta), NA), na.rm = TRUE))
  rows <- list()
  for (a in names(res$arms)) {
    A <- res$arms[[a]]
    uses_rule <- a %in% c("A2", "A2s")
    for (ep in c("AUC", "CMAX", "AUC_CMAX")) {
      if (ep == "AUC_CMAX") {
        be <- A$AUC$be & A$CMAX$be; ev <- A$AUC$evaluable
        b <- c(est = NA, mcse = NA, k = sum(ev)); se_emp <- NA; cv <- c(NA, NA, NA)
      } else {
        S2 <- A[[ep]]; be <- S2$be; ev <- S2$evaluable
        b <- mc_mean(S2$est - lt); se_emp <- if (sum(ev) > 1) sd(S2$est, na.rm = TRUE) else NA
        cv <- mc_rate(ifelse(ev, S2$lo <= lt & lt <= S2$hi, NA))
      }
      p <- mc_rate(be); pe <- mc_rate(ifelse(ev, be, NA)); ne <- mc_rate(!ev)
      ex <- if (uses_rule) mc_mean(excl_frac) else c(0, 0, R)
      cov_cells <- if (ep == "AUC") list(mc_mean(A$coverage$share_below80), mc_rate(A$coverage$trigger))
                   else list(c(NA, NA, NA), c(NA, NA, NA))
      rows[[length(rows) + 1]] <- data.frame(
        arm = a, endpoint = ep, n_rep = R, n_eval = sum(ev),
        bias = b[["est"]], bias_mcse = b[["mcse"]], emp_se = se_emp,
        be_rate = p[["est"]], be_rate_mcse = p[["mcse"]],
        be_rate_eval = pe[["est"]], be_rate_eval_mcse = pe[["mcse"]],
        ci_coverage = cv[1], ci_coverage_mcse = cv[2],
        excl_frac = ex[1], excl_frac_mcse = ex[2],
        excl_frac_tr = if (uses_rule) mean(excl_tr) else 0, excl_frac_tr_mcse = if (uses_rule) sd(excl_tr) / sqrt(R) else 0,
        excl_frac_rt = if (uses_rule) mean(excl_rt) else 0, excl_frac_rt_mcse = if (uses_rule) sd(excl_rt) / sqrt(R) else 0,
        noneval_rate = ne[["est"]], noneval_rate_mcse = ne[["mcse"]],
        auc_cov_below80 = cov_cells[[1]][1], auc_cov_below80_mcse = cov_cells[[1]][2],
        auc_cov_trigger = cov_cells[[2]][1], auc_cov_trigger_mcse = cov_cells[[2]][2],
        a3_no_lambda_frac = if (a == "A3") mean(res$a3_nolambda) else NA_real_,
        mean_r = mean(res$r), closed_form_bias = if (ep == "AUC") mean(cf) else NA_real_,
        stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, rows)
}

## rows of oc_bias_decomposition.csv for one washout: A2 - A0 = (A2 - A2s) + (A2s - A0),
## paired within study (common random numbers). Bias terms use the studies that are
## evaluable under the rule; BE-rate terms use all studies (not evaluable = not BE).
decompose_washout <- function(res, pop) {
  rows <- list()
  for (ep in c("AUC", "CMAX")) {
    e0 <- res$arms$A0[[ep]]; e2 <- res$arms$A2[[ep]]; es <- res$arms$A2s[[ep]]
    ev <- e2$evaluable
    t <- mc_mean(ifelse(ev, e2$est - e0$est, NA)); rr <- mc_mean(ifelse(ev, e2$est - es$est, NA))
    s <- mc_mean(ifelse(ev, es$est - e0$est, NA))
    pt <- mc_mean(e2$be - e0$be); pr <- mc_mean(e2$be - es$be); ps <- mc_mean(es$be - e0$be)
    rows[[ep]] <- data.frame(endpoint = ep, n_rep = pop$R, n_eval = sum(ev),
      bias_total = t[["est"]], bias_total_mcse = t[["mcse"]],
      bias_retained = rr[["est"]], bias_retained_mcse = rr[["mcse"]],
      bias_selection = s[["est"]], bias_selection_mcse = s[["mcse"]],
      rate_total = pt[["est"]], rate_total_mcse = pt[["mcse"]],
      rate_retained = pr[["est"]], rate_retained_mcse = pr[["mcse"]],
      rate_selection = ps[["est"]], rate_selection_mcse = ps[["mcse"]],
      stringsAsFactors = FALSE)
  }
  do.call(rbind, rows)
}

## --- one (theta, disposition) cell: every configuration, washout and arm --------------
## washouts: named numeric vector of W / t1/2 multiples; "adequate" adds the KA1 control
## (W = 10 x the largest individual t1/2 in each replicate).
run_cell <- function(pop, theta, disposition, configs, washouts, lloq, adequate = TRUE,
                     set = oc_settings(), keep_studies = FALSE) {
  res_rows <- list(); dec_rows <- list(); studies <- list()
  Wlist <- as.list(washouts * set$t_half)
  names(Wlist) <- sprintf("%g", washouts)
  if (adequate) {
    tmax_rep <- tapply(log(2) / pop$k, pop$rep, max)
    Wlist[["adequate"]] <- rep(10 * as.numeric(tmax_rep), each = pop$n)
  }
  for (cn in names(configs)) {
    cfg <- configs[[cn]]
    prof <- true_profiles(pop, theta, cfg$times, disposition, set)
    obs1 <- observe(prof$c1, pop$e1, cfg$assay, lloq, set)
    obs2own <- observe(prof$c2, pop$e2, cfg$assay, lloq, set)
    n1 <- nca_matrix(obs1, cfg$times); n2own <- nca_matrix(obs2own, cfg$times)
    for (wn in names(Wlist)) {
      res <- analyze_washout(pop, prof, obs1, obs2own, n1, n2own, Wlist[[wn]], cfg, lloq, set)
      key <- data.frame(config = cn, theta = theta, disposition = disposition,
                        washout = wn, W_over_thalf = if (wn == "adequate") NA_real_ else as.numeric(wn),
                        W_h = if (wn == "adequate") NA_real_ else Wlist[[wn]][1], stringsAsFactors = FALSE)
      s <- summarize_washout(res, pop, theta, set)
      res_rows[[length(res_rows) + 1]] <- cbind(key[rep(1, nrow(s)), ], s, row.names = NULL)
      d <- decompose_washout(res, pop)
      dec_rows[[length(dec_rows) + 1]] <- cbind(key[rep(1, nrow(d)), ], d, row.names = NULL)
      if (keep_studies) studies[[paste(cn, wn)]] <- res
    }
  }
  list(results = do.call(rbind, res_rows), decomposition = do.call(rbind, dec_rows),
       studies = if (keep_studies) studies else NULL)
}

## --- grid, random-number streams and replicate sizing -------------------------------
## The (theta, disposition) cells, in stream order (theta varies fastest).
oc_cells <- function() expand.grid(theta = c(0.80, 0.95, 1.00, 1.25),
                                   disposition = c("mono", "biexp"), stringsAsFactors = FALSE)
OC_WASHOUTS <- c(2, 3, 4, 5, 6, 8, 10)          # W / mean t1/2
OC_SEED <- 20261025L

## RNGkind("L'Ecuyer-CMRG"), set.seed(20261025), then one parallel::nextRNGStream per cell;
## one further stream (the last) is used only for the configuration-B LLOQ.
oc_streams <- function(n_cells, seed = OC_SEED) {
  RNGkind("L'Ecuyer-CMRG", "Inversion", "Rejection"); set.seed(seed)
  s <- .Random.seed; out <- vector("list", n_cells + 1L)
  for (i in seq_len(n_cells + 1L)) { s <- parallel::nextRNGStream(s); out[[i]] <- s }
  out
}
use_stream <- function(s) assign(".Random.seed", s, envir = globalenv())

## replicates for a target MCSE of a rate p: MCSE = sqrt(p (1 - p) / R), rounded up to `step`
reps_for_mcse <- function(p = 0.05, target = 0.005, step = 500L) {
  as.integer(ceiling(p * (1 - p) / target^2 / step) * step)
}
mcse_rate <- function(p, R) sqrt(p * (1 - p) / R)

## write a data frame with doubles at 12 significant digits (as sim_lifecycle/run_lifecycle.R
## does), so the files regenerate identically across platforms
write_oc_csv <- function(d, path) {
  dbl <- vapply(d, is.double, logical(1))
  d[dbl] <- lapply(d[dbl], signif, digits = 12)
  write.csv(d, path, row.names = FALSE)
}
