################################################################################
# extract_facts.R — deterministic fact extraction from a VALIDATED TLF result.
# Operates on the aggregate NUMERIC summary (the n's/%'s/geo-means the validated
# program already produced) — never on participant-level data, so no PHI reaches the
# model. Returns a flat named list of typed facts (numbers + short labels).
# No model here; this is plain R.
################################################################################

extract_facts <- function(tlf_id, result, ...) {
  fn <- switch(tlf_id,
    t_ae_overview      = facts_ae_overview,
    t_pk_param_summary = facts_pk_param_summary,
    stop("no fact extractor registered for '", tlf_id, "'"))
  fn(result, ...)
}

## AE overview: `result` = data.frame(category, n, pct) for ONE column (e.g. the
## active arm), already computed by the validated program (participants + %). `N` =
## that column's population denominator.
facts_ae_overview <- function(result, arm = "Active", N = NA_integer_) {
  g  <- function(cat) { v <- result$n  [match(cat, result$category)]; if (length(v)) v else NA }
  gp <- function(cat) { v <- result$pct[match(cat, result$category)]; if (length(v)) v else NA }
  list(
    arm            = arm,
    N              = as.integer(N),
    n_any_teae     = as.integer(g("Any TEAE")),
    pct_any_teae   = round(gp("Any TEAE"), 1),
    n_related_teae = as.integer(g("Related TEAE")),
    n_severe_teae  = as.integer(g("Severe TEAE")),
    n_sae          = as.integer(g("SAE")),
    n_teae_dc      = as.integer(g("TEAE leading to discontinuation")),
    n_deaths       = as.integer(g("Death")))
}

## PK parameters: `result` = data.frame(trt, param, n, geomean, geocv, median).
facts_pk_param_summary <- function(result, param = "CMAX", trt = "Test") {
  r <- result[result$param == param & result$trt == trt, , drop = FALSE]
  stopifnot(nrow(r) == 1L)
  list(parameter = param, treatment = trt,
       n        = as.integer(r$n),
       geomean  = signif(r$geomean, 4),
       geocv    = round(r$geocv, 1),
       median   = signif(r$median, 4))
}
