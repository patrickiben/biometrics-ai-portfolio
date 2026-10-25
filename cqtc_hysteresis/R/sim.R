################################################################################
# cqtc_hysteresis/R/sim.R
# Data-generating model (DGM) for the synthetic known-answer demo of the C-QTc
# hysteresis check. Base R only. Synthetic data only: nothing here is trial data.
#
# One-compartment oral PK with first-order absorption, an effect compartment
# (dCe/dt = ke0 (C - Ce), solved analytically) and three effect models:
#   linear     ddQTcF = slope * Ce
#   emax       ddQTcF = emax * Ce / (Ce + ec50)
#   tolerance  ddQTcF = slope * C - gamma * M,  dM/dt = k_m (C - M)
# plus N(0, sd^2) noise, an optional residual diurnal term left uncorrected,
# and a Day -1 series (no drug) on the same scale as the Day 1 analysis value.
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

## residual diurnal term (ms) that a correction failed to remove
diurnal <- function(t, amp = 3, phi = 0) amp * sin(2 * pi * (t + phi) / 24)

## Simulate one trial: n active participants on a common nominal grid `times`.
## Returns matrices (rows = participants, columns = times):
##   C   plasma concentration (noise-free; see the page's "What it does not do")
##   Y   Day 1 ddQTcF (ms)
##   D1  Day -1 time-matched QTcF, centered within participant (no drug)
## and the true PK parameters. The Day -1 series carries the same residual
## diurnal term as Day 1 when diurnal_amp > 0, and only noise otherwise.
sim_trial <- function(n = 32, times = DEFAULT_TIMES,
                      model = c("linear", "emax", "tolerance"),
                      ke0 = Inf, slope = 4, emax = 20, ec50 = 0.4,
                      gamma = 2, k_m = 0.35, sd = 5,
                      diurnal_amp = 0, phi = 0, dv = 2,
                      ka_pop = 1.2, ke_pop = 0.15, omega = 0.3) {
  model <- match.arg(model)
  m <- length(times)
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
  dirn <- matrix(diurnal(times, diurnal_amp, phi), n, m, byrow = TRUE)
  Y  <- E + dirn + matrix(rnorm(n * m, 0, sd), n, m)
  D1 <- dirn + matrix(rnorm(n * m, 0, sd), n, m)
  D1 <- D1 - rowMeans(D1)                       # centered within participant
  list(times = times, C = C, Y = Y, D1 = D1, ka = ka, ke = ke,
       truth = list(model = model, ke0 = ke0, slope = slope, emax = emax, ec50 = ec50,
                    gamma = gamma, k_m = k_m, sd = sd, diurnal_amp = diurnal_amp, phi = phi))
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
