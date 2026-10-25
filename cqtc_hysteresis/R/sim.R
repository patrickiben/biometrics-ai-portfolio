################################################################################
# cqtc_hysteresis/R/sim.R
# Data-generating model (DGM) for the synthetic known-answer demo of the C-QTc
# hysteresis check. Base R only. Synthetic data only: nothing here is trial data.
#
# One-compartment oral PK with first-order absorption, an effect compartment
# (dCe/dt = ke0 (C - Ce), solved analytically) and three effect models:
#   linear     drug effect = slope * Ce
#   emax       drug effect = emax * Ce / (Ce + ec50)
#   tolerance  drug effect = slope * C - gamma * M,  dM/dt = k_m (C - M)
# Each active and placebo participant's dQTcF also carries a common daily
# rhythm and N(0, sd^2) noise. ddQTcF is built as the TLF shells build it:
# active dQTcF minus the time-matched mean dQTcF of a pooled placebo group, so
# the placebo-mean noise is shared by every active participant. A crossover
# variant ("within") corrects each participant by their own placebo period.
# An optional residual term (active participants only, Day 1 and Day -1) is a
# time pattern the placebo correction does not remove (negative control NC1).
################################################################################

DEFAULT_TIMES <- c(0, 0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24)   # hours

## plasma concentration, one-compartment oral (D/V = dv, so C is in dose/volume units)
pk_conc <- function(t, ka, ke, dv = 2) {
  dv * ka / (ka - ke) * (exp(-ke * t) - exp(-ka * t))
}

## effect-compartment concentration for the same PK, analytic solution with Ce(0) = 0.
## ke0 = Inf gives Ce = C (direct effect). Rate constants that coincide are nudged by
## 1e-9 so the three-exponential form stays defined (a measure-zero event here).
effect_conc <- function(t, ka, ke, ke0, dv = 2) {
  if (is.infinite(ke0)) return(pk_conc(t, ka, ke, dv))
  if (abs(ke0 - ke) < 1e-9) ke0 <- ke0 + 1e-9
  if (abs(ke0 - ka) < 1e-9) ke0 <- ke0 + 1e-9
  dv * ka * ke0 * (exp(-ke * t)  / ((ka - ke)  * (ke0 - ke)) +
                   exp(-ka * t)  / ((ke - ka)  * (ke0 - ka)) +
                   exp(-ke0 * t) / ((ke - ke0) * (ka - ke0)))
}

## a time-of-day term (ms): the common rhythm, or the residual term of NC1
diurnal <- function(t, amp = 3, phi = 0) amp * sin(2 * pi * (t + phi) / 24)

## Simulate one trial: n active participants and a pooled placebo group of n_pbo
## on a common nominal grid `times`. Returns matrices (rows = participants,
## columns = times):
##   C    plasma concentration (noise-free; see the page's "What it does not do")
##   dY   active Day 1 dQTcF (ms): drug effect + common rhythm + residual + noise
##   P    placebo dQTcF (n_pbo x m) whose time-matched mean corrects dY
##        (placebo = "within": each active participant's own placebo period, n x m)
##   Y    ddQTcF = dY - colMeans(P) (pooled) or dY - P (within)
##   D1A  active Day -1 QTcF, centered within participant (no drug)
##   D1P  placebo Day -1 QTcF, centered within participant (within: own period)
##   D1   Day -1 series corrected the same way as Day 1: D1A - colMeans(D1P), or D1A - D1P
## and the true PK parameters. The common rhythm (common_amp, common_phi) is on
## every participant on both days, so the time-matched correction removes it
## exactly. The residual term (diurnal_amp, phi) is on active participants only,
## on both days. Random numbers are drawn in a fixed order: ka, ke, active Day 1
## noise, placebo Day 1 noise, active Day -1 noise, placebo Day -1 noise.
sim_trial <- function(n = 32, n_pbo = 8, placebo = c("pooled", "within"),
                      times = DEFAULT_TIMES,
                      model = c("linear", "emax", "tolerance"),
                      ke0 = Inf, slope = 4, emax = 20, ec50 = 0.4,
                      gamma = 2, k_m = 0.35, sd = 5,
                      common_amp = 4, common_phi = 18,
                      diurnal_amp = 0, phi = 0, dv = 2,
                      ka_pop = 1.2, ke_pop = 0.15, omega = 0.3) {
  model <- match.arg(model); placebo <- match.arg(placebo)
  m <- length(times)
  np <- if (placebo == "within") n else n_pbo
  ka <- ka_pop * exp(rnorm(n, 0, omega))
  ke <- ke_pop * exp(rnorm(n, 0, omega))
  C <- E <- matrix(0, n, m)
  for (i in seq_len(n)) {
    C[i, ] <- pk_conc(times, ka[i], ke[i], dv)
    E[i, ] <- switch(model,
      linear    = slope * effect_conc(times, ka[i], ke[i], ke0, dv),
      emax      = { ce <- effect_conc(times, ka[i], ke[i], ke0, dv); emax * ce / (ce + ec50) },
      tolerance = slope * C[i, ] - gamma * effect_conc(times, ka[i], ke[i], k_m, dv))
  }
  rowm <- function(v, k) matrix(v, k, m, byrow = TRUE)
  com <- diurnal(times, common_amp, common_phi)
  res <- diurnal(times, diurnal_amp, phi)
  dY  <- E + rowm(com + res, n) + matrix(rnorm(n * m, 0, sd), n, m)
  P   <- rowm(com, np) + matrix(rnorm(np * m, 0, sd), np, m)
  D1A <- rowm(com + res, n) + matrix(rnorm(n * m, 0, sd), n, m)
  D1P <- rowm(com, np) + matrix(rnorm(np * m, 0, sd), np, m)
  D1A <- D1A - rowMeans(D1A); D1P <- D1P - rowMeans(D1P)   # centered within participant
  if (placebo == "pooled") {
    Y  <- sweep(dY, 2, colMeans(P));  D1 <- sweep(D1A, 2, colMeans(D1P))
  } else {
    Y  <- dY - P;                     D1 <- D1A - D1P
  }
  list(times = times, C = C, dY = dY, P = P, Y = Y, D1A = D1A, D1P = D1P, D1 = D1,
       placebo = placebo, ka = ka, ke = ke,
       truth = list(model = model, ke0 = ke0, slope = slope, emax = emax, ec50 = ec50,
                    gamma = gamma, k_m = k_m, sd = sd, n_pbo = np, common_amp = common_amp,
                    common_phi = common_phi, diurnal_amp = diurnal_amp, phi = phi))
}

## Noise-free typical-participant profile (ka = 1.2, ke = 0.15) for figures and
## for the noise-free area checks; `times` may be a dense grid.
typical_profile <- function(times = DEFAULT_TIMES, model = c("linear", "emax", "tolerance"),
                            ke0 = Inf, slope = 4, emax = 20, ec50 = 0.4,
                            gamma = 2, k_m = 0.35, dv = 2, ka = 1.2, ke = 0.15,
                            diurnal_amp = 0, phi = 0) {
  model <- match.arg(model)
  C <- pk_conc(times, ka, ke, dv)
  E <- switch(model,
    linear    = slope * effect_conc(times, ka, ke, ke0, dv),
    emax      = { ce <- effect_conc(times, ka, ke, ke0, dv); emax * ce / (ce + ec50) },
    tolerance = slope * C - gamma * effect_conc(times, ka, ke, k_m, dv))
  list(times = times, C = C, E = E + diurnal(times, diurnal_amp, phi))
}
