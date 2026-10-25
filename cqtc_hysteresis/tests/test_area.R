################################################################################
# cqtc_hysteresis/tests/test_area.R
# Tests for the signed loop area, the sign-flip test, the direct-effect fits and
# the TLF shells' gates. Base R (+ nlme, which ships with R). Synthetic data only.
# Run from the repository root:  Rscript cqtc_hysteresis/tests/test_area.R
# Exits non-zero if any check fails. About 1 minute.
################################################################################

args <- commandArgs(trailingOnly = FALSE)
here <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", args, value = TRUE)[1])))
MOD  <- normalizePath(file.path(here, ".."))
REPO <- normalizePath(file.path(MOD, ".."))
source(file.path(MOD, "R", "sim.R")); source(file.path(MOD, "R", "area.R"))
RNGkind("Mersenne-Twister", "Inversion", "Rejection")

results <- character(0); failed <- 0L
check <- function(name, ok, detail = "") {
  ok <- isTRUE(ok)
  results[length(results) + 1L] <<- sprintf("%s  %s%s", if (ok) "PASS" else "FAIL", name,
                                             if (nzchar(detail)) paste0("  (", detail, ")") else "")
  if (!ok) failed <<- failed + 1L
}

## ---- geometry -------------------------------------------------------------------
check("counterclockwise unit square has area +1",
      identical(loop_area(c(0, 1, 1, 0), c(0, 0, 1, 1)), 1))
check("clockwise unit square has area -1",
      identical(loop_area(c(0, 0, 1, 1), c(0, 1, 1, 0)), -1))
set.seed(1)
xi <- sample(0:9, 12, TRUE); yi <- sample(-5:5, 12, TRUE)
check("reversing time flips the sign exactly (integer path)",
      identical(loop_area(rev(xi), rev(yi)), -loop_area(xi, yi)))
x <- runif(12); y <- rnorm(12)
a <- loop_area(x, y); ar <- loop_area(rev(x), rev(y))
check("reversing time flips the sign (random doubles, 1e-14)", abs(a + ar) < 1e-14,
      sprintf("A = %.6f, reversed = %.6f", a, ar))
X <- matrix(runif(60), 5); Y <- matrix(rnorm(60), 5)
check("row-wise areas match the single-path area",
      max(abs(loop_areas(X, Y) - vapply(1:5, function(i) loop_area(X[i, ], Y[i, ]), 0))) < 1e-14)
lin0 <- vapply(1:200, function(k) { x <- runif(12); loop_area(x, rnorm(1, 0, 50) + rnorm(1, 0, 50) * x) }, 0)
check("area(x, a + b x) = 0 to 1e-12 (200 random lines)", max(abs(lin0)) < 1e-12,
      sprintf("max |A| = %.1e", max(abs(lin0))))
## the antisymmetric part of the lag-1 cross-moment Gamma = sum_j z_j z_{j+1}^T is the area
z <- cbind(x, y); zl <- z[c(2:12, 1), ]
Gam <- crossprod(z, zl)
check("antisymmetric part of the lag-1 cross-moment equals the area",
      abs(0.5 * (Gam[1, 2] - Gam[2, 1]) - a) < 1e-14)

## ---- sign-flip test ---------------------------------------------------------------
A6 <- c(2.1, 1.4, 3.3, 0.7, 2.2, 1.9)
s6 <- signflip_test(A6)
check("exact test at n = 6 enumerates 64 sign vectors; smallest one-sided p = 1/64",
      s6$method == "exact" && s6$nvec == 64 && abs(s6$p_one - 1 / 64) < 1e-15,
      sprintf("p = %.4f", s6$p_one))
check("exact two-sided p at n = 6 with all areas positive = 2/64", abs(s6$p_two - 2 / 64) < 1e-15)
set.seed(20261025)
gaps <- vapply(1:25, function(k) {
  A <- rnorm(10, 0.6, 2)
  pe <- signflip_test(A)$p_one
  pm <- signflip_test(A, B = 9999L, exact_max = 0L)$p_one
  abs(pm - pe) / sqrt(pe * (1 - pe) / 10000 + 1e-12)
}, 0)
check("exact enumeration matches Monte Carlo (B = 9,999) within 3 MCSE at n = 10 (25 datasets)",
      max(gaps) <= 3, sprintf("largest gap %.2f MCSE; %d of 25 within 1 MCSE", max(gaps), sum(gaps <= 1)))

