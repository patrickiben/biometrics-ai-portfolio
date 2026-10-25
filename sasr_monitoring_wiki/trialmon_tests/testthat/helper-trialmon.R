# Shared setup for the TRIALMON tests. testthat runs this before the test files, from this folder.
APP_DIR <- normalizePath(file.path("..", "..", "trialmon_shiny"), mustWork = TRUE)
source(file.path(APP_DIR, "R", "logic.R"))
TM <- trialmon_load(file.path(APP_DIR, "data"))
S0 <- study_signals(TM)   # the study tier as the app starts (the app calls it STUDY0)

ULN <- c(ALT = 40, AST = 40, ALP = 120, BILI = 1.2)

# A one-participant liver panel. Values are multiples of ULN by study day; day 1 is baseline.
make_liver <- function(days, alt, ast = alt * 0 + 0.5, alp = alt * 0 + 0.8, tbl = alt * 0 + 0.5, id = "T-001") {
  d <- c(1, days)
  v <- list(ALT = c(0.5, alt), AST = c(0.5, ast), ALP = c(0.8, alp), BILI = c(0.5, tbl))
  do.call(rbind, lapply(names(v), function(p) data.frame(
    USUBJID = id, PARAMCD = p, AVISIT = ifelse(d == 1, "Day 1", paste("Day", d)), ADY = d,
    AVAL = v[[p]] * ULN[[p]], ANRLO = 0, ANRHI = ULN[[p]], BASE = v[[p]][1] * ULN[[p]],
    ABLFL = ifelse(d == 1, "Y", ""), stringsAsFactors = FALSE)))
}

# A one-participant QTcF record: a predose baseline and post-dose values (ms)
make_qtc <- function(base, post, id = "T-001") {
  n <- length(post)
  data.frame(USUBJID = id, PARAMCD = "QTCF", AVISIT = c("Day 1", paste("Day", seq_len(n) * 7)),
             ATPT = c("Predose", rep("4 h", n)), ADY = c(1, seq_len(n) * 7), AVAL = c(base, post),
             BASE = base, CHG = c(NA, post - base), ABLFL = c("Y", rep("", n)), stringsAsFactors = FALSE)
}

# Replace one cohort's participants with n treated, n_eval evaluable and n_dlt confirmed DLTs
with_cohort <- function(tm, cohort, n, n_eval = n, n_dlt = 0, n_pending = 0) {
  s <- tm$adsl[tm$adsl$COHORT != cohort, ]
  dose <- tm$cohorts$DOSEMG[tm$cohorts$COHORT == cohort]
  new <- s[rep(1, n), ]
  new$USUBJID <- sprintf("X-%s-%02d", cohort, seq_len(n)); new$COHORT <- cohort; new$DOSEMG <- dose
  new$DLTEVLFL <- ifelse(seq_len(n) <= n_eval, "Y", "N")
  new$DLTFL <- ifelse(seq_len(n) <= n_dlt, "Y", "N"); new$DLTADJ <- "Final"
  if (n_pending) { k <- n_dlt + seq_len(n_pending); new$DLTFL[k] <- ""; new$DLTADJ[k] <- "Pending" }
  tm$adsl <- rbind(s, new)
  tm
}
