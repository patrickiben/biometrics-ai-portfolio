################################################################################
# TABLE     : t_cqtc_hysteresis  (Single Ascending Dose)
# TITLE     : Assessment of Delay between Concentration and ddQTcF before the
#             C-QTc Analysis: Mean Signed Loop Area on Direct-Effect Model
#             Residuals, by Dose
# POPULATION: C-QTc Analysis Set (PKFL == "Y" and SAFFL == "Y"), active doses
# INPUT     : ADEG (PARAMCD == "QTCF"; CHG on Day 1, AVAL on Day -1, ATPTN),
#             ADPC (PARAMCD == "CONC"; AVAL, AFRLT actual time, ATPTN)
# NOTE      : PSEUDOCODE. The prespecified hysteresis check (SAP text: see
#             cqtc_hysteresis/index.html). Steps:
#             1. ddQTcF = CHG minus the time-matched placebo mean CHG (placebo
#                pooled); concentrations time-matched on nominal time; each
#                participant's records ordered by ACTUAL time (AFRLT).
#             2. Fit the prespecified direct-effect model with NO time factor on
#                all active doses: ddQTcF = f(C) + b_i + e, f linear, or Emax if
#                the SAP's linearity check selects it (FORM below). A time factor
#                would absorb the delay this step looks for.
#             3. r = ddQTcF - f-hat(C) - b-hat_i; x = C / participant's Cmax.
#             4. A_i = 0.5 * sum_j (x_j r_(j+1) - x_(j+1) r_j), closed path
#                (index m+1 = 1); A_i > 0 = counterclockwise = effect lags.
#             5. Test mean(A_i) by participant-level sign flips: exact (all 2^n
#                sign vectors) when n <= 20, otherwise 9,999 random sign vectors,
#                p = (1 + #{T* >= T}) / (9,999 + 1). One- and two-sided.
#             6. Report beside it: A-bar with a t-based 95% CI, the tmax gap
#                (median time of peak ddQTcF minus median tmax; and the peak of
#                the mean profile minus median tmax) and the Day -1 pseudo-loop
#                check (Day -1 QTcF, centered and corrected the same way, paired
#                with Day 1 x). Rows: each active dose, then all active doses.
#             A significant result prompts an effect-compartment model; it does
#             not replace the C-QTc analysis. Mirrors cqtc_hysteresis/R/area.R.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                       # TRT01A = dose level; TRT01AN = dose

PCCD  <- "CONC"     # parent analyte PARAMCD in ADPC
FORM  <- "LINEAR"   # prespecified f: "LINEAR", or "EMAX" if the SAP linearity check selects it
SEED  <- 20261025   # SAP-specified seed for the random sign vectors (n > 20)
NSIGN <- 9999       # random sign vectors when n > 20

## ---- helpers (as in cqtc_hysteresis/R/area.R) ---------------------------------
loop_area <- function(x, y) {                     # closed-path shoelace area
  j <- c(seq_along(x)[-1], 1L)
  0.5 * sum(x * y[j] - x[j] * y)
}
signflip <- function(A) {                         # participant-level sign-flip test of mean(A)
  n <- length(A); T0 <- mean(A); tol <- 1e-10 * mean(abs(A))
  if (n <= 20) {                                  # exact: all 2^n signed sums
    s <- 0; for (a in A) s <- c(s + a, s - a); Ts <- s / n
    c(p1 = mean(Ts >= T0 - tol), p2 = mean(abs(Ts) >= abs(T0) - tol))
  } else {
    set.seed(SEED)
    Ts <- drop(matrix(sample(c(-1, 1), NSIGN * n, replace = TRUE), NSIGN, n) %*% A) / n
    c(p1 = (1 + sum(Ts >= T0 - tol)) / (NSIGN + 1), p2 = (1 + sum(abs(Ts) >= abs(T0) - tol)) / (NSIGN + 1))
  }
}

## ---- Day 1: ddQTcF with time-matched concentrations ------------------------------
eg <- adam$adeg %>%
  filter(SAFFL == "Y", ANL01FL == "Y", PARAMCD == "QTCF", ADY == 1, !is.na(CHG)) %>%
  transmute(USUBJID, trt = .data[[dv$trtvar]], dose = .data[[dv$trtnvar]], ATPTN, CHG)
pbo <- eg %>% filter(dose == 0) %>% group_by(ATPTN) %>% summarise(pbo = mean(CHG), .groups = "drop")
pc  <- adam$adpc %>%
  filter(PKFL == "Y", PARAMCD == PCCD, !is.na(AVAL)) %>%
  transmute(USUBJID, ATPTN, AFRLT, conc = AVAL)
cq <- eg %>% filter(dose > 0) %>%
  inner_join(pbo, by = "ATPTN") %>%
  mutate(ddqtcf = CHG - pbo) %>%
  inner_join(pc, by = c("USUBJID", "ATPTN")) %>%
  arrange(USUBJID, AFRLT)                         # time order = actual time

