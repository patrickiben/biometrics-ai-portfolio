# ---------------------------------------------------------------------------
# logic.R: pure UAT evaluation logic for the IRT/RTSM tracker.
# Operations-only, synthetic, no PHI. "participant" not "subject".
#
# Plain functions shared by the Shiny app, the Quarto documents, and the unit
# tests. The go-live gate and the KPIs are computed here, once.
# ---------------------------------------------------------------------------

STATUSES  <- c("Pass", "Fail", "Blocked", "In Progress", "Not Run")
RUN_STATUSES <- c("Pass", "Fail")    # executed; the other three mean the test has not been run
SEVERITIES <- c("Critical", "Major", "Minor")

uat_validate <- function(tests, defects, trace) {
  required <- list(tests = c("TestID", "Area", "RequirementID", "TestTitle", "Priority", "Steps", "ExpectedResult", "Status", "LinkedDefect"),
                   defects = c("DefectID", "Severity", "Status", "FoundInTest", "Description", "DateRaised", "Resolution"),
                   trace = c("RequirementID", "RequirementDescription", "CoveringTests", "Covered"))
  frames <- list(tests = tests, defects = defects, trace = trace)
  keys <- c(tests = "TestID", defects = "DefectID", trace = "RequirementID")
  for (name in names(frames)) {
    frame <- frames[[name]]
    if (!is.data.frame(frame) || anyDuplicated(names(frame)) || !all(required[[name]] %in% names(frame)))
      stop("Missing or duplicated UAT columns in ", name, ".")
    key <- frame[[keys[[name]]]]
    if (anyNA(key) || any(!nzchar(trimws(key))) || anyDuplicated(key)) stop("UAT identifiers must be nonblank and unique in ", name, ".")
  }
  if (!nrow(tests) || !nrow(trace)) stop("At least one test and one requirement are required; an empty register cannot be ready.")
  allowed <- list(tests$Status %in% STATUSES, tests$Priority %in% c("Critical", "High", "Medium", "Low"),
                  defects$Severity %in% SEVERITIES, defects$Status %in% c("Open", "Closed"), trace$Covered %in% c("Y", "N", "N (GAP)"))
  if (!all(unlist(allowed))) stop("Unknown or missing UAT status, priority, severity or coverage flag.")
  invisible(TRUE)
}

uat_load <- function(dir = NULL) {
  if (!is.null(dir) && (!is.character(dir) || length(dir) != 1 || is.na(dir) || !nzchar(dir)))
    stop("Supply one explicit input path, or omit it to use the bundled example.")
  cand <- if (!is.null(dir)) dir else c( "../templates", "templates", "uat_irt/templates")
  cand <- Filter(Negate(is.null), cand)
  base <- Find(function(d) file.exists(file.path(d, "test_scripts.csv")), cand)
  if (is.null(base)) stop("Cannot find templates/test_scripts.csv (looked in: ",
                          paste(cand, collapse = ", "), ")")
  rd <- function(f) utils::read.csv(file.path(base, f), stringsAsFactors = FALSE, check.names = FALSE)
  data <- list(tests   = rd("test_scripts.csv"),
       defects = rd("defect_log.csv"),
       trace   = rd("traceability_matrix.csv"))
  uat_validate(data$tests, data$defects, data$trace)
  data
}

# The go-live sign-off gate: three criteria, all of which must hold (conjunctive).
#   1. Every Critical test passes.
#   2. No open Critical or Major defect, and every fix was retested: a closed defect's test
#      (FoundInTest) passes, and a failing test has an open defect logged against it. Open Minor
#      defects do not block; the person who signs fixes them or waives them with a rationale.
#   3. Every requirement has a test, and every test has been run (Pass or Fail): none is still
#      Not Run, In Progress or Blocked, including a draft test added to close a traceability gap.
# crit_fail, open_cm and trace_gap keep their earlier meaning (the Quarto pages print them).
uat_gate <- function(tests, defects, trace) {
  b <- uat_blockers(tests, defects, trace)
  n <- vapply(b[c("tests", "defects", "unretested", "untracked", "gaps", "not_run")], nrow, 0L)
  defects_ok <- n[["defects"]] + n[["unretested"]] + n[["untracked"]] == 0
  trace_ok   <- n[["gaps"]] + n[["not_run"]] == 0
  go <- n[["tests"]] == 0 && defects_ok && trace_ok
  list(crit_fail = n[["tests"]], open_cm = n[["defects"]], unretested = n[["unretested"]],
       untracked = n[["untracked"]], trace_gap = n[["gaps"]], not_run = n[["not_run"]],
       tests_ok = n[["tests"]] == 0, defects_ok = defects_ok, trace_ok = trace_ok,
       minor_open = b$minor_open$DefectID, go = go,
       verdict = if (go) "READY for sign-off" else "NOT ready - blocked")
}

uat_summary <- function(tests, defects, trace) {
  uat_validate(tests, defects, trace)
  total    <- nrow(tests)
  pass     <- sum(tests$Status == "Pass")
  fail     <- sum(tests$Status == "Fail")
  open_now <- sum(!tests$Status %in% RUN_STATUSES)
  run      <- sum(tests$Status %in% RUN_STATUSES)
  open_def <- sum(defects$Status == "Open")
  covered <- uat_valid_coverage(tests, trace)
  traced   <- sum(covered)
  run_ids  <- tests$TestID[tests$Status %in% RUN_STATUSES]
  covering <- uat_covering_tests(trace)
  req_run  <- sum(covered & vapply(covering, function(t) length(t) > 0 && all(t %in% run_ids), NA))
  list(total = total, pass = pass, fail = fail, open_now = open_now,
       open_def = open_def, traced = traced, req_run = req_run, n_urs = nrow(trace),
       cov = round(100 * traced / nrow(trace)),
       pass_rate = if (run > 0) round(100 * pass / run) else 0)
}

