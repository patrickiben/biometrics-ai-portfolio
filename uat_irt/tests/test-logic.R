#!/usr/bin/env Rscript
# Unit tests for the UAT gate/KPI logic. Zero dependencies (base R only).
# Run from the package root:  Rscript uat_irt/tests/test-logic.R
# or from this folder:        Rscript test-logic.R

lp <- Find(file.exists, c("../shiny/R/logic.R", "uat_irt/shiny/R/logic.R", "shiny/R/logic.R"))
stopifnot("found logic.R" = !is.null(lp))
source(lp)

dir <- Find(function(d) file.exists(file.path(d, "test_scripts.csv")),
            c("../templates", "uat_irt/templates", "templates"))
d <- uat_load(dir)

g <- uat_gate(d$tests, d$defects, d$trace)
s <- uat_summary(d$tests, d$defects, d$trace)

stopifnot(
  "seed gate is blocked"          = !g$go,
  "two open critical/major"       = g$open_cm == 2,
  "one traceability gap"          = g$trace_gap == 1,
  "at least one critical failing" = g$crit_fail >= 1,
  "coverage < 100 with the gap"   = s$cov < 100,
  "totals add up"                 = s$pass + s$fail + s$open_now == s$total,
  "24 requirements tested so far"  = s$req_run == 24
)

# fixing every criterion makes the gate READY: every test run and passing, the critical and
# major defects closed, every requirement traced
t2  <- d$tests;   t2$Status <- "Pass"
df2 <- d$defects; df2$Status[df2$Severity %in% c("Critical", "Major")] <- "Closed"
tr2 <- d$trace;   tr2$Covered <- "Y"
g2  <- uat_gate(t2, df2, tr2)
stopifnot("fixing all criteria -> READY" = g2$go,
          "the open minor defect is named for the signer" = identical(g2$minor_open, "DEF-04"))

# the shortcut is not enough: critical tests passing, critical and major defects closed and every
# requirement traced still leaves SUP-03 failing under a closed defect and four tests not run
t1 <- d$tests; t1$Status[t1$Priority == "Critical"] <- "Pass"
g1 <- uat_gate(t1, df2, tr2)
b1 <- uat_blockers(t1, df2, tr2)
stopifnot(
  "the shortcut is still blocked"         = !g1$go && g1$tests_ok && !g1$defects_ok && !g1$trace_ok,
  "a closed defect whose test fails"      = identical(b1$unretested$DefectID, "DEF-03") && b1$unretested$TestStatus == "Fail",
  "tests not run block traceability"      = identical(b1$not_run$TestID, c("ENR-03", "DISP-03", "UNBL-03", "NOT-02")),
  "old counts keep their meaning"         = g1$crit_fail == 0 && g1$open_cm == 0 && g1$trace_gap == 0
)

# the seed's blockers under the second and third criteria
g0 <- uat_gate(d$tests, d$defects, d$trace)
stopifnot("five tests not run at the seed" = g0$not_run == 5, "nothing unretested at the seed" = g0$unretested == 0,
          "no untracked failure at the seed" = g0$untracked == 0)

# a defect closes only after the test it was found in passes on retest
t4 <- d$tests; t4$Status[t4$TestID == "RAND-04"] <- "Pass"
stopifnot(
  "DEF-01 cannot close while RAND-04 fails" = !uat_can_close(d$tests, d$defects, "DEF-01")$ok,
  "and names the test to retest"            = identical(uat_can_close(d$tests, d$defects, "DEF-01")$test, "RAND-04"),
  "DEF-01 can close once RAND-04 passes"    = uat_can_close(t4, d$defects, "DEF-01")$ok,
  "DEF-04 (its test passes) can close"      = uat_can_close(d$tests, d$defects, "DEF-04")$ok,
  "an unknown defect cannot close"          = !uat_can_close(d$tests, d$defects, "DEF-99")$ok
)

# a failing test needs an open defect; an open minor defect is enough (the signer waives or fixes it)
t5 <- d$tests; t5$Status[t5$TestID %in% c("ENR-03", "NOT-01")] <- "Fail"
b5 <- uat_blockers(t5, d$defects, d$trace)
stopifnot("ENR-03 fails with no defect: blocks" = identical(b5$untracked$TestID, "ENR-03"),
          "NOT-01 fails under open minor DEF-04: tracked" = !"NOT-01" %in% b5$untracked$TestID)

# what blocks the seed gate, item by item (the app turns each into a link)
b <- uat_blockers(d$tests, d$defects, d$trace)
stopifnot(
  "blocking critical tests"   = identical(b$tests$TestID, c("RAND-04", "COH-03")),
  "tests not run yet"         = identical(b$not_run$TestID, c("COH-03", "ENR-03", "DISP-03", "UNBL-03", "NOT-02")),
  "blocking defects"          = identical(b$defects$DefectID, c("DEF-01", "DEF-03")),
  "defects name their test"   = identical(b$defects$FoundInTest, c("RAND-04", "SUP-03")),
  "the untraced requirement"  = identical(b$gaps$RequirementID, "URS-SUP-005"),
  "counts match the gate"     = nrow(b$tests) == g$crit_fail && nrow(b$defects) == g$open_cm && nrow(b$gaps) == g$trace_gap
)