## ---- the model matters --------------------------------------------------------------
set.seed(7)
d <- sim_trial(32, model = "linear", ke0 = 0.7)
fl <- fit_linear(d$C, d$Y); Xs <- scale_conc(d$C)
check("residual area equals raw area under a linear f (1e-10)",
      max(abs(resid_areas(d$C, d$Y, fl, Xs) - loop_areas(Xs, d$Y))) < 1e-10)
check("participant intercepts do not change the area",
      max(abs(loop_areas(Xs, d$Y + rnorm(32, 0, 20)) - loop_areas(Xs, d$Y))) < 1e-10)
pf <- typical_profile(DEFAULT_TIMES, "emax"); pd <- typical_profile(seq(0, 24, by = 0.01), "emax")
check("noise-free Emax direct effect: raw area is positive on the 12-point grid and near 0 on a dense grid",
      loop_area(pf$C / max(pf$C), pf$E) > 1 && abs(loop_area(pd$C / max(pd$C), pd$E)) < 0.05,
      sprintf("12-point %.3f ms, dense %.4f ms", loop_area(pf$C / max(pf$C), pf$E), loop_area(pd$C / max(pd$C), pd$E)))
## Emax profile fit recovers the truth on noise-free data
set.seed(3)
dn <- sim_trial(32, model = "emax", sd = 1e-6)
fe <- fit_emax(dn$C, dn$Y)
check("Emax profile fit recovers Emax = 20, EC50 = 0.4 on noise-free data",
      abs(fe$theta[["Emax"]] - 20) < 0.05 && abs(fe$theta[["EC50"]] - 0.4) < 0.002,
      sprintf("Emax %.3f, EC50 %.4f", fe$theta[["Emax"]], fe$theta[["EC50"]]))
## within estimator vs nlme random-intercept fit
set.seed(11)
de <- sim_trial(32, model = "emax")
fw <- fit_emax(de$C, de$Y); fr <- fit_direct_nlme(de$C, de$Y, "emax")
Xe <- scale_conc(de$C)
fr_fit <- list(form = "emax", theta = fr, fitted = fr[["E0"]] + fr[["Emax"]] * de$C / (fr[["EC50"]] + de$C))
dA <- abs(mean(resid_areas(de$C, de$Y, fw, Xe)) - mean(loop_areas(Xe, de$Y - fr_fit$fitted)))
check("within (fixed-intercept) and nlme random-intercept Emax fits give mean residual areas within 0.1 ms",
      dA < 0.1, sprintf("difference %.3f ms; EC50 %.3f vs %.3f", dA, fw$theta[["EC50"]], fr[["EC50"]]))
## parametric bootstrap: the linear shortcut equals an explicit refit
set.seed(5)
db <- sim_trial(12, model = "linear"); fb <- fit_linear(db$C, db$Y); Xb <- scale_conc(db$C)
set.seed(99); pb <- param_boot_test(db$C, db$Y, fb, B = 50L, X = Xb)
set.seed(99); E <- matrix(rnorm(50 * length(db$Y), 0, fb$sigma), 50)
brute <- vapply(1:50, function(b) {
  ys <- fb$fitted + matrix(E[b, ], nrow(db$Y)); f2 <- fit_linear(db$C, ys)
  mean(resid_areas(db$C, ys, f2, Xb)) }, 0)
check("parametric bootstrap: linear shortcut equals refitting each draw",
      pb$p_one == (1 + sum(brute >= pb$stat)) / 51)

## ---- known answers at 300 replicates -------------------------------------------------
oc <- function(model, R = 300L, B = 1999L) {
  rej <- matrix(NA, R, 2)
  for (r in seq_len(R)) {
    s <- sim_trial(32, model = model); Xr <- scale_conc(s$C)
    rej[r, 1] <- signflip_test(loop_areas(Xr, s$Y), B)$p_one <= 0.05
    if (model == "emax") rej[r, 2] <- signflip_test(resid_areas(s$C, s$Y, fit_emax(s$C, s$Y), Xr), B)$p_one <= 0.05
  }
  colMeans(rej)
}
mc300 <- sqrt(0.05 * 0.95 / 300)
set.seed(20261025 + 101); k1 <- oc("linear")
check("KA1: linear direct effect, size within 0.05 +/- 3 MCSE (300 replicates)",
      abs(k1[1] - 0.05) <= 3 * mc300, sprintf("rate %.3f, 3 MCSE = %.3f", k1[1], 3 * mc300))
