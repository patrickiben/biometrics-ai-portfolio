################################################################################
# carryover_oc/R/dgm.R: data-generating model for the residual-carryover study of the
# ICH M13A 5% pre-dose rule in a single-dose 2x2 crossover. SYNTHETIC DATA ONLY.
#
# Own-dose profile (one compartment, first-order absorption, linear PK):
#   c_ip(t) = phi_f F_i w_ip (D/V) ka_i / (ka_i - k_i) (exp(-k_i t) - exp(-ka_i t))
# Superposition: period 1 is y_i1(t) = c_i1(t); period 2 is y_i2(t) = c_i2(t) + c_i1(t + W).
# Misspecification ("biexp"): a slow phase 0.03 phi_f F_i w_ip exp(-(k_i/4) t)(1 - exp(-ka_i t))
# is added to both periods and to the residual. phi_R = 1, phi_T = theta.
# Sequences: within each replicate the first n/2 participants are TR, the rest RT.
# Storage: participant-level vectors have length m = R * n in replicate-major order
# (replicate r holds positions (r - 1) n + 1 .. r n); profiles are m x J matrices.
################################################################################

## --- settings ---------------------------------------------------------------
oc_settings <- function(...) {
  s <- list(
    n = 24L,                      # participants per study (n/2 per sequence)
    t_half = 24,                  # mean (median) elimination half-life, h
    sd_k = 0.30,                  # k_i = (ln 2 / t_half) exp(N(0, sd_k^2))
    ka = 1.2, sd_ka = 0.20,       # ka_i = 1.2 exp(N(0, 0.20^2)) per h
    sd_F = 0.20,                  # F_i = exp(N(0, 0.20^2))
    sd_w = 0.15,                  # w_ip = exp(N(0, 0.15^2)), one per period
    dose_over_v = 2,              # D/V
    times = c(0, 0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 36, 48, 72),
    times_ext = c(96, 120),       # sensitivity: extended sampling
    slow_frac = 0.03, slow_k_ratio = 1/4,
    assay_sd = 0.08,              # configuration B: 8% proportional (log-normal) assay error
    lloq_frac = 0.005,            # configuration B: LLOQ = 0.5% of the median Cmax
    predose_frac = 0.05,          # M13A: exclude a period whose pre-dose conc > 5% of its Cmax
    min_evaluable = 12L,          # M13A: at least 12 evaluable participants
    be_limits = c(0.80, 1.25),    # acceptance range for the 90% CI of the GMR
    conf = 0.90)
  modifyList(s, list(...))
}

## the three sampling and assay configurations of the study
oc_configs <- function(set = oc_settings()) list(
  base     = list(label = "Base: no assay error, sampling to 72 h", times = set$times, assay = FALSE),
  assay    = list(label = "Configuration B: 8% assay error, LLOQ 0.5% of median Cmax", times = set$times, assay = TRUE),
  extended = list(label = "Sampling extended to 96 and 120 h", times = c(set$times, set$times_ext), assay = FALSE))

## --- participants -------------------------------------------------------------
## One call draws everything a (theta, disposition) cell needs, in a fixed order: k, ka, F, w1,
## w2, then the assay errors for the longest sampling grid. Every washout, arm and configuration
## of the cell reuses these draws (common random numbers).
draw_population <- function(R, set = oc_settings()) {
  n <- set$n; m <- R * n; J <- length(set$times) + length(set$times_ext)
  stopifnot(n %% 2 == 0)
  pop <- list(R = R, n = n, m = m,
              rep = rep(seq_len(R), each = n),
              seq = rep(rep(1:2, each = n / 2), times = R))   # 1 = TR, 2 = RT
  pop$k  <- (log(2) / set$t_half) * exp(rnorm(m, 0, set$sd_k))
  pop$ka <- set$ka * exp(rnorm(m, 0, set$sd_ka))
  pop$F  <- exp(rnorm(m, 0, set$sd_F))
  pop$w1 <- exp(rnorm(m, 0, set$sd_w))
  pop$w2 <- exp(rnorm(m, 0, set$sd_w))
  pop$e1 <- matrix(rnorm(m * J), m, J)                        # standard normal assay errors
  pop$e2 <- matrix(rnorm(m * J), m, J)
  pop
}

