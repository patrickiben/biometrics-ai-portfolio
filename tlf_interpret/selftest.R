#!/usr/bin/env Rscript
################################################################################
# selftest.R — proves the guardrails WITHOUT a model (pure R validators).
# Run: Rscript selftest.R
################################################################################
source("R/validate_interpretation.R")
source("R/extract_facts.R")

## A synthetic VALIDATED AE-overview result (what the TLF program would emit)
ae_result <- data.frame(
  category = c("Any TEAE","Related TEAE","Severe TEAE","SAE",
               "TEAE leading to discontinuation","Death"),
  n   = c(24L, 15L, 2L, 1L, 0L, 0L),
  pct = c(80.0, 50.0, 6.7, 3.3, 0.0, 0.0))
facts <- extract_facts("t_ae_overview", ae_result, arm = "Active 100 mg", N = 30L)

cat("FACTS:\n"); str(facts)

## (a) faithful draft — every number is a fact
good <- paste("Among the 30 participants in the Active 100 mg arm, 24 (80.0%) reported",
              "at least one treatment-emergent adverse event and 15 were considered",
              "related. There was 1 serious adverse event, no discontinuations, and",
              "no deaths.")

## (b) hallucinated draft — invents 27 / 90.0% / 3 deaths (none in facts)
bad <- paste("Among the 30 participants, 27 (90.0%) reported a treatment-emergent adverse",
             "event and the drug was generally well tolerated; there were 3 deaths.")

vg <- validate_interpretation(good, facts); sg <- interpretation_status(vg)
vb <- validate_interpretation(bad,  facts); sb <- interpretation_status(vb)

cat("\n[A] faithful draft -> status:", sg,
    "| numbers ok:", vg$numbers$ok, "| claims ok:", vg$claims$ok, "\n")
cat("[B] hallucinated draft -> status:", sb,
    "| unmatched numbers:", paste(vb$numbers$unmatched, collapse = ", "),
    "| flagged claims:", paste(vb$claims$flagged, collapse = "; "), "\n\n")

ok <- sg == "DRAFT_OK" &&
      sb == "REJECTED" &&
      setequal(vb$numbers$unmatched, c("27","90.0","3")) &&
      length(vb$claims$flagged) >= 1
cat(if (ok) "SELFTEST PASS\n" else "SELFTEST FAIL\n")
quit(status = if (ok) 0L else 1L)
