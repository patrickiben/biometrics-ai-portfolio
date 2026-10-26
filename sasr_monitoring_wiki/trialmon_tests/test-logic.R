#!/usr/bin/env Rscript
# Unit tests for the TRIALMON screening logic. Base R only.
# Run:  Rscript sasr_monitoring_wiki/trialmon_tests/test-logic.R

lp <- Find(file.exists, c("../trialmon_shiny/R/logic.R", "sasr_monitoring_wiki/trialmon_shiny/R/logic.R", "trialmon_shiny/R/logic.R"))
stopifnot("found logic.R" = !is.null(lp)); source(lp)
dir <- Find(function(d) file.exists(file.path(d, "participants.csv")),
            c("../trialmon_shiny/data", "sasr_monitoring_wiki/trialmon_shiny/data", "trialmon_shiny/data"))
tm <- trialmon_load(dir)
p  <- score_participants(tm$participants)
wl <- trialmon_worklist(tm)
k  <- trialmon_kpis(tm)

stopifnot(
  "22 participants"              = nrow(p) == 22,
  "CP101-014 is a Hy's position" = isTRUE(p$hys[p$id == "CP101-014"]),
  "CP101-009 is the AND-gate near-miss (ALT>3, TBili<2, NOT Hy's)" =
      p$alt[p$id=="CP101-009"] > 3 && p$tbl[p$id=="CP101-009"] < 2 && !p$hys[p$id=="CP101-009"],
  "CP101-018 QTcF RED"           = p$qsev[p$id == "CP101-018"] == "RED",
  "CP101-006 QTcF AMBER"         = p$qsev[p$id == "CP101-006"] == "AMBER",
  "overall status RED"           = trialmon_status(tm) == "RED",
  "worklist ranked red-first"    = nrow(wl) == 0 || wl$sev[1] == "RED",
  "C4 cohort shows a DLT"        = dlt_state(tm)$dlt[dlt_state(tm)$cohort == "C4"] == 1,
  "two SAEs"                     = k$sae == 2
)

# the eDISH AND-gate: ALT high alone must NOT fire Hy's without bili
stopifnot("AND-gate holds" = !score_participants(
  transform(tm$participants, alt = ifelse(id=="CP101-001", 9, alt)))$hys[tm$participants$id=="CP101-001"])

cat("TRIALMON logic: all tests passed\n")