## --- profiles -----------------------------------------------------------------
## amt = phi_f F_i w_ip (length m). tt: a time vector (shared by every row) or an m x J matrix.
own_conc <- function(tt, amt, k, ka, disposition = "mono", set = oc_settings()) {
  m <- length(amt)
  TT <- if (is.matrix(tt)) tt else matrix(tt, m, length(tt), byrow = TRUE)
  on <- TT > 0
  TT <- pmax(TT, 0)
  y <- amt * set$dose_over_v * ka / (ka - k) * (exp(-k * TT) - exp(-ka * TT))
  if (identical(disposition, "biexp"))
    y <- y + amt * set$slow_frac * exp(-(k * set$slow_k_ratio) * TT) * (1 - exp(-ka * TT))
  y * on
}

## formulation factor by sequence and period (TR: T then R; RT: R then T)
phi_period <- function(seq, period, theta) {
  if (period == 1) ifelse(seq == 1, theta, 1) else ifelse(seq == 1, 1, theta)
}

## Noise-free profiles for one cell and sampling grid; the residual is added per washout.
## W may be a scalar or a vector of length m (one washout per participant row).
true_profiles <- function(pop, theta, times, disposition = "mono", set = oc_settings()) {
  amt1 <- phi_period(pop$seq, 1, theta) * pop$F * pop$w1
  amt2 <- phi_period(pop$seq, 2, theta) * pop$F * pop$w2
  list(times = times, amt1 = amt1, amt2 = amt2, disposition = disposition,
       c1 = own_conc(times, amt1, pop$k, pop$ka, disposition, set),
       c2 = own_conc(times, amt2, pop$k, pop$ka, disposition, set))
}
residual_profile <- function(pop, prof, W, set = oc_settings()) {
  W <- rep_len(W, pop$m)
  own_conc(outer(W, prof$times, "+"), prof$amt1, pop$k, pop$ka, prof$disposition, set)
}

## Observation: optional proportional (log-normal) assay error, then BLQ = 0 (M13A). The error
## for a sample is the same whether or not a residual is present (common random numbers).
observe <- function(Y, E, assay, lloq, set = oc_settings()) {
  if (!assay) return(Y)
  Z <- Y * exp(set$assay_sd * E[, seq_len(ncol(Y)), drop = FALSE])
  Z[Z < lloq] <- 0
  Z
}

## LLOQ for configuration B: 0.5% of the median reference-formulation Cmax (noise-free,
## base grid, monoexponential) in a large draw from the participant distribution. The caller
## sets the RNG stream (run_oc.R uses its own stream for this).
lloq_from_population <- function(m_draw = 100000L, set = oc_settings()) {
  k  <- (log(2) / set$t_half) * exp(rnorm(m_draw, 0, set$sd_k))
  ka <- set$ka * exp(rnorm(m_draw, 0, set$sd_ka))
  amt <- exp(rnorm(m_draw, 0, set$sd_F)) * exp(rnorm(m_draw, 0, set$sd_w))
  Y <- own_conc(set$times, amt, k, ka, "mono", set)
  set$lloq_frac * stats::median(do.call(pmax, as.data.frame(Y)))
}

## residual fraction r_i = AUC_trap[c_i1(. + W)] / AUC_trap[c_i1] on the sampling grid
## (noise-free; phi, F and w cancel)
residual_fraction <- function(c1, resid, times) {
  trap <- function(Y) {
    s <- 0; for (j in seq_len(length(times) - 1))
      s <- s + (times[j + 1] - times[j]) * (Y[, j] + Y[, j + 1]) / 2
    s }
  trap(resid) / trap(c1)
}

## closed form for E[log GMR-hat] under the naive analysis with residual fraction r
## (constant r, no within-participant noise), and its first-order approximation
closed_form_log_gmr <- function(theta, r) log(theta) + 0.5 * (log(1 + r / theta) - log(1 + r * theta))
closed_form_approx  <- function(theta, r) log(theta) - (r / 2) * (theta - 1 / theta)