## ---- Day -1: centered QTcF, corrected the same way as Day 1 ----------------------
d1 <- adam$adeg %>%
  filter(SAFFL == "Y", PARAMCD == "QTCF", ADY == -1, !is.na(AVAL)) %>%
  group_by(USUBJID) %>% mutate(qc = AVAL - mean(AVAL)) %>% ungroup() %>%
  transmute(USUBJID, dose = .data[[dv$trtnvar]], ATPTN, qc)
d1 <- d1 %>% filter(dose > 0) %>%
  inner_join(d1 %>% filter(dose == 0) %>% group_by(ATPTN) %>% summarise(pqc = mean(qc), .groups = "drop"),
             by = "ATPTN") %>%
  transmute(USUBJID, ATPTN, dm1 = qc - pqc)

## ---- prespecified direct-effect model, no time factor, all active doses ----------
fit <- if (FORM == "LINEAR") {
  nlme::lme(ddqtcf ~ conc, random = ~ 1 | USUBJID, data = cq, method = "REML")
} else {
  nlme::nlme(ddqtcf ~ e0 + emax * conc / (ec50 + conc), data = cq,
             fixed = e0 + emax + ec50 ~ 1, random = e0 ~ 1 | USUBJID,
             start = c(e0 = 0, emax = 20, ec50 = median(cq$conc[cq$conc > 0])))   # starts per SAP
}
cq$resid <- cq$ddqtcf - fitted(fit, level = 1)    # r = ddQTcF - f-hat(C) - b-hat_i

## ---- per-participant signed areas and tmax quantities ------------------------------
part <- cq %>%
  left_join(d1, by = c("USUBJID", "ATPTN")) %>%
  group_by(USUBJID, trt, dose) %>%
  summarise(m      = n(),
            A      = loop_area(conc / max(conc), resid),
            A_dm1  = if (all(!is.na(dm1))) loop_area(conc / max(conc), dm1) else NA_real_,
            tmax   = ATPTN[which.max(conc)],
            tpeak  = ATPTN[which.max(ddqtcf)],
            .groups = "drop")
## the mean ddQTcF profile per dose, for the mean-profile tmax gap
prof <- cq %>% group_by(dose, ATPTN) %>% summarise(mdd = mean(ddqtcf), .groups = "drop")

summ <- function(d, pr, label) {
  ci <- mean(d$A) + c(-1, 1) * qt(0.975, nrow(d) - 1) * sd(d$A) / sqrt(nrow(d))
  p  <- signflip(d$A)
  a1 <- d$A_dm1[!is.na(d$A_dm1)]
  tibble(
    `Dose`                       = label,
    `n`                          = as.character(n_distinct(d$USUBJID)),
    `Mean area, ms (95% CI)`     = sprintf("%.2f (%.2f, %.2f)", mean(d$A), ci[1], ci[2]),
    `p one-sided`                = sprintf("%.4f", p[["p1"]]),
    `p two-sided`                = sprintf("%.4f", p[["p2"]]),
    `tmax gap, h (individual)`   = sprintf("%.1f", median(d$tpeak) - median(d$tmax)),
    `tmax gap, h (mean profile)` = sprintf("%.1f", pr$ATPTN[which.max(pr$mdd)] - median(d$tmax)),
    `Day -1 mean area, ms (p two-sided)` =
      if (length(a1) > 1) sprintf("%.2f (%.4f)", mean(a1), signflip(a1)[["p2"]]) else "NE",
    `Model for f`                = if (FORM == "LINEAR") "Linear" else "Emax")
}
doses <- sort(unique(part$dose))
tab <- bind_rows(
  lapply(doses, function(dd) summ(part %>% filter(dose == dd), prof %>% filter(dose == dd),
                                  as.character(part$trt[part$dose == dd][1]))),
  ## pooled profile for the all-doses row: mean over participants of all active doses
  summ(part, cq %>% group_by(ATPTN) %>% summarise(mdd = mean(ddqtcf), .groups = "drop"), "All active doses"))

ttl <- tfl_titles(num = "14.3.5.5", type = "Table",
   text = "Assessment of Delay between Concentration and ddQTcF: Mean Signed Loop Area on Direct-Effect Model Residuals, by Dose",
   pop  = "C-QTc Analysis Set",
   foot = paste(
     "Area = signed area of each participant's closed path of (concentration / participant Cmax, residual ddQTcF) in time order;",
     "positive = counterclockwise = effect lags concentration. Residuals from the prespecified direct-effect model",
     "(no time factor, participant random intercept) fitted to all active doses.",
     "p: participant-level sign-flip test, exact for n <= 20, otherwise 9,999 random sign vectors.",
     "tmax gap: median time of peak ddQTcF (individual) or time of peak mean ddQTcF (mean profile) minus median tmax; > 1 h is flagged in the SAP.",
     "Day -1: Day -1 time-matched QTcF, centered and placebo-corrected as on Day 1, paired with Day 1 concentrations; no drug, so any area reflects timing alone.",
     "NE = not evaluable. A significant result prompts an effect-compartment model; it does not replace the C-QTc analysis."))

print(tab)
