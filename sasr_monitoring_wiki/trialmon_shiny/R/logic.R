# ---------------------------------------------------------------------------
# logic.R - pure SCREENING logic for TRIALMON. Operations-only, synthetic, no PHI.
# Every function is a screening lens: it flags a position for a human reviewer.
# It never reports a clinical number and never adjudicates a DLT or a Hy's-Law case.
# Reported safety numbers come from the validated safety database.
#
# Screening rules (illustrative thresholds):
#   eDISH / Hy's-Law : (ALT or AST > 3x ULN) AND TBili > 2x ULN           -> RED
#   QTcF (ICH E14)   : QTcF > 500 ms or dQTcF > 60 ms  -> RED ; >480/>30  -> AMBER
#   3+3 DLT          : >= 2 adjudicated DLT in an evaluable cohort -> RED ; 1 -> AMBER
# ---------------------------------------------------------------------------

trialmon_load <- function(dir = NULL) {
  cand <- c(dir, "data", "../data", "trialmon_shiny/data", "sasr_monitoring_wiki/trialmon_shiny/data")
  cand <- Filter(Negate(is.null), cand)
  base <- Find(function(d) file.exists(file.path(d, "participants.csv")), cand)
  if (is.null(base)) stop("Cannot find participants.csv (run R/gen_data.R first)")
  rd <- function(f) utils::read.csv(file.path(base, f), stringsAsFactors = FALSE)
  list(participants = rd("participants.csv"), aes = rd("aes.csv"), cohorts = rd("cohorts.csv"))
}

qtc_sev <- function(qt, dqt) {
  if (qt > 500 || dqt > 60) "RED" else if (qt > 480 || dqt > 30) "AMBER" else if (qt > 450) "watch" else "GREEN"
}
r_pattern <- function(r) if (r >= 5) "hepatocellular" else if (r >= 2) "mixed" else "cholestatic"

# Attach screening columns to the participant frame.
score_participants <- function(p) {
  p$hys    <- (p$alt > 3 | p$ast > 3) & p$tbl > 2
  p$rratio <- round(p$alt / p$alp, 1)
  p$pattern <- vapply(p$rratio, r_pattern, character(1))
  p$qsev   <- mapply(qtc_sev, p$qt, p$dqt)
  p
}

# Per-cohort 3+3 DLT screening state.
dlt_state <- function(tm) {
  p <- tm$participants
  do.call(rbind, lapply(split(p, p$cohort), function(x) {
    nd <- sum(x$dltfl == "Y"); neval <- sum(x$dlteval == "Y")
    sev <- if (nd >= 2) "RED" else if (nd == 1) "AMBER" else "GREEN"
    data.frame(cohort = x$cohort[1], dose_mg = x$dose_mg[1], n = nrow(x),
               dlt = nd, evaluable = neval, sev = sev, stringsAsFactors = FALSE)
  }))
}

sev_rank <- function(x) match(x, c("GREEN","watch","AMBER","RED"))
worst    <- function(v) c("GREEN","watch","AMBER","RED")[max(sev_rank(v), na.rm = TRUE)]

# The screening worklist: every firing position, ranked RED before AMBER.
trialmon_worklist <- function(tm) {
  p <- score_participants(tm$participants); wl <- list()
  add <- function(id, sev, check, val, rule) wl[[length(wl)+1]] <<-
    data.frame(id=id, sev=sev, check=check, value=val, rule=rule, stringsAsFactors=FALSE)
  for (j in which(p$hys)) add(p$id[j], "RED", "eDISH / Hy's-Law screen",
      sprintf("ALT %.1fx & TBili %.1fx (R %.1f %s)", p$alt[j], p$tbl[j], p$rratio[j], p$pattern[j]),
      "(ALT or AST >3x) AND TBili >2x")
  for (j in which(p$qsev == "RED")) add(p$id[j], "RED", "QTcF (ICH E14 screen)",
      sprintf("%d ms, d%d", p$qt[j], p$dqt[j]), "QTcF >500 or dQTcF >60 ms")
  for (j in which(p$qsev == "AMBER")) add(p$id[j], "AMBER", "QTcF (ICH E14 screen)",
      sprintf("%d ms, d%d", p$qt[j], p$dqt[j]), "QTcF >480 or dQTcF >30 ms")
  ds <- dlt_state(tm)
  for (j in which(ds$sev != "GREEN")) add(paste(ds$cohort[j], "cohort"), ds$sev[j],
      "Adjudicated DLT vs 3+3", sprintf("%d/%d evaluable", ds$dlt[j], ds$evaluable[j]),
      if (ds$sev[j]=="RED") ">=2 DLT in cohort" else "1 DLT in cohort")
  if (!length(wl)) return(data.frame())
  out <- do.call(rbind, wl); out[order(out$sev != "RED"), ]
}

trialmon_status <- function(tm) {
  p <- score_participants(tm$participants); ds <- dlt_state(tm)
  worst(c(if (any(p$hys)) "RED" else "GREEN", p$qsev, ds$sev))
}

trialmon_kpis <- function(tm) {
  p <- score_participants(tm$participants); ae <- tm$aes
  list(n = nrow(p), cohorts = nrow(tm$cohorts),
       red = sum(p$hys) + sum(p$qsev == "RED") + sum(dlt_state(tm)$sev == "RED"),
       amber = sum(p$qsev == "AMBER") + sum(dlt_state(tm)$sev == "AMBER"),
       g3ae = length(unique(ae$id[ae$grade >= 3])),
       sae = sum(ae$serious == "Y"),
       ongoing = sum(p$disposition == "Ongoing"))
}

# A simple visit trajectory for one analyte, baseline -> peak (for the detail view).
trajectory <- function(baseline, peak, visits = c("Screen","C1D1","C1D8","C1D15","C2D1","C3D1","EOT")) {
  n <- length(visits); f <- seq(0, 1, length.out = n)^1.4
  data.frame(visit = factor(visits, levels = visits), value = round(baseline + (peak - baseline) * f, 2))
}
