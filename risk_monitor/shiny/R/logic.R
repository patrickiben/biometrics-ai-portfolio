# ---------------------------------------------------------------------------
# logic.R - pure roll-up scoring for the two-tier (participant and study) trial early-warning
# console. Operations-only, synthetic, no PHI, no participant-level data (the
# "participant tier" holds de-identified signal states, never records).
#
# The console flags; the SRC, the DSMB and the medical monitor decide.
# Reported safety numbers come from the validated safety database, never here.
# The advanced-engine signals use published methods (Optimal Transport /
# Wasserstein drift, Active Inference / free-energy) - flagged `advanced`.
# ---------------------------------------------------------------------------

TIERS <- c("Participant", "Study")
SEVERITY <- c(green = 0, amber = 50, red = 100)
TIER_WEIGHT <- c(Participant = 0.60, Study = 0.40)

# Reject incomplete feeds instead of turning missing/invalid signals into a
# low or undefined score. The displayed weights are operational heuristics.
risk_validate <- function(signals, require_both = FALSE) {
  fields <- c("tier", "id", "signal", "category", "level", "weight", "advanced", "detail")
  if (!is.data.frame(signals) || !nrow(signals) || anyDuplicated(names(signals)) || !all(fields %in% names(signals)))
    stop("Signals require nonempty rows and the documented CSV columns.")
  for (field in c("tier", "id", "signal", "category", "level", "detail"))
    if (anyNA(signals[[field]]) || any(!nzchar(trimws(as.character(signals[[field]])))))
      stop("Signal fields must not be missing or blank: ", field)
  if (anyDuplicated(signals$id)) stop("Signal IDs must be unique.")
  if (any(!signals$tier %in% TIERS) || (require_both && !setequal(unique(signals$tier), TIERS)))
    stop("A complete feed must include Participant and Study tiers only.")
  if (any(!as.character(signals$level) %in% names(SEVERITY))) stop("Signal levels must be green, amber or red.")
  if (!is.numeric(signals$weight) || any(!is.finite(signals$weight)) || any(signals$weight < 0))
    stop("Signal weights must be finite, nonnegative numbers.")
  if (any(vapply(split(signals$weight, signals$tier), function(x) sum(x) <= 0, logical(1))))
    stop("Each tier needs a positive total signal weight.")
  if (!is.logical(signals$advanced) || anyNA(signals$advanced)) stop("advanced must be TRUE or FALSE.")
  invisible(TRUE)
}

risk_load <- function(dir = NULL) {
  if (!is.null(dir) && (!is.character(dir) || length(dir) != 1 || is.na(dir) || !nzchar(dir)))
    stop("Supply one explicit input path, or omit it to use the bundled example.")
  cand <- if (!is.null(dir)) dir else c("data", "../data", "shiny/data", "risk_monitor/shiny/data")
  cand <- Filter(Negate(is.null), cand)
  base <- Find(function(d) file.exists(file.path(d, "signals.csv")), cand)
  if (is.null(base)) stop("Cannot find signals.csv")
  s <- utils::read.csv(file.path(base, "signals.csv"), stringsAsFactors = FALSE, check.names = FALSE)
  risk_validate(s, require_both = TRUE)
  s$level <- factor(s$level, levels = c("green", "amber", "red"))
  s$weight <- as.numeric(s$weight)
  s
}

rag_of <- function(score) ifelse(score > 55, "red", ifelse(score > 25, "amber", "green"))

# Weighted roll-up of one tier's signals to a 0..100 score + a RAG.
tier_score <- function(signals, tier) {
  risk_validate(signals)
  if (length(tier) != 1 || !tier %in% TIERS) stop("Unknown risk tier.")
  x <- signals[signals$tier == tier, ]
  if (!nrow(x)) stop("No signals available for the requested tier.")
  sev <- SEVERITY[as.character(x$level)]
  scaled_weight <- x$weight / max(x$weight)  # Avoid overflow for large but finite weights.
  # Apply the documented integer thresholds to the displayed rounded score,
  # as the overall score already does; 25 must not be shown as amber.
  score <- round(sum(sev * scaled_weight) / sum(scaled_weight))
  list(score = score, rag = rag_of(score), n = nrow(x),
       red = sum(x$level == "red"), amber = sum(x$level == "amber"))
}

risk_overall <- function(signals) {
  risk_validate(signals, require_both = TRUE)
  ts <- vapply(TIERS, function(t) tier_score(signals, t)$score, numeric(1))
  w <- TIER_WEIGHT[TIERS]
  score <- round(sum(ts * w) / sum(w))
  list(score = score, rag = rag_of(score),
       tiers = setNames(lapply(TIERS, function(t) tier_score(signals, t)), TIERS))
}

# The early-warning feed: every firing (non-green) signal, ranked red-first.
risk_feed <- function(signals) {
  risk_validate(signals)
  f <- signals[signals$level != "green", ]
  if (!nrow(f)) return(f)
  f <- f[order(f$level != "red", f$tier), ]
  f
}

risk_counts <- function(signals) {
  risk_validate(signals)
  list(total = nrow(signals),
       red = sum(signals$level == "red"),
       amber = sum(signals$level == "amber"),
       green = sum(signals$level == "green"),
       advanced = sum(as.logical(signals$advanced)))
}
