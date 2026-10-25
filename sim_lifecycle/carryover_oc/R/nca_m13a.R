################################################################################
# carryover_oc/R/nca_m13a.R: NCA for many profiles at once, following the ICH M13A
# conventions used in this study. SYNTHETIC DATA ONLY.
#
#   AUC(0-t)  linear trapezoid from t = 0 (the pre-dose sample is kept) to the last
#             quantifiable concentration; BLQ samples are 0 (they are 0 in Y already).
#   Cmax      maximum observed concentration; Tmax its first time.
#   lambda_z  log-linear least squares on the last 3 positive concentrations (at least 3
#             required; zeros never enter the fit).
#   AUC(0-inf) = AUC(0-t) + Clast / lambda_z, used only for the M13A coverage condition
#             AUC(0-t) / AUC(0-inf) >= 0.80.
# Y is an m x J matrix of concentrations (one profile per row) on the time vector t.
################################################################################

lambda_z_last3 <- function(Y, t, npts = 3L) {
  m <- nrow(Y); J <- ncol(Y)
  pos <- Y > 0
  sel <- matrix(FALSE, m, J); cnt <- integer(m)
  for (j in J:1) { take <- pos[, j] & cnt < npts; sel[, j] <- take; cnt <- cnt + take }
  X <- matrix(t, m, J, byrow = TRUE)
  L <- log(ifelse(sel, Y, 1))
  sw <- rowSums(sel); sx <- rowSums(X * sel); sy <- rowSums(L * sel)
  sxx <- rowSums(X^2 * sel); sxy <- rowSums(X * L * sel)
  slope <- (sxy - sx * sy / sw) / (sxx - sx^2 / sw)
  lz <- -slope
  lz[cnt < npts] <- NA_real_
  lz
}

nca_matrix <- function(Y, t) {
  m <- nrow(Y); J <- ncol(Y)
  stopifnot(length(t) == J, all(diff(t) > 0), t[1] == 0)
  pos <- Y > 0
  last <- integer(m)
  for (j in seq_len(J)) last[pos[, j]] <- j
  auc <- numeric(m)
  for (j in seq_len(J - 1)) {
    seg <- (t[j + 1] - t[j]) * (Y[, j] + Y[, j + 1]) / 2
    auc <- auc + ifelse(j + 1 <= last, seg, 0)
  }
  cmax <- Y[, 1]; tmax <- rep(t[1], m)
  for (j in seq_len(J)[-1]) { up <- Y[, j] > cmax; cmax[up] <- Y[up, j]; tmax[up] <- t[j] }
  lz <- lambda_z_last3(Y, t)
  clast <- ifelse(last > 0, Y[cbind(seq_len(m), pmax(last, 1L))], 0)
  aucinf <- ifelse(!is.na(lz) & lz > 0, auc + clast / lz, NA_real_)
  list(auclast = auc, cmax = cmax, tmax = tmax, lambda_z = lz, clast = clast,
       aucinf = aucinf, coverage = auc / aucinf)
}

## one profile (vectors), for checks by hand
nca_one_profile <- function(t, conc) {
  r <- nca_matrix(matrix(conc, nrow = 1), t)
  vapply(r, function(v) v[1], numeric(1))
}
