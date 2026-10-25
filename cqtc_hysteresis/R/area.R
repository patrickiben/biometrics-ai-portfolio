################################################################################
# cqtc_hysteresis/R/area.R
# The C-QTc hysteresis check: signed loop area of each participant's
# (scaled concentration, residual ddQTcF) path, computed on residuals from the
# prespecified direct-effect model, with a participant-level sign-flip test.
# Base R; nlme (a recommended package that ships with R) only for the optional
# random-intercept comparison fit. Synthetic data only.
#
# Conventions (the page states them in full):
#   * rows = participants, columns = sampling times in increasing actual time
#   * x_ij = C_ij / max_j C_ij (each participant's own Cmax; prespecified)
#   * A_i = 0.5 * sum_j (x_j r_{j+1} - x_{j+1} r_j), index m+1 = 1 (closed path);
#     A_i > 0 = counterclockwise = effect lags concentration
#   * direct-effect model, no time factor: y_ij = f(C_ij; theta) + b_i + e_ij,
#     f linear (theta0 + theta1 C) or Emax (E0 + Emax C / (EC50 + C))
################################################################################

## ---- signed area ------------------------------------------------------------
## closed-path shoelace area of one path
loop_area <- function(x, y) {
  m <- length(x); j <- c(seq_len(m)[-1], 1L)
  0.5 * sum(x * y[j] - x[j] * y)
}
## row-wise areas for matrices (one participant per row)
loop_areas <- function(X, Y) {
  m <- ncol(X); j <- c(seq_len(m)[-1], 1L)
  0.5 * rowSums(X * Y[, j, drop = FALSE] - X[, j, drop = FALSE] * Y)
}
## concentration scaled to each participant's Cmax
scale_conc <- function(C) C / apply(C, 1, max)

## ---- direct-effect model fits -------------------------------------------------
## The b_i are participant intercepts. They are estimated here as fixed effects
## (the within estimator: profile least squares on participant-centered data).
## A constant has zero closed-path area, so b_i never changes A_i; only the shape
## of f does. fit_direct_nlme() below gives the random-intercept fit for comparison.
center_rows <- function(M) M - rowMeans(M)

fit_linear <- function(C, Y) {
  Cc <- center_rows(C); Yc <- center_rows(Y)
  theta1 <- sum(Cc * Yc) / sum(Cc^2)
  icpt <- rowMeans(Y) - theta1 * rowMeans(C)          # theta0 + b_i
  fitted <- icpt + theta1 * C
  rss <- sum((Y - fitted)^2)
  N <- length(Y); n <- nrow(Y)
  list(form = "linear", theta = c(theta0 = mean(icpt), theta1 = theta1),
       b = icpt - mean(icpt), fitted = fitted, rss = rss,
       sigma = sqrt(rss / (N - n - 1)),
       aic = N * log(rss / N) + 2 * (n + 1 + 1), boundary = FALSE)
}

## EC50 grid for the profile fit, relative to the largest concentration observed
ec50_grid <- function(C, K = 241, lo = 0.005, hi = 100) {
  exp(seq(log(lo * max(C)), log(hi * max(C)), length.out = K))
}

## Profile least squares for Emax with participant intercepts, for one or many
## response matrices that share the concentrations C. Yc_rows is a B x N matrix of
## participant-centered responses, each row as.vector() of an n x m matrix.
## Returns EC50 and Emax per row. A parabolic step in log(EC50) refines the grid.
emax_profile_rows <- function(C, Yc_rows, grid = ec50_grid(C)) {
  K <- length(grid)
  G <- vapply(grid, function(e) as.vector(center_rows(C / (e + C))), numeric(length(C)))
  ssg <- colSums(G^2)
  cross <- Yc_rows %*% G                                   # B x K
  ssy <- rowSums(Yc_rows^2)
  rss <- ssy - sweep(cross^2, 2, ssg, "/")                 # B x K profile RSS
  kbest <- max.col(-rss, ties.method = "first")
  lg <- log(grid)
  rss_at <- function(b, e) {
    g <- as.vector(center_rows(C / (e + C)))
    cr <- sum(Yc_rows[b, ] * g); ssy[b] - cr^2 / sum(g^2)
  }
  ec50 <- grid[kbest]; boundary <- kbest == 1L | kbest == K
  for (b in which(!boundary)) {
    k <- kbest[b]
    y3 <- rss[b, (k - 1):(k + 1)]; x3 <- lg[(k - 1):(k + 1)]
    den <- (x3[1] - x3[2]) * (x3[1] - x3[3]) * (x3[2] - x3[3])
    A <- (x3[3] * (y3[2] - y3[1]) + x3[2] * (y3[1] - y3[3]) + x3[1] * (y3[3] - y3[2])) / den
    Bq <- (x3[3]^2 * (y3[1] - y3[2]) + x3[2]^2 * (y3[3] - y3[1]) + x3[1]^2 * (y3[2] - y3[3])) / den
    if (A > 0) {
      xv <- -Bq / (2 * A)
      if (xv > x3[1] && xv < x3[3] && rss_at(b, exp(xv)) < rss[b, k]) ec50[b] <- exp(xv)
    }
  }
  emax <- vapply(seq_len(nrow(Yc_rows)), function(b) {
    g <- as.vector(center_rows(C / (ec50[b] + C)))
    sum(Yc_rows[b, ] * g) / sum(g^2)
  }, numeric(1))
  list(ec50 = ec50, emax = emax, boundary = boundary)
}

