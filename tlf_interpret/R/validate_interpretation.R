################################################################################
# validate_interpretation.R — deterministic guardrails (NOT the model).
# The core control: every number in the SLM draft must already exist in the
# deterministic FACTS, else the draft is REJECTED (hallucinated-number guard).
# Pure R, no reticulate — runs anywhere, including CI.
################################################################################

## --- number extraction ------------------------------------------------------
## Match signed/decimal numbers; a leading sign is only honoured when NOT
## preceded by a digit/dot, so range hyphens ("80-125") split into 80 and 125.
.NUM_RE <- "(?<![0-9.])[-+]?[0-9]+(?:\\.[0-9]+)?"

number_tokens <- function(text) {
  if (is.null(text) || !nzchar(text)) return(character(0))
  unlist(regmatches(text, gregexpr(.NUM_RE, text, perl = TRUE)), use.names = FALSE)
}
.decimals <- function(tok) if (grepl("\\.", tok)) nchar(sub(".*\\.", "", tok)) else 0L

## Collect every numeric value appearing in FACTS — numeric leaves AND numbers
## embedded in character values (e.g. a pre-formatted "12 (50.0%)").
collect_fact_numbers <- function(x) {
  if (is.null(x)) return(numeric(0))
  if (is.list(x))      return(unlist(lapply(x, collect_fact_numbers), use.names = FALSE))
  if (is.numeric(x))   return(as.numeric(x))
  if (is.character(x)) return(suppressWarnings(as.numeric(number_tokens(paste(x, collapse = " ")))))
  numeric(0)
}

## --- (1) numeric-consistency: every draft number must be a fact -------------
validate_numbers <- function(draft, facts, tol_abs = 1e-6) {
  fnums <- unique(collect_fact_numbers(facts)); fnums <- fnums[!is.na(fnums)]
  toks  <- number_tokens(draft)
  if (!length(toks)) return(list(ok = TRUE, n_checked = 0L, unmatched = character(0)))
  dnums <- suppressWarnings(as.numeric(toks))
  matched <- vapply(seq_along(toks), function(i) {
    d <- dnums[i]; dp <- .decimals(toks[i])
    if (is.na(d)) return(TRUE)
    any(abs(fnums - d) <= tol_abs) ||            # exact (float wobble)
      any(round(fnums, dp) == round(d, dp))      # equal at the draft's displayed precision
  }, logical(1))
  list(ok = all(matched), n_checked = length(toks), unmatched = unique(toks[!matched]))
}

## --- (2) claim guard: flag conclusions that need human judgement ------------
.FLAG_PATTERNS <- c(
  "well[ -]?tolerated", "\\bsafe\\b", "\\bsafety profile\\b", "no safety concern",
  "efficac", "\\beffective\\b", "superior", "benefit", "favou?rable",
  "caused? by", "due to (the )?(study )?(drug|treatment)", "attributable to",
  "consistent with .* (efficacy|benefit)")
validate_claims <- function(draft) {
  hits <- .FLAG_PATTERNS[vapply(.FLAG_PATTERNS,
            function(p) grepl(p, draft, ignore.case = TRUE, perl = TRUE), logical(1))]
  list(ok = length(hits) == 0, flagged = unname(hits))
}

## --- (3) template conformance -----------------------------------------------
validate_template <- function(draft, min_sent = 1L, max_sent = 6L, max_words = 130L) {
  words <- length(strsplit(trimws(draft), "\\s+")[[1]])
  sents <- length(regmatches(draft, gregexpr("[.!?](\\s|$)", draft))[[1]])
  issues <- c(
    if (!nzchar(trimws(draft)))      "empty draft",
    if (sents < min_sent)            sprintf("too few sentences (%d)", sents),
    if (sents > max_sent)            sprintf("too many sentences (%d)", sents),
    if (words > max_words)           sprintf("too long (%d words)", words))
  list(ok = length(issues) == 0, issues = issues, n_words = words, n_sent = sents)
}

## --- combine + status -------------------------------------------------------
validate_interpretation <- function(draft, facts) {
  num <- validate_numbers(draft, facts)
  cl  <- validate_claims(draft)
  tpl <- validate_template(draft)
  list(numbers = num, claims = cl, template = tpl,
       all_ok = num$ok && cl$ok && tpl$ok)
}

## REJECTED  = a hallucinated/altered number (hard fail — must not ship)
## FLAGGED   = numbers OK but risky claim / template issue (human must review)
## DRAFT_OK  = passed automated checks — still requires biostatistician SIGN-OFF
## (nothing is ever APPROVED automatically; APPROVED is set only by a human gate)
interpretation_status <- function(val, stub = FALSE) {
  if (!val$numbers$ok)                 return("REJECTED")      # hallucinated number
  if (stub)                            return("FLAGGED")       # stub draft, no real model
  if (!val$claims$ok || !val$template$ok) return("FLAGGED")
  "DRAFT_OK"
}