# a typed defect status is read forgivingly, and anything else is refused
stopifnot(identical(uat_defect_status(c("Closed", " closed ", "CLOSE", "open", "Reopen", "maybe", "", NA)),
                    c("Closed", "Closed", "Closed", "Open", "Open", NA, NA, NA)))

# covering the gap adds a draft test (Not Run) in the right area and traces the requirement
cg <- uat_cover_gap(d$tests, d$trace, "URS-SUP-005")
new <- cg$tests[cg$tests$TestID == cg$test_id, ]
stopifnot(
  "new test ID follows the area" = identical(cg$test_id, "SUP-05"),
  "one row added"                = nrow(cg$tests) == nrow(d$tests) + 1,
  "same columns"                 = identical(names(cg$tests), names(d$tests)),
  "draft: area, status"          = new$Area == "Resupply / inventory" && new$Status == "Not Run" && new$RequirementID == "URS-SUP-005",
  "no NA left in the new row"    = !anyNA(unlist(new)),
  "requirement now covered"      = cg$trace$Covered[cg$trace$RequirementID == "URS-SUP-005"] == "Y",
  "gap closed in the gate"       = uat_gate(cg$tests, d$defects, cg$trace)$trace_gap == 0,
  "but the draft is not run yet" = "SUP-05" %in% uat_blockers(cg$tests, d$defects, cg$trace)$not_run$TestID,
  "covering twice changes nothing" = is.na(uat_cover_gap(cg$tests, cg$trace, "URS-SUP-005")$test_id),
  "an unknown requirement errors" = inherits(try(uat_cover_gap(d$tests, d$trace, "URS-NOPE-1"), silent = TRUE), "try-error")
)

# the visitor's path to READY: retest the two critical failures and SUP-03 (Pass), close their
# defects, run the four other tests not run yet, then add the draft test and run it
DONE <- c("RAND-04", "COH-03", "SUP-03", "ENR-03", "DISP-03", "UNBL-03", "NOT-02")
t3 <- cg$tests; t3$Status[t3$TestID %in% DONE] <- "Pass"
df3 <- d$defects; df3$Status[df3$DefectID %in% c("DEF-01", "DEF-03")] <- "Closed"
stopifnot("one step short: the draft is not run" = !uat_gate(t3, df3, cg$trace)$go)
t3$Status[t3$TestID == "SUP-05"] <- "Pass"
s3 <- uat_summary(t3, df3, cg$trace)
stopifnot("the app's path reaches READY"      = uat_gate(t3, df3, cg$trace)$go,
          "and the summary shows 100% traced" = s3$cov == 100 && s3$req_run == 30)

# the earlier five-step path (two critical passes, two defects closed, the draft added) is refused:
# SUP-03 still fails under its closed defect, and five tests have not been run
t6 <- cg$tests; t6$Status[t6$TestID %in% c("RAND-04", "COH-03")] <- "Pass"
g6 <- uat_gate(t6, df3, cg$trace)
stopifnot("the five-step path stays blocked" = !g6$go && g6$unretested == 1 && g6$not_run == 5)

# changes since the seed: 7 statuses + 1 added test + 2 defects
stopifnot("no changes at the seed" = uat_changes(d$tests, d$defects, d) == 0,
          "ten changes on the path" = uat_changes(t3, df3, d) == 10)

# the area counts cover every test once
ac <- uat_area_counts(d$tests)
stopifnot("area counts add up" = sum(ac$Freq) == nrow(d$tests), "no zero rows" = all(ac$Freq > 0))

# Shinylive readiness: the app folder carries its own copy of the seed CSVs (the export
# bundles only the app folder), the copy matches templates/ byte for byte, and the app
# builds its download in the browser instead of using a downloadHandler
app_dir <- dirname(dirname(lp))
csvs <- c("test_scripts.csv", "defect_log.csv", "traceability_matrix.csv")
bundled <- file.path(app_dir, "templates", csvs)
stopifnot(
  "the app folder bundles the seed CSVs"   = all(file.exists(bundled)),
  "the bundled CSVs match templates/"      = identical(unname(tools::md5sum(bundled)),
                                                       unname(tools::md5sum(file.path(dir, csvs)))),
  "no downloadHandler in the app"          = !any(grepl("downloadHandler|downloadButton",
                                                        sub("#.*$", "", readLines(file.path(app_dir, "app.R"))))),
  "only shiny, bslib, DT and ggplot2"      = setequal(
    sub("^\\s*library\\(([^)]+)\\).*$", "\\1", grep("^\\s*library\\(", readLines(file.path(app_dir, "app.R")), value = TRUE)),
    c("shiny", "bslib", "DT", "ggplot2"))
)

cat("UAT logic: all tests passed\n")