fit_emax <- function(C, Y) {
  pr <- emax_profile_rows(C, matrix(as.vector(center_rows(Y)), 1L))
  g <- C / (pr$ec50 + C)
  icpt <- rowMeans(Y) - pr$emax * rowMeans(g)            # E0 + b_i
  fitted <- icpt + pr$emax * g
  rss <- sum((Y - fitted)^2)
  N <- length(Y); n <- nrow(Y)
  list(form = "emax", theta = c(E0 = mean(icpt), Emax = pr$emax, EC50 = pr$ec50),
       b = icpt - mean(icpt), fitted = fitted, rss = rss,
       sigma = sqrt(rss / (N - n - 2)),
       aic = N * log(rss / N) + 2 * (n + 2 + 1), boundary = pr$boundary)
}

## Linearity check before the C-QTc model, following the CiPA Phase 1 SAP
## (NCT03070470, section 5.2.1): add a quadratic term in concentration and test it
## two-sided at 5%; if it is significant, fit Emax and keep it when its AIC is lower.
linearity_check <- function(C, Y, alpha = 0.05) {
  Cc <- as.vector(center_rows(C)); Q <- as.vector(center_rows(C^2)); Yc <- as.vector(center_rows(Y))
  X <- cbind(Cc, Q)
  XtX <- crossprod(X); beta <- solve(XtX, crossprod(X, Yc))
  rss <- sum((Yc - X %*% beta)^2)
  df <- length(Y) - nrow(Y) - 2
  se <- sqrt(rss / df * diag(solve(XtX)))
  p_quad <- 2 * pt(-abs(beta[2] / se[2]), df)
  lin <- fit_linear(C, Y)
  if (p_quad >= alpha) return(list(selected = lin, p_quad = p_quad))
  emx <- fit_emax(C, Y)
  list(selected = if (emx$aic < lin$aic) emx else lin, p_quad = p_quad)
}

fit_direct <- function(C, Y, form = c("linear", "emax", "select")) {
  form <- match.arg(form)
  switch(form, linear = fit_linear(C, Y), emax = fit_emax(C, Y),
         select = linearity_check(C, Y)$selected)
}

## Random-intercept fit with nlme, for comparison with the within estimator
## (used in tests/test_area.R and in the TLF shells' prespecified model).
fit_direct_nlme <- function(C, Y, form = c("linear", "emax")) {
  form <- match.arg(form)
  d <- data.frame(id = factor(rep(seq_len(nrow(Y)), times = ncol(Y))),
                  conc = as.vector(C), y = as.vector(Y))
  if (form == "linear") {
    m <- nlme::lme(y ~ conc, random = ~ 1 | id, data = d, method = "REML")
    return(c(theta0 = unname(nlme::fixef(m)[1]), theta1 = unname(nlme::fixef(m)[2])))
  }
  st <- fit_emax(C, Y)$theta
  m <- nlme::nlme(y ~ e0 + emax * conc / (ec50 + conc), data = d,
                  fixed = e0 + emax + ec50 ~ 1, random = e0 ~ 1 | id,
                  start = c(e0 = unname(st["E0"]), emax = unname(st["Emax"]), ec50 = unname(st["EC50"])))
  f <- nlme::fixef(m)
  c(E0 = unname(f["e0"]), Emax = unname(f["emax"]), EC50 = unname(f["ec50"]))
}

## shape term of f evaluated at C (participant-level constants removed)
f_shape <- function(fit, C) {
  if (fit$form == "linear") fit$theta[["theta1"]] * C
  else fit$theta[["Emax"]] * C / (fit$theta[["EC50"]] + C)
}

## residual areas: A_i on r_ij = y_ij - f-hat(C_ij) - b-hat_i
resid_areas <- function(C, Y, fit, X = scale_conc(C)) {
  loop_areas(X, Y - fit$fitted)
}

