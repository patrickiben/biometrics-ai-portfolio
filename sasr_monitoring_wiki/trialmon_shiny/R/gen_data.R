# ---------------------------------------------------------------------------
# gen_data.R: deterministic SYNTHETIC data for TRIALMON (no real participants, no PHI).
#
# Study CP-101 (synthetic): first-in-human multiple ascending dose, open label for
# illustration, once-daily oral dosing on Days 1 to 28 (the DLT window), follow-up to
# Day 43. Cohorts C1 to C4 (10, 30, 60, 120 mg) are dosed; C5 (200 mg) is planned.
# The data cut is the Safety Review Committee meeting after C4 finished its DLT window.
#
# Writes ADaM-shaped CSVs (base R only) into the app's data/ folder:
#   adsl.csv  one row per participant (cohort, dose, disposition, DLT status)
#   adlb.csv  chemistry and hematology by visit (AVAL, ANRLO, ANRHI, BASE)
#   adeg.csv  QTcF by visit and time point (AVAL, BASE, CHG)
#   adae.csv  adverse events (MedDRA PT and primary SOC, CTCAE grade as recorded)
#   cohorts.csv, study_kri.csv (operational study-level indicators), notes.csv (teaching notes)
#
# Run from the app folder:  Rscript R/gen_data.R
# ---------------------------------------------------------------------------

