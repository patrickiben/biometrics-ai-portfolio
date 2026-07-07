#!/usr/bin/env Rscript
# Unit tests for the 3-tier termination-risk roll-up. Base R only.
# Run:  Rscript risk_monitor/tests/test-logic.R

lp <- Find(file.exists, c("../shiny/R/logic.R", "risk_monitor/shiny/R/logic.R", "shiny/R/logic.R"))
stopifnot("found logic.R" = !is.null(lp)); source(lp)
dir <- Find(function(d) file.exists(file.path(d, "signals.csv")),
            c("../shiny/data", "risk_monitor/shiny/data", "shiny/data"))
s <- risk_load(dir)
o <- risk_overall(s)
f <- risk_feed(s)
cn <- risk_counts(s)

stopifnot(
  "signals loaded"        = nrow(s) == 21,
  "three tiers"           = setequal(unique(s$tier), TIERS),
  "overall in 0..100"     = o$score >= 0 && o$score <= 100,
  "rag valid"             = o$rag %in% c("green","amber","red"),
  "feed is firing only"   = all(f$level != "green"),
  "feed ranked red-first" = nrow(f) == 0 || f$level[1] == "red",
  "counts add up"         = cn$red + cn$amber + cn$green == cn$total
)

# roll-up monotonic: escalating a signal never lowers its tier score
s2 <- s; s2$level[s2$id == "ESC-33"] <- factor("red", levels = c("green","amber","red"))
stopifnot("escalation raises tier score" =
  tier_score(s2, "Study")$score >= tier_score(s, "Study")$score)

cat("Risk logic: all tests passed\n")