## ---- tests --------------------------------------------------------------------
## Participant-level sign-flip test of mean(A). Exact enumeration of all 2^n sign
## vectors when n <= exact_max; otherwise B random sign vectors with
## p = (1 + #{T* >= T}) / (B + 1). One-sided (counterclockwise) and two-sided (|T|).
signflip_test <- function(A, B = 9999L, exact_max = 20L) {
  n <- length(A); Tobs <- mean(A)
  tol <- 1e-10 * (sum(abs(A)) / n + .Machine$double.xmin)
  if (n <= exact_max) {
    s <- 0
    for (a in A) s <- c(s + a, s - a)                      # all 2^n signed sums
    Ts <- s / n
    return(list(stat = Tobs, p_one = mean(Ts >= Tobs - tol),
                p_two = mean(abs(Ts) >= abs(Tobs) - tol),
                method = "exact", nvec = length(Ts)))
  }
  S <- matrix(sample(c(-1, 1), B * n, replace = TRUE), B, n)
  Ts <- drop(S %*% A) / n
  list(stat = Tobs, p_one = (1 + sum(Ts >= Tobs - tol)) / (B + 1),
       p_two = (1 + sum(abs(Ts) >= abs(Tobs) - tol)) / (B + 1),
       method = "monte carlo", nvec = B)
}

## Secondary test: parametric bootstrap from the fitted direct-effect model
## (no delay by construction). y* = f-hat(C) + b-hat_i + e*, e* ~ N(0, sigma-hat^2);
## f is refitted to each y* and its residual mean area is the null draw.
param_boot_test <- function(C, Y, fit, B = 999L, X = scale_conc(C)) {
  n <- nrow(Y); m <- ncol(Y)
  Tobs <- mean(resid_areas(C, Y, fit, X))
  E <- matrix(rnorm(B * n * m, 0, fit$sigma), B, n * m)   # each row = one e* (as.vector)
  j <- c(seq_len(m)[-1], 1L)
  area_rows <- function(R) {                              # B x N -> B x n areas
    out <- matrix(0, nrow(R), n)
    for (k in seq_len(m)) {
      rk <- R[, (k - 1) * n + seq_len(n), drop = FALSE]
      rj <- R[, (j[k] - 1) * n + seq_len(n), drop = FALSE]
      out <- out + sweep(rj, 2, X[, k], "*") - sweep(rk, 2, X[, j[k]], "*")
    }
    0.5 * out
  }
  if (fit$form == "linear") {
    ## exact shortcut: f-hat and b-hat_i are participant-level linear functions of C,
    ## whose closed-path area is zero, so the refitted residual area is the area of e*
    Ts <- rowMeans(area_rows(E))
  } else {
    fit_shape <- as.vector(f_shape(fit, C))
    Ystar <- sweep(E, 2, fit_shape, "+")                  # constants b_i omitted: zero area
    Yc <- Ystar
    for (i in seq_len(n)) {                               # participant-center each row
      idx <- i + n * (seq_len(m) - 1L)
      Yc[, idx] <- Yc[, idx] - rowMeans(Yc[, idx, drop = FALSE])
    }
    pr <- emax_profile_rows(C, Yc)
    A_raw <- area_rows(Ystar)
    Ts <- vapply(seq_len(B), function(b) {
      gb <- C / (pr$ec50[b] + C)
      mean(A_raw[b, ] - pr$emax[b] * loop_areas(X, gb))
    }, numeric(1))
  }
  list(stat = Tobs, p_one = (1 + sum(Ts >= Tobs)) / (B + 1),
       p_two = (1 + sum(abs(Ts) >= abs(Tobs))) / (B + 1), B = B)
}

## tmax gap, reported beside the test. Two conventions:
##   individual   = median over participants of the time of peak ddQTcF minus
##                  median tmax (the rule as worded in the build spec)
##   mean_profile = time of the peak of the mean ddQTcF profile minus median tmax
##                  (the convention in the registry SAPs cited on the page)
tmax_gap <- function(times, C, Y) {
  tmax <- median(times[max.col(C, ties.method = "first")])
  c(individual = median(times[max.col(Y, ties.method = "first")]) - tmax,
    mean_profile = times[which.max(colMeans(Y))] - tmax)
}

## ---- the check as an SAP would run it ---------------------------------------------
## form: "linear", "emax", or "select" (linearity check chooses). D1 (optional) is the
## Day -1 time-matched QTcF, centered within participant, paired with Day 1 x.
hysteresis_check <- function(times, C, Y, form = "linear", B = 9999L, boot_B = 999L,
                             D1 = NULL, exact_max = 20L) {
  X <- scale_conc(C)
  fit <- fit_direct(C, Y, form)
  A <- resid_areas(C, Y, fit, X)
  n <- length(A)
  sf <- signflip_test(A, B, exact_max)
  half <- qt(0.975, n - 1) * sd(A) / sqrt(n)
  out <- list(n = n, model = fit$form, theta = fit$theta, A = A,
              Abar = mean(A), ci95 = mean(A) + c(-1, 1) * half,
              p_one = sf$p_one, p_two = sf$p_two, test = sf$method, nvec = sf$nvec,
              tmax_gap = tmax_gap(times, C, Y))
  if (boot_B > 0) out$boot <- param_boot_test(C, Y, fit, boot_B, X)
  if (!is.null(D1)) {
    A1 <- loop_areas(X, D1)
    s1 <- signflip_test(A1, B, exact_max)
    out$day_m1 <- list(Abar = mean(A1), p_one = s1$p_one, p_two = s1$p_two)
  }
  out
}