set.seed(20261025 + 102); k2 <- oc("emax")
check("KA2: Emax direct effect, raw area inflated (> 0.5) (300 replicates)", k2[1] > 0.5,
      sprintf("raw %.3f", k2[1]))
check("KA2: Emax-residual area at most 0.05 + 3 MCSE (300 replicates)", k2[2] <= 0.05 + 3 * mc300,
      sprintf("residual %.3f", k2[2]))

## ---- gates on the TLF shells (G1 parse, G4 parity, G7 scan) ------------------------------
rfiles <- list.files(REPO, pattern = "[.]R$", recursive = TRUE, full.names = TRUE)
rfiles <- rfiles[!grepl("/(node_modules|[.]git|renv/library)/", rfiles)]
bad <- rfiles[vapply(rfiles, function(f) inherits(try(parse(f), silent = TRUE), "try-error"), logical(1))]
check("G1: every R program in the repository parses", length(bad) == 0,
      sprintf("%d files, %d fail", length(rfiles), length(bad)))
tlfnum <- function(f) {
  t <- paste(readLines(f, warn = FALSE), collapse = "\n")
  m <- regmatches(t, regexpr('num\\s*=\\s*"?[0-9]+(\\.[0-9]+)+', t))
  if (length(m)) sub('^num\\s*=\\s*"?', "", m) else NA_character_
}
shells <- c("f_cqtc_hysteresis", "t_cqtc_hysteresis")
for (des in c("sad", "mad")) {
  for (st in shells) {
    rf <- file.path(REPO, "r_tlf_pseudocode", des, paste0(st, ".R"))
    sf <- file.path(REPO, "sas_tlf_pseudocode", des, paste0(st, ".sas"))
    check(sprintf("G4: %s/%s has an R program and a SAS twin with the same TLF number", des, st),
          file.exists(rf) && file.exists(sf) && identical(tlfnum(rf), tlfnum(sf)) && !is.na(tlfnum(rf)),
          if (file.exists(rf) && file.exists(sf)) sprintf("R %s, SAS %s", tlfnum(rf), tlfnum(sf)) else "missing")
  }
  for (lang in c("r_tlf_pseudocode", "sas_tlf_pseudocode")) {
    fs <- list.files(file.path(REPO, lang, des), pattern = "[.](R|sas)$", full.names = TRUE)
    nums <- vapply(fs, tlfnum, "")
    check(sprintf("G4: no TLF number repeats in %s/%s", lang, des), !anyDuplicated(nums[!is.na(nums)]))
  }
}
g7 <- "experimental (engine|method|analytic)|research-grade (engine|model)|non-standard (analytic )?method|unvalidated (engine|model)"
scan <- c(list.files(file.path(REPO, c("sas_tlf_pseudocode", "r_tlf_pseudocode", "sim_lifecycle")),
                     recursive = TRUE, full.names = TRUE),
          list.files(MOD, recursive = TRUE, full.names = TRUE))
scan <- scan[!grepl("tests/test_area[.]R$", scan)]   # this file names the phrases to scan for
hits <- unlist(lapply(scan, function(f) grep(g7, readLines(f, warn = FALSE), ignore.case = TRUE, value = TRUE)))
check("G7: no experimental/non-standard method labels in the TLF libraries, sim_lifecycle or this module",
      length(hits) == 0, sprintf("%d hits", length(hits)))
new_shells <- unlist(lapply(c("sad", "mad"), function(des) c(
  file.path(REPO, "r_tlf_pseudocode", des, paste0(shells, ".R")),
  file.path(REPO, "sas_tlf_pseudocode", des, paste0(shells, ".sas")))))
new_shells <- new_shells[file.exists(new_shells)]
subj <- unlist(lapply(new_shells, function(f) {
  l <- readLines(f, warn = FALSE); l[grepl("\\bsubjects?\\b", l, ignore.case = TRUE) & !grepl("subjid", l, ignore.case = TRUE)] }))
scope <- unlist(lapply(new_shells, function(f) grep("\\bedish\\b|hy'?s.?law", readLines(f, warn = FALSE), ignore.case = TRUE, value = TRUE)))
check("G3/G6: the new shells use 'participant' and stay out of eDISH/Hy's Law scope",
      length(subj) == 0 && length(scope) == 0, sprintf("%d term hits, %d scope hits", length(subj), length(scope)))

cat(results, sep = "\n")
cat(sprintf("\n%d of %d checks passed\n", length(results) - failed, length(results)))
if (failed > 0) quit(status = 1)
