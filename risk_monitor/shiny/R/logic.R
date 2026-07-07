# ---------------------------------------------------------------------------
# logic.R - pure roll-up scoring for the 3-tier Trial-Termination Early-Warning
# console. Operations-only, synthetic, no PHI, no participant-level data (the
# "participant tier" holds de-identified signal states, never records).
#
# The AI flags; the SRC / DSMB / medical monitor / PM / account lead decide.
# Reported safety numbers come from the validated safety database, never here.
# The advanced-engine signals use published methods (Optimal Transport /
# Wasserstein drift, Active Inference / free-energy) - flagged `advanced`.
# ---------------------------------------------------------------------------

TIERS <- c("Participant", "Study", "Client")
SEVERITY <- c(green = 0, amber = 50, red = 100)
TIER_WEIGHT <- c(Participant = 0.50, Study = 0.30, Client = 0.20)

risk_load <- function(dir = NULL) {
  cand <- c(dir, "data", "../data", "shiny/data", "risk_monitor/shiny/data")
  cand <- Filter(Negate(is.null), cand)
  base <- Find(function(d) file.exists(file.path(d, "signals.csv")), cand)
  if (is.null(base)) stop("Cannot find signals.csv")
  s <- utils::read.csv(file.path(base, "signals.csv"), stringsAsFactors = FALSE)
  s$level <- factor(s$level, levels = c("green", "amber", "red"))
  s$weight <- as.numeric(s$weight)
  s
}

rag_of <- function(score) ifelse(score > 55, "red", ifelse(score > 25, "amber", "green"))

# Weighted roll-up of one tier's signals to a 0..100 score + a RAG.
tier_score <- function(signals, tier) {
  x <- signals[signals$tier == tier, ]
  if (!nrow(x)) return(list(score = 0, rag = "green", n = 0, red = 0, amber = 0))
  sev <- SEVERITY[as.character(x$level)]
  score <- sum(sev * x$weight) / sum(x$weight)
  list(score = round(score), rag = rag_of(score), n = nrow(x),
       red = sum(x$level == "red"), amber = sum(x$level == "amber"))
}

risk_overall <- function(signals) {
  ts <- vapply(TIERS, function(t) tier_score(signals, t)$score, numeric(1))
  w <- TIER_WEIGHT[TIERS]
  score <- round(sum(ts * w) / sum(w))
  list(score = score, rag = rag_of(score),
       tiers = setNames(lapply(TIERS, function(t) tier_score(signals, t)), TIERS))
}

# The early-warning feed: every firing (non-green) signal, ranked red-first.
risk_feed <- function(signals) {
  f <- signals[signals$level != "green", ]
  if (!nrow(f)) return(f)
  f <- f[order(f$level != "red", f$tier), ]
  f
}

risk_counts <- function(signals) {
  list(total = nrow(signals),
       red = sum(signals$level == "red"),
       amber = sum(signals$level == "amber"),
       green = sum(signals$level == "green"),
       advanced = sum(as.logical(signals$advanced)))
}