gen_trialmon <- function(out_dir = "data", seed = 20260611L) {
  set.seed(seed)
  rnd <- function(x, d) round(x, d)

  coh <- data.frame(
    COHORT  = c("C1", "C2", "C3", "C4", "C5"),
    DOSEMG  = c(10, 30, 60, 120, 200),
    STATUS  = c("Complete", "Complete", "Complete",
                "DLT window complete; follow-up ongoing", "Planned; not dosed"),
    DLTWIN  = 28L, stringsAsFactors = FALSE)

  # 18 dosed participants, in enrollment order within each cohort (3 + 3 + 6 + 6)
  ids <- sprintf("CP101-%03d", 1:18)
  ch  <- rep(c("C1", "C2", "C3", "C4"), c(3, 3, 6, 6))
  adsl <- data.frame(
    STUDYID = "CP-101", USUBJID = ids, COHORT = ch,
    DOSEMG = coh$DOSEMG[match(ch, coh$COHORT)],
    AGE = sample(22:55, 18, replace = TRUE), SEX = sample(c("F", "M"), 18, replace = TRUE),
    SAFFL = "Y", TRTSDY = 1L, TRTEDY = 28L,
    EOTSTT = "COMPLETED", DCTREAS = "", EOSSTT = "COMPLETED", LSTVISDY = 43L,
    DLTEVLFL = "Y", DLTFL = "N", DLTADJ = "Final", DLTDESC = "",
    stringsAsFactors = FALSE)
  # C4 expansion participants are past Day 29 but not yet at the Day 43 follow-up visit
  adsl$EOSSTT[adsl$USUBJID %in% sprintf("CP101-%03d", 16:18)] <- "ONGOING"
  adsl$LSTVISDY[adsl$USUBJID %in% sprintf("CP101-%03d", 16:18)] <- 29L
  set_sl <- function(id, ...) { v <- list(...); for (k in names(v)) adsl[adsl$USUBJID == id, k] <<- v[[k]] }
  set_sl("CP101-008", DLTFL = "Y", DLTDESC = "Platelet count decreased, grade 3 (Day 15)")
  set_sl("CP101-014", DLTFL = "Y", DLTDESC = "Liver injury: potential Hy's Law (Day 22)",
         EOTSTT = "DISCONTINUED", DCTREAS = "ADVERSE EVENT", TRTEDY = 22L, EOSSTT = "ONGOING")
  set_sl("CP101-018", DLTFL = "", DLTADJ = "Pending",
         DLTDESC = "QTcF 503 ms on Day 22 (candidate DLT; adjudication pending)")

  # ---- laboratory data ------------------------------------------------------
  vis  <- c("Screening", "Day 1", "Day 4", "Day 8", "Day 15", "Day 22", "Day 29", "Day 43")
  vday <- c(-14L, 1L, 4L, 8L, 15L, 22L, 29L, 43L)
  ref <- data.frame(
    PARAMCD = c("ALT", "AST", "ALP", "BILI", "CREAT", "HGB", "NEUT", "PLAT"),
    PARAM   = c("Alanine aminotransferase (U/L)", "Aspartate aminotransferase (U/L)",
                "Alkaline phosphatase (U/L)", "Bilirubin, total (mg/dL)", "Creatinine (mg/dL)",
                "Hemoglobin (g/dL)", "Neutrophils (10^9/L)", "Platelets (10^9/L)"),
    AVALU   = c("U/L", "U/L", "U/L", "mg/dL", "mg/dL", "g/dL", "10^9/L", "10^9/L"),
    ANRLO   = c(7, 8, 40, 0.2, 0.6, 12.0, 1.8, 150),
    ANRHI   = c(40, 40, 120, 1.2, 1.2, 17.0, 7.5, 400),
    center  = c(22, 22, 75, 0.6, 0.85, 14.2, 3.8, 250),   # typical baseline
    sd      = c(.25, .2, .15, .25, .1, .05, .15, .12),    # between-participant (log scale)
    wsd     = c(.12, .1, .07, .12, .05, .025, .1, .07),   # within-participant (log scale)
    lo      = c(.3, .3, .5, .3, .55, .74, .9, .9),        # background bounds as x ULN (or x LLN
    hi      = c(1.6, 1.4, 1.1, .95, .95, 1.0, 1.0, 1.0),  #   for HGB, NEUT, PLAT: kept in range)
    dig     = c(0, 0, 0, 2, 2, 1, 2, 0), stringsAsFactors = FALSE)

  lb <- list(); k <- 0
  for (i in seq_along(ids)) {
    last <- adsl$LSTVISDY[i]
    for (j in seq_len(nrow(ref))) {
      r <- ref[j, ]
      low_bad <- r$PARAMCD %in% c("HGB", "NEUT", "PLAT")
      # baseline inside the normal range; later values kept in the background band
      blim <- c(r$ANRLO * 1.05, r$ANRHI * 0.95)
      b <- min(max(r$center * exp(rnorm(1, 0, r$sd)), blim[1]), blim[2])
      x <- b * exp(rnorm(length(vday), 0, r$wsd))
      lim <- if (low_bad) c(r$ANRLO * 1.02, r$ANRHI * 0.98) else c(r$ANRHI * r$lo, r$ANRHI * r$hi)
      x <- pmin(pmax(x, lim[1]), lim[2])
      x[2] <- b
      keep <- vday <= last
      k <- k + 1
      lb[[k]] <- data.frame(USUBJID = ids[i], PARAMCD = r$PARAMCD, AVISIT = vis[keep], ADY = vday[keep],
                            AVAL = rnd(x[keep], r$dig), stringsAsFactors = FALSE)
    }
  }
  adlb <- do.call(rbind, lb)

  # planted trajectories, given as multiples of ULN by visit (Screening, Day 1, 4, 8, 15, 22, 29, 43)
  uln <- setNames(ref$ANRHI, ref$PARAMCD); dig <- setNames(ref$dig, ref$PARAMCD)
  plant <- function(id, param, xuln = NULL, aval = NULL) {
    v <- if (!is.null(xuln)) xuln * uln[[param]] else aval
    rows <- which(adlb$USUBJID == id & adlb$PARAMCD == param & adlb$AVISIT != "Unscheduled")
    adlb$AVAL[rows] <<- rnd(v[seq_along(rows)], dig[[param]])
  }
  unsched <- function(id, day, vals) {   # an unscheduled repeat panel, values as x ULN
    for (p in names(vals)) adlb <<- rbind(adlb, data.frame(USUBJID = id, PARAMCD = p,
      AVISIT = "Unscheduled", ADY = as.integer(day), AVAL = rnd(vals[[p]] * uln[[p]], dig[[p]]),
      stringsAsFactors = FALSE))
  }
  # CP101-014 (C4): aminotransferase rise from Day 15, total bilirubin above 2x ULN on Day 22
  plant("CP101-014", "ALT",  c(.8, .8, 1.0, 1.9, 4.4, 5.6, 4.9, 2.0))
  plant("CP101-014", "AST",  c(.7, .7, .9, 1.6, 3.9, 4.9, 4.1, 1.6))
  plant("CP101-014", "BILI", c(.6, .6, .6, .7, 1.3, 3.1, 2.6, 1.2))
  plant("CP101-014", "ALP",  c(.8, .8, .8, .9, 1.1, 1.4, 1.3, 1.0))
  unsched("CP101-014", 17, list(ALT = 5.1, AST = 4.5, ALP = 1.2, BILI = 1.8))
  # CP101-009 (C3): ALT 4.2x, AST 3.6x ULN on Day 15 with total bilirubin 1.6x ULN; repeat on Day 20
  plant("CP101-009", "ALT",  c(.9, .9, 1.1, 2.0, 4.2, 2.9, 1.8, 1.1))
  plant("CP101-009", "AST",  c(.8, .8, 1.0, 1.7, 3.6, 2.4, 1.5, 1.0))
  plant("CP101-009", "BILI", c(.7, .7, .7, .9, 1.6, 1.2, .9, .8))
  plant("CP101-009", "ALP",  c(.9, .9, .9, 1.0, 1.2, 1.1, 1.0, .9))
  unsched("CP101-009", 20, list(ALT = 3.4, AST = 2.9, ALP = 1.1, BILI = 1.4))
  # CP101-004 (C2): isolated bilirubin rise on Day 4 BEFORE an ALT rise on Day 22 (timing case)
  plant("CP101-004", "ALT",  c(.8, .8, .9, 1.2, 1.9, 3.3, 1.7, 1.0))
  plant("CP101-004", "AST",  c(.7, .7, .8, 1.0, 1.5, 2.4, 1.3, .9))
  plant("CP101-004", "BILI", c(.8, .9, 2.4, 1.3, 1.1, 1.0, 1.0, .9))
  plant("CP101-004", "ALP",  c(.7, .7, .7, .8, .8, .8, .8, .7))
  unsched("CP101-004", 24, list(ALT = 2.6, AST = 1.9, ALP = .8, BILI = 1.0))
  # CP101-011 (C3): several analytes drift together, each below its own action threshold
  plant("CP101-011", "ALT",  c(.9, 1.0, 1.1, 1.5, 2.0, 2.6, 2.2, 1.4))
  plant("CP101-011", "AST",  c(.8, .9, 1.0, 1.4, 1.9, 2.4, 2.0, 1.3))
  plant("CP101-011", "BILI", c(.6, .6, .7, .9, 1.3, 1.7, 1.4, .9))
  plant("CP101-011", "ALP",  c(.9, .9, 1.0, 1.1, 1.2, 1.3, 1.2, 1.0))
  plant("CP101-011", "CREAT", aval = c(.78, .80, .84, .95, 1.10, 1.28, 1.15, .92))
  plant("CP101-011", "HGB",  aval = c(13.6, 13.4, 13.1, 12.6, 11.8, 11.1, 11.5, 12.4))
  plant("CP101-012", "ALT",  c(.8, .8, 1.0, 1.4, 2.3, 2.0, 1.6, 1.1))
  plant("CP101-012", "AST",  c(.8, .8, .9, 1.3, 2.1, 1.8, 1.4, 1.0))
  plant("CP101-012", "BILI", c(.6, .6, .7, .9, 1.4, 1.1, .9, .7))
  # CP101-017 (C4): creatinine baseline below LLN; rises above 1.5x baseline while still under ULN
  plant("CP101-017", "CREAT", aval = c(.56, .55, .58, .70, .84, .92, .88))
  # CP101-013 (C4): neutrophil nadir 0.9 x 10^9/L (CTCAE v5.0 grade 3; v6.0 grade 2)
  plant("CP101-013", "NEUT", aval = c(3.4, 3.3, 3.0, 2.1, .90, 1.60, 2.70, 3.10))
  # CP101-008 (C3): platelet nadir 42 x 10^9/L on Day 15 (the C3 DLT)
  plant("CP101-008", "PLAT", aval = c(238, 241, 220, 151, 42, 88, 176, 229))
  # CP101-003 (C1): missed Day 22 visit (no labs or ECG): a data-completeness gap, not a signal
  adlb <- adlb[!(adlb$USUBJID == "CP101-003" & adlb$AVISIT == "Day 22"), ]

  adlb <- merge(adlb, ref[, c("PARAMCD", "PARAM", "AVALU", "ANRLO", "ANRHI")], by = "PARAMCD")
  adlb$ABLFL <- ifelse(adlb$AVISIT == "Day 1", "Y", "")
  bl <- adlb[adlb$ABLFL == "Y", c("USUBJID", "PARAMCD", "AVAL")]; names(bl)[3] <- "BASE"
  adlb <- merge(adlb, bl, by = c("USUBJID", "PARAMCD"))
  adlb <- adlb[order(adlb$USUBJID, adlb$PARAMCD, adlb$ADY), c("USUBJID", "PARAMCD", "PARAM",
                 "AVISIT", "ADY", "AVAL", "AVALU", "ANRLO", "ANRHI", "BASE", "ABLFL")]
  adlb <- cbind(STUDYID = "CP-101", adlb, stringsAsFactors = FALSE)

  # ---- ECG: QTcF (Fridericia), triplicate mean in ms --------------------------
  tp <- data.frame(AVISIT = c("Day 1", "Day 1", "Day 8", "Day 15", "Day 22", "Day 28", "Day 43"),
                   ATPT = c("Predose", "4 h", "4 h", "4 h", "4 h", "4 h", "Follow-up"),
                   ADY = c(1L, 1L, 8L, 15L, 22L, 28L, 43L), stringsAsFactors = FALSE)
  eg <- list()
  for (i in seq_along(ids)) {
    b <- round(min(max(rnorm(1, 412, 9), 394), 436))
    ch <- pmin(pmax(round(rnorm(nrow(tp) - 1, 4, 5)), -10), 18)
    v <- c(b, pmin(b + ch, 449))
    keep <- tp$ADY <= adsl$LSTVISDY[i]
    eg[[i]] <- data.frame(USUBJID = ids[i], tp[keep, ], AVAL = v[keep], stringsAsFactors = FALSE)
  }
  adeg <- do.call(rbind, eg)
  set_eg <- function(id, v) { rows <- which(adeg$USUBJID == id); adeg$AVAL[rows] <<- v[seq_along(rows)] }
  set_eg("CP101-006", c(453, 458, 466, 486, 479, 471, 455))   # baseline already above 450
  set_eg("CP101-018", c(462, 468, 476, 489, 503, 497))        # follow-up ECG not yet done
  set_eg("CP101-011", c(448, 452, 459, 466, 474, 470, 451))
  set_eg("CP101-012", c(446, 450, 457, 468, 461, 455, 449))
  adeg <- adeg[!(adeg$USUBJID == "CP101-003" & adeg$AVISIT == "Day 22"), ]
  adeg$PARAMCD <- "QTCF"; adeg$PARAM <- "QTcF interval (ms)"
  adeg$ABLFL <- ifelse(adeg$ATPT == "Predose", "Y", "")
  bl <- adeg[adeg$ABLFL == "Y", c("USUBJID", "AVAL")]; names(bl)[2] <- "BASE"
  adeg <- merge(adeg, bl, by = "USUBJID")
  adeg$CHG <- ifelse(adeg$ABLFL == "Y", NA, adeg$AVAL - adeg$BASE)
  adeg <- adeg[order(adeg$USUBJID, adeg$ADY, adeg$ATPT != "Predose"),
               c("USUBJID", "PARAMCD", "PARAM", "AVISIT", "ATPT", "ADY", "AVAL", "BASE", "CHG", "ABLFL")]
  adeg <- cbind(STUDYID = "CP-101", adeg, stringsAsFactors = FALSE)

  # ---- adverse events (MedDRA PT, primary SOC; grade as recorded, NCI CTCAE v6.0) ----
  soc <- c(GI = "Gastrointestinal disorders", NS = "Nervous system disorders",
           GEN = "General disorders and administration site conditions",
           BLD = "Blood and lymphatic system disorders", INV = "Investigations",
           HEP = "Hepatobiliary disorders")
  ae <- function(id, pt, s, gr, st, en, ser = "N", rel = "Not related")
    data.frame(USUBJID = id, AEDECOD = pt, AEBODSYS = soc[[s]], AETOXGR = as.integer(gr),
               AESER = ser, AREL = rel, ASTDY = as.integer(st), AENDY = as.integer(en),
               TRTEMFL = "Y", stringsAsFactors = FALSE)
  adae <- rbind(
    ae("CP101-014", "Alanine aminotransferase increased", "INV", 3, 15, NA, "N", "Related"),
    ae("CP101-014", "Aspartate aminotransferase increased", "INV", 2, 15, NA, "N", "Related"),
    ae("CP101-014", "Hyperbilirubinaemia", "HEP", 3, 22, NA, "Y", "Related"),
    ae("CP101-014", "Fatigue", "GEN", 2, 16, 30, "N", "Possibly related"),
    ae("CP101-009", "Alanine aminotransferase increased", "INV", 2, 15, 29, "N", "Possibly related"),
    ae("CP101-004", "Blood bilirubin increased", "INV", 2, 4, 8, "N", "Not related"),
    ae("CP101-004", "Alanine aminotransferase increased", "INV", 2, 22, 29, "N", "Possibly related"),
    ae("CP101-006", "Electrocardiogram QT prolonged", "INV", 2, 15, 22, "N", "Possibly related"),
    ae("CP101-018", "Electrocardiogram QT prolonged", "INV", 3, 22, NA, "N", "Possibly related"),
    ae("CP101-018", "Dizziness", "NS", 1, 22, 24, "N", "Possibly related"),
    ae("CP101-008", "Platelet count decreased", "INV", 3, 15, 29, "N", "Related"),
    ae("CP101-013", "Neutrophil count decreased", "INV", 2, 15, 22, "N", "Possibly related"),
    ae("CP101-011", "Anaemia", "BLD", 1, 22, 43, "N", "Possibly related"),
    ae("CP101-011", "Nausea", "GI", 1, 8, 10, "N", "Possibly related"),
    ae("CP101-001", "Headache", "NS", 1, 2, 3),
    ae("CP101-002", "Nausea", "GI", 1, 1, 2, "N", "Possibly related"),
    ae("CP101-005", "Headache", "NS", 1, 9, 10),
    ae("CP101-005", "Diarrhoea", "GI", 1, 12, 14, "N", "Possibly related"),
    ae("CP101-007", "Nausea", "GI", 1, 3, 4, "N", "Possibly related"),
    ae("CP101-010", "Headache", "NS", 1, 5, 6),
    ae("CP101-012", "Fatigue", "GEN", 1, 10, 16),
    ae("CP101-013", "Diarrhoea", "GI", 2, 6, 9, "N", "Possibly related"),
    ae("CP101-015", "Headache", "NS", 1, 18, 19),
    ae("CP101-016", "Nausea", "GI", 1, 2, 3, "N", "Possibly related"),
    ae("CP101-017", "Dizziness", "NS", 1, 11, 12))
  adae <- cbind(STUDYID = "CP-101", adae, stringsAsFactors = FALSE)

  # ---- study-level operational indicators (values are synthetic) -------------------
  kri <- data.frame(
    ID = c("SF-RATE", "ENROLL", "QRY-AGE", "PROTDEV", "DATA-LAG"),
    INDICATOR = c("Screen-failure rate", "Enrollment versus plan", "Open queries older than 30 days",
                  "Important protocol deviations per dosed participant", "Median days from visit to data entry"),
    CATEGORY = c("Enrollment", "Enrollment", "Data", "Compliance", "Data"),
    VALUE = c(30.8, -22, 14, 0.11, 2),
    UNIT = c("%", "% vs plan", "queries", "per participant", "days"),
    WORSE = c("higher", "lower", "higher", "higher", "higher"),
    AMBER = c(30, -15, 10, 0.20, 5),
    RED = c(40, -30, 25, 0.40, 10),
    DETAIL = c("8 of 26 screened did not meet eligibility (plan: 25%)",
               "18 dosed against 23 planned by this date",
               "backlog rising ahead of the C4 data cut",
               "2 important deviations in 18 dosed participants",
               "entry within plan"),
    stringsAsFactors = FALSE)

  notes <- data.frame(USUBJID = c("CP101-014", "CP101-009", "CP101-004", "CP101-011", "CP101-012",
                                  "CP101-006", "CP101-018", "CP101-008", "CP101-013", "CP101-017", "CP101-003"),
    NOTE = c(
      "ALT and AST rise from Day 15; total bilirubin passes 2x ULN on Day 22, 7 days after the aminotransferase elevation, with ALP 1.1x ULN at that first elevation: a potential Hy's Law case. Adjudicated DLT; study drug stopped on Day 22.",
      "ALT 4.2x and AST 3.6x ULN on Day 15 with total bilirubin 1.6x ULN: not a potential Hy's Law case, but an aminotransferase elevation above 3x ULN that needs confirmation (repeat ALT, AST, ALP and total bilirubin within 48 to 72 hours). The first repeat came on Day 20 and was still above 3x ULN.",
      "Peak total bilirubin (2.4x ULN, Day 4) came 18 days before the peak ALT (3.3x ULN, Day 22), so the point sits in the upper-right eDISH quadrant on peak values but is not a potential Hy's Law case. The ALT elevation was repeated on Day 24 (2.6x ULN).",
      "Several analytes drift together, each below its own action threshold. No rule fires; whether the pattern deserves a closer look is the reviewer's call. Creatinine is grade 2 under CTCAE v5.0 (more than 1.5x baseline) but grade 1 under v6.0.",
      "A milder version of the same co-drift; every value below its action threshold.",
      "QTcF 486 ms on Day 15 (change 33 ms). Baseline was already 453 ms.",
      "QTcF 503 ms on Day 22 (change 41 ms). Baseline was already 462 ms. A candidate DLT under the synthetic protocol; the committee has not adjudicated it.",
      "Platelet count 42 x 10^9/L on Day 15 (grade 3): the C3 DLT, which led to the C3 expansion to 6.",
      "Neutrophil nadir 0.9 x 10^9/L on Day 15: grade 3 under CTCAE v5.0 and grade 2 under v6.0.",
      "Creatinine baseline 0.55 mg/dL, below the LLN; the Day 22 value is 1.67x baseline while still below the ULN (grade 2 under both v5.0 and v6.0).",
      "Missed the Day 22 visit: no labs or ECG that day. A completeness gap, not a clinical signal."),
    stringsAsFactors = FALSE)

  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  w <- function(x, f) utils::write.csv(x, file.path(out_dir, f), row.names = FALSE, na = "")
  w(adsl, "adsl.csv"); w(adlb, "adlb.csv"); w(adeg, "adeg.csv"); w(adae, "adae.csv")
  w(coh, "cohorts.csv"); w(kri, "study_kri.csv"); w(notes, "notes.csv")
  invisible(list(adsl = adsl, adlb = adlb, adeg = adeg, adae = adae))
}

if (sys.nframe() == 0) gen_trialmon(out_dir = "data")