# Counts per test area by status, tidy for a stacked bar.
uat_area_counts <- function(tests) {
  df <- as.data.frame(table(Area = tests$Area, Status = factor(tests$Status, levels = STATUSES)))
  df[df$Freq > 0, ]
}

# The test IDs that cover each requirement ("RAND-01" or "RAND-01; RAND-07"), one vector per row.
uat_covering_tests <- function(trace) {
  x <- ifelse(is.na(trace$CoveringTests), "", as.character(trace$CoveringTests))
  lapply(strsplit(x, "[;,[:space:]]+"), function(v) v[nzchar(v)])
}

# A manually typed Y flag is not evidence that the referenced tests exist.
uat_valid_coverage <- function(tests, trace) {
  trace$Covered == "Y" & vapply(uat_covering_tests(trace),
    function(ids) length(ids) > 0 && all(ids %in% tests$TestID), logical(1))
}

# The status of the test each defect was found in (NA when the defect names no test in the table).
defect_test_status <- function(tests, defects) {
  tests$Status[match(defects$FoundInTest, tests$TestID)]
}

# What keeps the gate blocked, criterion by criterion, so the app can name each item.
#   tests       critical tests that do not pass                                  (criterion 1)
#   defects     open critical or major defects                                   (criterion 2)
#   unretested  closed defects whose test does not pass: the fix was not retested (criterion 2)
#   untracked   failing tests with no defect logged against them: none open, and none
#               closed (a closed one is listed under unretested instead)       (criterion 2)
#   gaps        requirements without a test                                      (criterion 3)
#   not_run     tests not run yet: Not Run, In Progress or Blocked               (criterion 3)
#   minor_open  open minor defects: they do not block, but the signer must fix or waive them
uat_blockers <- function(tests, defects, trace) {
  uat_validate(tests, defects, trace)
  found_st <- defect_test_status(tests, defects)
  is_open  <- defects$Status == "Open"
  named    <- !is.na(defects$FoundInTest) & nzchar(defects$FoundInTest)
  linked   <- ifelse(is.na(tests$LinkedDefect), "", tests$LinkedDefect)
  open_for <- unique(c(defects$FoundInTest[is_open], tests$TestID[linked %in% defects$DefectID[is_open]]))
  unret    <- defects$Status == "Closed" & named & !(found_st %in% "Pass")   # a missing test counts too
  list(
    tests      = tests[tests$Priority == "Critical" & tests$Status != "Pass", c("TestID", "Status"), drop = FALSE],
    defects    = defects[is_open & defects$Severity %in% c("Critical", "Major"),
                         c("DefectID", "Severity", "FoundInTest"), drop = FALSE],
    unretested = cbind(defects[unret, c("DefectID", "Severity", "FoundInTest"), drop = FALSE],
                       TestStatus = found_st[unret]),
    untracked  = tests[tests$Status == "Fail" & !tests$TestID %in% c(open_for, defects$FoundInTest[unret]),
                       c("TestID", "Status"), drop = FALSE],
    gaps       = trace[!uat_valid_coverage(tests, trace), c("RequirementID", "RequirementDescription"), drop = FALSE],
    not_run    = tests[!tests$Status %in% RUN_STATUSES, c("TestID", "Status", "RequirementID"), drop = FALSE],
    minor_open = defects[is_open & defects$Severity == "Minor", c("DefectID", "FoundInTest"), drop = FALSE])
}

# May this defect be closed now? Only once the test it was found in passes on retest. A defect
# that names no test (found outside a script) can be closed at any time.
uat_can_close <- function(tests, defects, id) {
  r <- match(id, defects$DefectID)
  if (is.na(r)) return(list(ok = FALSE, test = NA_character_, status = NA_character_))
  test <- defects$FoundInTest[r]
  if (is.na(test) || !nzchar(test)) return(list(ok = TRUE, test = NA_character_, status = NA_character_))
  st <- tests$Status[match(test, tests$TestID)]
  list(ok = identical(st, "Pass"), test = test, status = st)
}

# Read a defect status typed by a person: "closed", " Close ", "OPEN" -> "Closed" / "Open"; else NA.
uat_defect_status <- function(x) {
  x <- tolower(trimws(as.character(x)))
  ifelse(x %in% c("open", "reopen", "reopened"), "Open",
         ifelse(x %in% c("closed", "close", "fixed"), "Closed", NA_character_))
}

# Close a traceability gap the way a UAT lead would: write a draft test script for the
# requirement and record it in the matrix. The draft is Not Run, so the gate stays blocked
# (criterion 3) until someone writes its steps and runs it.
# The new ID follows the requirement's area, e.g. URS-SUP-005 -> SUP-05 in "Resupply / inventory".
uat_cover_gap <- function(tests, trace, req_id) {
  i <- match(req_id, trace$RequirementID)
  if (is.na(i)) stop("No requirement ", req_id, " in the traceability matrix")
  if (isTRUE(uat_valid_coverage(tests, trace)[i])) return(list(tests = tests, trace = trace, test_id = NA_character_))
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
