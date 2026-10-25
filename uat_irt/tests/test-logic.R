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
  "totals add up"                 = s$pass + s$fail + s$open_now == s$total
)

# fixing every criterion makes the gate READY
t2  <- d$tests;   t2$Status[t2$Priority == "Critical"] <- "Pass"
df2 <- d$defects; df2$Status[df2$Severity %in% c("Critical", "Major")] <- "Closed"
tr2 <- d$trace;   tr2$Covered <- "Y"
stopifnot("fixing all criteria -> READY" = uat_gate(t2, df2, tr2)$go)

# what blocks the seed gate, item by item (the app turns each into a link)
b <- uat_blockers(d$tests, d$defects, d$trace)
stopifnot(
  "blocking critical tests"   = identical(b$tests$TestID, c("RAND-04", "COH-03")),
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
  "covering twice changes nothing" = is.na(uat_cover_gap(cg$tests, cg$trace, "URS-SUP-005")$test_id),
  "an unknown requirement errors" = inherits(try(uat_cover_gap(d$tests, d$trace, "URS-NOPE-1"), silent = TRUE), "try-error")
)

# the visitor's path to READY: two critical tests pass, two defects close, one draft test added
t3 <- cg$tests; t3$Status[t3$TestID %in% c("RAND-04", "COH-03")] <- "Pass"
df3 <- d$defects; df3$Status[df3$DefectID %in% c("DEF-01", "DEF-03")] <- "Closed"
stopifnot("the app's path reaches READY" = uat_gate(t3, df3, cg$trace)$go,
          "and the summary shows 100% traced" = uat_summary(t3, df3, cg$trace)$cov == 100)

# changes since the seed: 2 statuses + 1 added test + 2 defects
stopifnot("no changes at the seed" = uat_changes(d$tests, d$defects, d) == 0,
          "five changes on the path" = uat_changes(t3, df3, d) == 5)

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
