# ---------------------------------------------------------------------------
# logic.R: pure UAT evaluation logic for the IRT/RTSM tracker.
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

# What keeps the gate blocked, criterion by criterion, so the app can name each item.
uat_blockers <- function(tests, defects, trace) {
  list(
    tests   = tests[tests$Priority == "Critical" & tests$Status != "Pass", c("TestID", "Status"), drop = FALSE],
    defects = defects[defects$Status == "Open" & defects$Severity %in% c("Critical", "Major"),
                      c("DefectID", "Severity", "FoundInTest"), drop = FALSE],
    gaps    = trace[trace$Covered != "Y", c("RequirementID", "RequirementDescription"), drop = FALSE])
}

# Read a defect status typed by a person: "closed", " Close ", "OPEN" -> "Closed" / "Open"; else NA.
uat_defect_status <- function(x) {
  x <- tolower(trimws(as.character(x)))
  ifelse(x %in% c("open", "reopen", "reopened"), "Open",
         ifelse(x %in% c("closed", "close", "fixed"), "Closed", NA_character_))
}

# Close a traceability gap the way a UAT lead would: write a draft test script for the
# requirement (status Not Run, so it still has to be executed) and record it in the matrix.
# The new ID follows the requirement's area, e.g. URS-SUP-005 -> SUP-05 in "Resupply / inventory".
uat_cover_gap <- function(tests, trace, req_id) {
  i <- match(req_id, trace$RequirementID)
  if (is.na(i)) stop("No requirement ", req_id, " in the traceability matrix")
  if (identical(trace$Covered[i], "Y")) return(list(tests = tests, trace = trace, test_id = NA_character_))
  stem <- sub("-[0-9]+$", "-", req_id)                                # "URS-SUP-"
  kin <- tests[startsWith(tests$RequirementID, stem), , drop = FALSE]
  area <- if (nrow(kin)) names(sort(table(kin$Area), decreasing = TRUE))[1] else "Unassigned"
  pre <- if (nrow(kin)) sub("-[0-9]+$", "", kin$TestID[1]) else sub("^URS-|-[0-9]+$", "", stem)
  num <- suppressWarnings(as.integer(sub("^.*-", "", tests$TestID[startsWith(tests$TestID, paste0(pre, "-"))])))
  new_id <- sprintf("%s-%02d", pre, max(c(0L, num), na.rm = TRUE) + 1L)
  desc <- trace$RequirementDescription[i]
  row <- tests[NA_integer_, , drop = FALSE]                           # one row of NAs, same columns
  row$TestID <- new_id; row$Area <- area; row$RequirementID <- req_id
  row$TestTitle <- sub("\\.$", "", sub(" shall be ", " is ", desc))
  row$Priority <- "High"
  row$Steps <- "Draft script added to close the traceability gap: write the steps, then execute it."
  row$ExpectedResult <- desc
  row$Status <- "Not Run"
  row$LinkedDefect <- ""
  trace$CoveringTests[i] <- new_id
  trace$Covered[i] <- "Y"
  tests <- rbind(tests, row)
  rownames(tests) <- NULL
  list(tests = tests, trace = trace, test_id = new_id)
}

# How far the current state is from the seed: changed test statuses, added tests, changed defects.
uat_changes <- function(tests, defects, seed) {
  m <- match(seed$tests$TestID, tests$TestID)
  d <- match(seed$defects$DefectID, defects$DefectID)
  sum(!is.na(m) & tests$Status[m] != seed$tests$Status) +
    sum(!tests$TestID %in% seed$tests$TestID) +
    sum(!is.na(d) & defects$Status[d] != seed$defects$Status)
}
