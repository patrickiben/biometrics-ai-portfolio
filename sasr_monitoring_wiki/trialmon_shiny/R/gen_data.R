# ---------------------------------------------------------------------------
# gen_data.R - deterministic synthetic safety-monitoring portfolio for TRIALMON.
# Values are xULN multiples / ms, NOT real measurements. No PHI. The dashboard is
# a SCREENING lens: it flags positions for a human, it never reports a number and
# never adjudicates. Writes ../data/*.csv (participants, aes, cohorts).
# ---------------------------------------------------------------------------
gen_trialmon <- function(out_dir = "data", seed = 20260611L) {
  set.seed(seed)
  COH <- data.frame(
    cohort = c("C1","C2","C3","C4","C5"),
    dose_mg = c(10,30,60,120,200), planned_n = c(3,3,6,6,4),
    stringsAsFactors = FALSE)
  disp_choices <- c("Ongoing","Completed","Discontinued")

  rows <- list(); k <- 0
  for (ci in seq_len(nrow(COH))) {
    for (j in seq_len(COH$planned_n[ci])) {
      k <- k + 1
      id <- sprintf("CP101-%03d", k)
      rows[[k]] <- data.frame(
        id = id, cohort = COH$cohort[ci], dose_mg = COH$dose_mg[ci],
        disposition = sample(disp_choices, 1, prob = c(.6,.3,.1)),
        alt = round(runif(1, .7, 1.6), 1), ast = round(runif(1, .7, 1.4), 1),
        tbl = round(runif(1, .4, .9), 1),  alp = round(runif(1, .8, 1.2), 1),
        qt = round(runif(1, 405, 442)), dqt = round(runif(1, 2, 20)),
        qbase = round(runif(1, 400, 430)),
        hgb = round(runif(1, 12.8, 15.2), 1), neut = round(runif(1, 2.4, 5.5), 1),
        plt = round(runif(1, 190, 300)), creat = round(runif(1, .75, 1.05), 2),
        dltfl = "N", dlteval = "Y", note = "", stringsAsFactors = FALSE)
    }
  }
  P <- do.call(rbind, rows)
  set_p <- function(id, ...) { P[P$id == id, names(list(...))] <<- list(...) }

  # the signature illustrative positions (screening lenses)
  set_p("CP101-006", qt = 486, dqt = 33, qbase = 453,
        note = "QTcF 486 ms (>480) - AMBER tier (as-collected, pending ECG QC). Baseline 453 already watch-band.")
  set_p("CP101-009", alt = 4.2, ast = 3.6, tbl = 1.6, alp = 1.2,
        note = "ALT 4.2x but TBili 1.6x (<2x) -> NOT a Hy's-Law position (the AND-gate). GREEN every visit; the eDISH near-miss.")
  set_p("CP101-011", alt = 2.6, ast = 2.4, tbl = 1.7, alp = 1.3, qt = 474, dqt = 26,
        hgb = 11.1, neut = 1.9, creat = 1.28,
        note = "Every univariate value below its own action threshold, yet several organs drift together. No single rule fires; whether the coordinated sub-threshold drift warrants a human look is a clinical judgement, not an automated flag.")
  set_p("CP101-012", alt = 2.3, ast = 2.1, tbl = 1.4, qt = 468, dqt = 22,
        note = "Mild co-drift, every value sub-threshold (QTcF 468 = watch). GREEN/watch on every deterministic check.")
  set_p("CP101-014", alt = 5.6, ast = 4.9, tbl = 3.1, alp = 1.4, dltfl = "Y",
        disposition = "Discontinued",
        note = "Hy's-Law screening position (RED): ALT 5.6x AND TBili 3.1x. R-ratio ~4 = MIXED pattern. Also an adjudicated DLT. Medical monitor + SRC notified.")
  set_p("CP101-018", qt = 503, dqt = 41, qbase = 462,
        note = "QTcF 503 ms (>500) - RED tier at an on-treatment visit (as-collected, pending ECG QC). Baseline 462 already watch-band.")

  AE <- rbind(
    data.frame(id="CP101-014", soc="Investigations", pt="ALT increased", grade=3L, serious="Y", related="Related", teae="Y", onset=18L, resolution=NA_integer_),
    data.frame(id="CP101-014", soc="Investigations", pt="AST increased", grade=3L, serious="N", related="Related", teae="Y", onset=18L, resolution=NA_integer_),
    data.frame(id="CP101-014", soc="Hepatobiliary disorders", pt="Hyperbilirubinaemia", grade=3L, serious="Y", related="Related", teae="Y", onset=22L, resolution=NA_integer_),
    data.frame(id="CP101-009", soc="Investigations", pt="ALT increased", grade=2L, serious="N", related="Possible", teae="Y", onset=15L, resolution=34L),
    data.frame(id="CP101-018", soc="Investigations", pt="Electrocardiogram QT prolonged", grade=2L, serious="N", related="Possible", teae="Y", onset=22L, resolution=NA_integer_),
    data.frame(id="CP101-006", soc="Investigations", pt="Electrocardiogram QT prolonged", grade=1L, serious="N", related="Unlikely", teae="Y", onset=15L, resolution=40L),
    data.frame(id="CP101-011", soc="Blood/lymphatic disorders", pt="Anaemia", grade=1L, serious="N", related="Possible", teae="Y", onset=20L, resolution=NA_integer_),
    stringsAsFactors = FALSE)
  # a scatter of mild, expected background AEs
  bg <- c("Nausea","Headache","Fatigue","Dizziness","Diarrhoea")
  for (i in 1:9) {
    pid <- sprintf("CP101-%03d", sample(1:22, 1))
    AE <- rbind(AE, data.frame(id=pid, soc="General disorders", pt=sample(bg,1),
      grade=sample(1:2,1), serious="N", related=sample(c("Unlikely","Possible"),1),
      teae="Y", onset=sample(3:40,1), resolution=sample(c(NA,20:50),1), stringsAsFactors=FALSE))
  }

  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(P, file.path(out_dir, "participants.csv"), row.names = FALSE)
  utils::write.csv(AE, file.path(out_dir, "aes.csv"), row.names = FALSE)
  utils::write.csv(COH, file.path(out_dir, "cohorts.csv"), row.names = FALSE)
  invisible(P)
}

if (sys.nframe() == 0) gen_trialmon(out_dir = file.path(dirname(getwd()), "data"))
