#!/usr/bin/env Rscript
# Unit tests for the two-tier (participant and study) risk roll-up. Base R only.
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
  "signals loaded"        = nrow(s) == 15,
  "two tiers"             = setequal(unique(s$tier), TIERS),
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

# A malformed replacement feed must never silently produce green or NaN.
rejected <- function(x) inherits(try(risk_overall(x), silent = TRUE), "try-error")
for (kind in c("zero", "negative", "infinite", "missing", "bad-level", "missing-tier", "duplicate-id")) {
  bad <- s
  if (kind == "zero") bad$weight[bad$tier == "Study"] <- 0
  if (kind == "negative") bad$weight[1] <- -1
  if (kind == "infinite") bad$weight[1] <- Inf
  if (kind == "missing") bad$weight[1] <- NA_real_
  if (kind == "bad-level") { bad$level <- as.character(bad$level); bad$level[1] <- "unknown" }
  if (kind == "missing-tier") bad <- bad[bad$tier != "Study", ]
  if (kind == "duplicate-id") bad$id[2] <- bad$id[1]
  stopifnot(rejected(bad))
}
stopifnot(rejected(s[FALSE, ]))
cat("Risk replacement-feed guards: 8 invalid cases rejected\n")

# Decimal weights near a threshold must not contradict the displayed integer.
edge <- s[1:2, ]; edge$tier <- "Study"; edge$level <- c("green", "red")
edge$weight <- c(74.6, 25.4)
stopifnot(tier_score(edge, "Study")$score == 25, tier_score(edge, "Study")$rag == "green")
edge$weight <- c(44.6, 55.4)
stopifnot(tier_score(edge, "Study")$score == 55, tier_score(edge, "Study")$rag == "amber")
edge$weight <- c(44.4, 55.6)
stopifnot(tier_score(edge, "Study")$score == 56, tier_score(edge, "Study")$rag == "red")

# A wrong explicit client input path must never fall back to the example.
stopifnot(inherits(try(risk_load(file.path(tempdir(), "missing-explicit-input-20261028")), silent = TRUE), "try-error"))
