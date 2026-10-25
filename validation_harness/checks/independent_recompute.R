#!/usr/bin/env Rscript
###############################################################################
# G9 Independent recomputation (Trial-Management Validation Harness)
#
# Recomputes the sandbox's NCA parameters, bioequivalence result, geometric means and AE
# participant counts from the analysis data and compares them with ADPP and
# out/results_summary.csv (the driver's printed results) at relative tolerance 1e-6.
# The code here is written separately from the sandbox: it never sources
# sim_lifecycle/simulate_adam.R or run_lifecycle.R. The same author wrote both, so this is a
# same-author re-derivation, not double programming by a second person.
#
#   AUC(0-t)  linear trapezoid from t = 0 (the predose zero kept) to the last quantifiable
#             concentration, BLQ as 0 (ICH M13A)
#   Cmax, Tmax; lambda_z by log-linear least squares on the last three positive points;
#   AUC(0-inf) = AUC(0-t) + Clast / lambda_z; t1/2 = ln 2 / lambda_z; CL/F = dose / AUC(0-inf);
#   Vz/F = (CL/F) / lambda_z
#   BE (participants with both periods): d_i = log Y(period 1) - log Y(period 2);
#             log GMR = (mean d_TR - mean d_RT) / 2; SE = 0.5 s_p sqrt(1/n_TR + 1/n_RT), with
#             s_p the pooled within-sequence SD of d and df = n - 2; 90% CI = exp(est +/- t SE).
#             For complete 2x2 data this equals the participant + period + formulation OLS
#             model, asserted below against lm().
#   Geometric mean = exp(mean(log x)); geometric CV% = 100 sqrt(exp(s^2_log) - 1)
#   AE counts = distinct USUBJID among treatment-emergent AEs in the safety population
#
# Optional third engine: PKNCA (tested with 0.12.1), with
# conc.blq = list(first = "keep", middle = "keep", last = "keep") and auc.method = "linear",
# and the half-life fit given the same last three positive points; skipped when not installed.
#
# Prints one "CHECK <name>: PASS|FAIL|SKIPPED (detail)" line per check, then G9_* summary
# lines and a verdict. 100% synthetic data; no PHI.
# Usage: Rscript validation_harness/checks/independent_recompute.R [out_dir] [--no-pknca]
###############################################################################
args <- commandArgs(trailingOnly = TRUE)
use_pknca <- !("--no-pknca" %in% args)
args <- args[!grepl("^--", args)]
out <- if (length(args) >= 1) args[1] else "sim_lifecycle/out"
TOL <- 1e-6
pass <- TRUE
maxrel <- 0
chk <- function(name, ok, detail = "", skipped = FALSE) {
  cat(sprintf("CHECK %-44s %s%s\n", name, if (skipped) "SKIPPED" else if (isTRUE(ok)) "PASS" else "FAIL",
              if (nzchar(detail)) paste0("  (", detail, ")") else ""))
  if (!skipped && !isTRUE(ok)) pass <<- FALSE
}
# relative difference to the reported value b; equal values (both NA, or both the same Inf) are 0,
# anything else that cannot be compared (NA on one side, Inf, NaN) is Inf
rel <- function(a, b) {
  d <- suppressWarnings(abs(a - b) / ifelse(!is.na(b) & b == 0, 1, abs(b)))
  same <- (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
  d[is.na(d)] <- Inf
  d[same] <- 0
  d
}
rd <- function(f) {
  p <- file.path(out, f)
  if (!file.exists(p)) return(NULL)
  read.csv(p, stringsAsFactors = FALSE, check.names = FALSE)
}
adpc <- rd("adpc.csv"); adpp <- rd("adpp.csv"); adex <- rd("adex.csv"); adsl <- rd("adsl.csv")
adae <- rd("adae.csv"); summ <- rd("results_summary.csv")
missing <- c("adpc.csv", "adpp.csv", "adex.csv", "adsl.csv", "adae.csv", "results_summary.csv")[
  vapply(list(adpc, adpp, adex, adsl, adae, summ), is.null, logical(1))]
if (length(missing)) {
  chk("input files present", FALSE, paste("missing:", paste(missing, collapse = ", ")))
  cat("G9_PROFILES 0\nG9_MAXREL NA\nG9_ENGINES none\nG9_VERDICT FAIL\n"); quit(status = 1)
}

# ---- 1. NCA from ADPC ---------------------------------------------------------
nca <- function(t, conc, dose) {
  o <- order(t); t <- t[o]; conc <- conc[o]
  conc[is.na(conc)] <- 0                               # BLQ as 0; the predose zero stays in
  if (!any(t == 0)) { t <- c(0, t); conc <- c(0, conc) }
  pos <- which(conc > 0)
  if (length(pos) < 3) return(NULL)                    # too few quantifiable points
  last <- max(pos); tt <- t[seq_len(last)]; cc <- conc[seq_len(last)]
  auclast <- sum((tt[-1] - tt[-last]) * (cc[-1] + cc[-last]) / 2)
  cmax <- max(conc); tmax <- t[which(conc == cmax)[1]]
  k <- tail(pos, 3); x <- t[k]; y <- log(conc[k])
  lz <- -sum((x - mean(x)) * (y - mean(y))) / sum((x - mean(x))^2)
  if (!is.finite(lz) || lz <= 0) lz <- NA_real_
  aucinf <- auclast + conc[last] / lz
  clf <- dose / aucinf
  c(CMAX = cmax, TMAX = tmax, AUCLST = auclast, AUCIFO = aucinf, T12 = log(2) / lz,
    CLFO = clf, VZFO = clf / lz, LZ = lz)
}
key <- unique(adpc[, c("USUBJID", "APERIOD", "TRTA")])
key <- key[order(key$USUBJID, key$APERIOD), ]
rec <- list()
for (i in seq_len(nrow(key))) {
  s <- adpc[adpc$USUBJID == key$USUBJID[i] & adpc$APERIOD == key$APERIOD[i], ]
  dz <- adex$AVAL[adex$USUBJID == key$USUBJID[i] & adex$APERIOD == key$APERIOD[i]]
  dose <- if (length(dz) && !is.na(dz[1]) && dz[1] > 0) dz[1] else NA_real_
  v <- nca(s$ATPTN, s$AVAL, dose)
  if (is.null(v)) next
  rec[[length(rec) + 1]] <- data.frame(USUBJID = key$USUBJID[i], APERIOD = key$APERIOD[i],
    TRTA = key$TRTA[i], PARAMCD = names(v), VALUE = unname(v), stringsAsFactors = FALSE)
}
rec <- do.call(rbind, rec)
params <- c("CMAX", "TMAX", "AUCLST", "AUCIFO", "T12", "CLFO", "VZFO")
rk <- function(d) paste(d$USUBJID, d$APERIOD, d$PARAMCD)
r7 <- rec[rec$PARAMCD %in% params, ]
pp <- adpp[adpp$PARAMCD %in% params, ]
extra <- setdiff(unique(adpp$PARAMCD), params)
m <- match(rk(r7), rk(pp))
prof_rec <- unique(paste(rec$USUBJID, rec$APERIOD)); prof_pp <- unique(paste(adpp$USUBJID, adpp$APERIOD))
d_pp <- rel(r7$VALUE, pp$AVAL[m])
n_prof <- length(intersect(prof_rec, prof_pp))
ok <- !anyNA(m) && nrow(pp) == nrow(r7) && !length(extra) && setequal(prof_rec, prof_pp) && all(d_pp <= TOL)
mx <- if (length(d_pp)) max(d_pp) else Inf
maxrel <- max(maxrel, mx)
chk("NCA parameters vs ADPP", ok, sprintf(
  "%d of %d profiles; %d values; max rel diff %.2g%s%s", n_prof, length(prof_pp), nrow(r7), mx,
  if (anyNA(m) || nrow(pp) != nrow(r7)) sprintf("; %d recomputed values have no ADPP match, ADPP has %d", sum(is.na(m)), nrow(pp)) else "",
  if (length(extra)) paste("; unexpected PARAMCD:", paste(extra, collapse = ",")) else ""))

# ---- 2. bioequivalence, closed form, and the lm() identity ---------------------
be_closed <- function(p) {
  x <- rec[rec$PARAMCD == p, ]
  w1 <- x[x$APERIOD == 1, ]; w2 <- x[x$APERIOD == 2, ]
  ids <- intersect(w1$USUBJID[w1$VALUE > 0], w2$USUBJID[w2$VALUE > 0])
  w1 <- w1[match(ids, w1$USUBJID), ]; w2 <- w2[match(ids, w2$USUBJID), ]
  sq <- paste0(substr(w1$TRTA, 1, 1), substr(w2$TRTA, 1, 1))   # TR or RT, from the data
  d <- log(w1$VALUE) - log(w2$VALUE)
  tr <- d[sq == "TR"]; rt <- d[sq == "RT"]; n <- length(tr) + length(rt)
  est <- (mean(tr) - mean(rt)) / 2
  sp2 <- ((length(tr) - 1) * var(tr) + (length(rt) - 1) * var(rt)) / (n - 2)
  se <- 0.5 * sqrt(sp2) * sqrt(1 / length(tr) + 1 / length(rt))
  tc <- qt(0.95, n - 2)
  long <- rbind(data.frame(USUBJID = ids, APERIOD = 1, TRT = w1$TRTA, Y = w1$VALUE),
                data.frame(USUBJID = ids, APERIOD = 2, TRT = w2$TRTA, Y = w2$VALUE))
  long$TRT <- relevel(factor(long$TRT), ref = "Reference")
  fit <- lm(log(Y) ~ factor(USUBJID) + factor(APERIOD) + TRT, data = long)
  co <- summary(fit)$coefficients["TRTTest", ]
  list(n = n, other = sum(!sq %in% c("TR", "RT")),
       values = c(GMR_PCT = 100 * exp(est), LCL90_PCT = 100 * exp(est - tc * se),
                  UCL90_PCT = 100 * exp(est + tc * se), INTRA_CV_PCT = 100 * sqrt(exp(sp2 / 2) - 1)),
       lm_gap = max(rel(est, co[["Estimate"]]), rel(se, co[["Std. Error"]]),
                    rel(n - 2, fit$df.residual), rel(sp2 / 2, summary(fit)$sigma^2)))
}
BE <- lapply(c(CMAX = "CMAX", AUCLST = "AUCLST"), be_closed)
gap <- max(vapply(BE, function(b) b$lm_gap, numeric(1)))
chk("BE closed form equals lm() (2x2)", gap <= 1e-8 && all(vapply(BE, function(b) b$other == 0, logical(1))),
    sprintf("estimate, SE, df and residual variance agree to %.2g; %s participants with both periods",
            gap, paste(vapply(BE, function(b) b$n, numeric(1)), collapse = "/")))

# ---- 3. the driver's printed results -----------------------------------------
exp_rows <- list()
put <- function(section, paramcd, group, stat, value) exp_rows[[length(exp_rows) + 1]] <<-
  data.frame(SECTION = section, PARAMCD = paramcd, GROUP = group, STAT = stat, VALUE = as.numeric(value),
             stringsAsFactors = FALSE)
for (p in c("CMAX", "AUCLST", "AUCIFO")) {
  x <- rec[rec$PARAMCD == p & !is.na(rec$VALUE) & rec$VALUE > 0, ]
  for (trt in sort(unique(x$TRTA))) {
    v <- log(x$VALUE[x$TRTA == trt])
    put("PK_GEO", p, trt, "N", length(v)); put("PK_GEO", p, trt, "GEOMEAN", exp(mean(v)))
    put("PK_GEO", p, trt, "GEOCV_PCT", 100 * sqrt(exp(var(v)) - 1))
  }
}
for (p in names(BE)) for (s in names(BE[[p]]$values)) put("BE", p, "Test vs Reference", s, BE[[p]]$values[[s]])
saf <- adsl$USUBJID[adsl$SAFFL == "Y"]
te <- adae[adae$TRTEMFL == "Y" & adae$USUBJID %in% saf, ]
cnt <- function(f) length(unique(te$USUBJID[f]))
put("AE", "", "Safety population", "N", length(saf))
put("AE", "", "Any TEAE", "N_PARTICIPANTS", cnt(rep(TRUE, nrow(te))))
put("AE", "", "Related TEAE", "N_PARTICIPANTS", cnt(te$AREL == "RELATED"))
put("AE", "", "Severe TEAE", "N_PARTICIPANTS", cnt(te$AESEVN == 3))
put("AE", "", "SAE", "N_PARTICIPANTS", cnt(te$AESER == "Y"))
ex <- do.call(rbind, exp_rows)
summ$PARAMCD[is.na(summ$PARAMCD)] <- ""
sk <- function(d) paste(d$SECTION, d$PARAMCD, d$GROUP, d$STAT, sep = "|")
for (sec in c("PK_GEO", "BE", "AE")) {
  e <- ex[ex$SECTION == sec, ]; s <- summ[summ$SECTION == sec, ]
  mm <- match(sk(e), sk(s)); d <- rel(e$VALUE, s$VALUE[mm])
  mxs <- if (length(d)) max(d) else Inf
  okk <- nrow(e) > 0 && !anyNA(mm) && nrow(s) == nrow(e) && all(d <= TOL)
  maxrel <- max(maxrel, mxs)
  bad <- if (!okk) {
    b <- sk(e)[is.na(mm) | d > TOL]
    paste0("; differs or missing: ", paste(head(sub("^[^|]*[|]", "", b), 4), collapse = ", "),
           if (nrow(s) != nrow(e)) sprintf("; results_summary has %d rows, expected %d", nrow(s), nrow(e)) else "")
  } else ""
  lab <- c(PK_GEO = "geometric means and CV% vs results_summary", BE = "BE GMR, 90% CI, intra-CV vs results_summary",
           AE = "AE participant counts vs results_summary")[[sec]]
  chk(lab, okk, sprintf("%d values; max rel diff %.2g%s", nrow(e), mxs, bad))
}

# ---- 4. optional third engine: PKNCA -------------------------------------------
engines <- "base R closed form and lm()"
if (use_pknca && requireNamespace("PKNCA", quietly = TRUE)) {
  pv <- as.character(utils::packageVersion("PKNCA"))
  res <- tryCatch({
    d <- adpc; d$id <- paste(d$USUBJID, d$APERIOD); d$conc <- ifelse(is.na(d$AVAL), 0, d$AVAL)
    d <- d[order(d$id, d$ATPTN), ]
    d$hl <- FALSE
    for (i in unique(d$id)) { r <- which(d$id == i & d$conc > 0); d$hl[tail(r, 3)] <- TRUE }
    d <- d[d$id %in% paste(rec$USUBJID, rec$APERIOD), ]
    co <- PKNCA::PKNCAconc(d, conc ~ ATPTN | id, include_half.life = "hl")
    dz <- unique(d["id"]); dz$time <- 0
    dz$dose <- adex$AVAL[match(dz$id, paste(adex$USUBJID, adex$APERIOD))]
    do <- PKNCA::PKNCAdose(dz, dose ~ time | id)
    iv <- data.frame(start = 0, end = Inf, cmax = TRUE, tmax = TRUE, auclast = TRUE, aucinf.obs = TRUE,
                     half.life = TRUE)
    da <- PKNCA::PKNCAdata(co, do, intervals = iv, options = list(auc.method = "linear",
           conc.blq = list(first = "keep", middle = "keep", last = "keep")))
    r <- as.data.frame(PKNCA::pk.nca(da))
    map <- c(cmax = "CMAX", tmax = "TMAX", auclast = "AUCLST", aucinf.obs = "AUCIFO", half.life = "T12")
    r <- r[r$PPTESTCD %in% names(map), ]
    rkey <- paste(r$id, map[r$PPTESTCD])
    bkey <- paste(rec$USUBJID, rec$APERIOD, rec$PARAMCD)
    mm <- match(bkey[rec$PARAMCD %in% map], rkey)
    list(d = rel(r$PPORRES[mm], rec$VALUE[rec$PARAMCD %in% map]), n = length(mm))
  }, error = function(e) e)
  if (inherits(res, "error")) {
    chk(sprintf("PKNCA %s third engine", pv), TRUE, paste("not run:", conditionMessage(res)), skipped = TRUE)
  } else {
    mxp <- max(res$d)
    chk(sprintf("PKNCA %s third engine", pv), all(res$d <= TOL),
        sprintf("Cmax, Tmax, AUClast, AUCinf, t1/2 on %d values; max rel diff %.2g vs the base-R recompute", res$n, mxp))
    maxrel <- max(maxrel, mxp)
    engines <- paste0(engines, "; PKNCA ", pv)
  }
} else {
  chk("PKNCA third engine", TRUE, if (use_pknca) "PKNCA not installed" else "--no-pknca", skipped = TRUE)
  engines <- paste0(engines, "; PKNCA skipped (", if (use_pknca) "not installed" else "--no-pknca", ")")
}

cat(sprintf("\nG9_PROFILES %d\nG9_MAXREL %.2g\nG9_ENGINES %s\nG9_VERDICT %s\n", n_prof, maxrel, engines,
            if (pass) "PASS" else "FAIL"))
quit(status = if (pass) 0 else 1)
