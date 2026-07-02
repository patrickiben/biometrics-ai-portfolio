################################################################################
# interpret.R — orchestrator: facts -> SLM draft -> validate -> status + audit.
# Nothing here is ever "APPROVED"; that is a human gate downstream.
################################################################################
if (!exists("slm_complete"))          source(file.path("R", "slm_client.R"))
if (!exists("validate_interpretation")) source(file.path("R", "validate_interpretation.R"))

## System prompt — the model is constrained to RESTATE facts, not conclude.
INTERPRET_SYSTEM <- paste(
  "You are a biostatistics writing assistant drafting the interpretation text",
  "that accompanies a clinical study Table/Listing/Figure. STRICT RULES:",
  "(1) Use ONLY the numbers given in FACTS; never invent, compute, or alter a number.",
  "(2) Write 2-4 plain, factual sentences describing what the table shows.",
  "(3) Do NOT state efficacy, safety, causal, or 'well tolerated' conclusions.",
  "(4) Use digits for numbers (e.g. '12', not 'twelve').",
  "(5) Always write 'participant'/'participants', never 'subject'/'subjects'.",
  "Output only the paragraph, no preamble.")

.fmt1 <- function(x) if (is.numeric(x)) format(x, trim = TRUE, scientific = FALSE) else as.character(x)

build_prompt <- function(tlf_id, facts) {
  kv <- paste(sprintf("- %s: %s", names(facts), vapply(facts, .fmt1, character(1))),
              collapse = "\n")
  paste0("TLF: ", tlf_id,
         "\nFACTS (these are the ONLY numbers you may use):\n", kv,
         "\n\nWrite the interpretation paragraph.")
}

## House-style normalization: CDISC deliverables say "participant", not "subject".
## Belt-and-suspenders with system rule 5; \\b protects CDISC USUBJID/SUBJID.
.normalize_terms <- function(txt) {
  if (is.null(txt) || !nzchar(txt)) return(txt)
  txt <- gsub("\\bSubjects\\b", "Participants", txt); txt <- gsub("\\bsubjects\\b", "participants", txt)
  txt <- gsub("\\bSubject\\b",  "Participant",  txt); txt <- gsub("\\bsubject\\b",  "participant",  txt)
  txt
}

## Full pipeline for one TLF. Returns the draft, validation, status, and a
## complete audit record (model digest, seed, prompt/facts hashes, timestamps).
interpret_tlf <- function(tlf_id, facts, cfg = slm_config()) {
  prompt <- build_prompt(tlf_id, facts)
  draft  <- slm_complete(prompt, system = INTERPRET_SYSTEM, facts = facts, cfg = cfg)
  draft$text <- .normalize_terms(draft$text)        # house style: "participant", never "subject"
  val    <- validate_interpretation(draft$text, facts)
  status <- interpretation_status(val, stub = isTRUE(draft$meta$stub))
  list(
    tlf_id     = tlf_id,
    facts      = facts,
    draft      = draft$text,
    validation = val,
    status     = status,                       # REJECTED | FLAGGED | DRAFT_OK
    approved   = FALSE,                         # set TRUE only by the human gate
    audit      = c(draft$meta, list(status = status, prompt = prompt,
                   validated_at = format(Sys.time(), tz = "UTC", usetz = TRUE))))
}

`%||%` <- function(a, b) if (is.null(a)) b else a
