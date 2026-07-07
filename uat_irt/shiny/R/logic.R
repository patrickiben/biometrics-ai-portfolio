# ---------------------------------------------------------------------------
# logic.R — pure UAT evaluation logic for the IRT/RTSM tracker.
# Operations-only, synthetic, no PHI. "participant" not "subject".
#
# Plain functions shared by the Shiny app, the Quarto documents, and the unit
# tests. The go-live gate and the KPIs are computed here, once.
# ---------------------------------------------------------------------------

STATUSES  <- c("Pass", "Fail", "Blocked", "In Progress", "Not Run")
SEVERITIES <- c("Critical", "Major", "Minor")

uat_load <- function(dir = NULL) {
  cand <- c(dir, "../templates", "templates", "uat_irt/templates")
  cand <- Filter(Negate(is.null), cand)
  base <- Find(function(d) file.exists(file.path(d, "test_scripts.csv")), cand)
  if (is.null(base)) stop("Cannot find templates/test_scripts.csv (looked in: ",
                          paste(cand, collapse = ", "), ")")
  rd <- function(f) utils::read.csv(file.path(base, f), stringsAsFactors = FALSE, check.names = FALSE)
  list(tests   = rd("test_scripts.csv"),
       defects = rd("defect_log.csv"),
       trace   = rd("traceability_matrix.csv"))
}

# The go-live sign-off gate. READY only when: every Critical test passes,
# there are zero OPEN Critical/Major defects, and traceability is complete.
uat_gate <- function(tests, defects, trace) {
  crit_fail <- sum(tests$Priority == "Critical" & tests$Status != "Pass")
  open_cm   <- sum(defects$Status == "Open" & defects$Severity %in% c("Critical", "Major"))
  trace_gap <- sum(trace$Covered != "Y")
  go <- crit_fail == 0 && open_cm == 0 && trace_gap == 0
  list(crit_fail = crit_fail, open_cm = open_cm, trace_gap = trace_gap, go = go,
       verdict = if (go) "READY for sign-off" else "NOT ready - blocked")
}

uat_summary <- function(tests, defects, trace) {
  total    <- nrow(tests)
  pass     <- sum(tests$Status == "Pass")
  fail     <- sum(tests$Status == "Fail")
  open_now <- sum(tests$Status %in% c("Blocked", "In Progress", "Not Run"))
  run      <- sum(tests$Status %in% c("Pass", "Fail"))
  open_def <- sum(defects$Status == "Open")
  traced   <- sum(trace$Covered == "Y")
  list(total = total, pass = pass, fail = fail, open_now = open_now,
       open_def = open_def, traced = traced, n_urs = nrow(trace),
       cov = round(100 * traced / nrow(trace)),
       pass_rate = if (run > 0) round(100 * pass / run) else 0)
}

# Counts per test area by status, tidy for a stacked bar.
uat_area_counts <- function(tests) {
  df <- as.data.frame(table(Area = tests$Area, Status = factor(tests$Status, levels = STATUSES)))
  df[df$Freq > 0, ]
}
