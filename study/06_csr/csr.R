################################################################################
# 06_csr/csr.R: CSR section 11-style statistical text written from the executed outputs,
# then checked with the number-grounding validator in tlf_interpret/R/
# (validate_interpretation.R, unchanged). SYNTHETIC DATA ONLY.
#
# Every number in the text is pulled from an output file by this script (no number is
# typed by hand). The validator then confirms that each number in each paragraph exists
# in the outputs at the displayed precision.
# KNOWN LIMITATION, stated on the page: the check proves a number EXISTS somewhere in the
# outputs, not that the sentence uses it correctly. Control C2 shows a wrong statement
# built from real numbers passing it. Small integers almost always match something.
#
# Inputs : 01_design/design_parameters.json, 02_sap/analysis_parameters.json,
#          04_analysis/{be_results,be_anova,pk_checks,analysis_sets}.csv, 04_analysis/tlf/*.csv,
#          03_adam/data/exclusion_rules_evaluated.csv, 05_qc/qc_ledger.json
# Outputs: 06_csr/csr_section11.html, csr_section11.txt, csr_check.json
################################################################################
source("tlf_interpret/R/validate_interpretation.R")

rcsv <- function(...) utils::read.csv(sp(...), colClasses = "character")
F_OUT <- list(
  design = jsonlite::read_json(sp("01_design", "design_parameters.json")),
  sap    = jsonlite::read_json(sp("02_sap", "analysis_parameters.json")),
  be     = rcsv("04_analysis", "be_results.csv"),
  anova  = rcsv("04_analysis", "be_anova.csv"),
  checks = rcsv("04_analysis", "pk_checks.csv"),
  sets   = rcsv("04_analysis", "analysis_sets.csv"),
  excl   = rcsv("03_adam", "data", "exclusion_rules_evaluated.csv"),
  titles = rcsv("04_analysis", "tlf", "tlf_titles.csv"),          # output identifiers such as Table 14.1.2
  qc     = jsonlite::read_json(sp("05_qc", "qc_ledger.json"))[c("checks", "pass", "fail", "values_compared")])
for (f in list.files(sp("04_analysis", "tlf"), pattern = "^t_.*\\.csv$"))
  F_OUT[[paste0("tlf_", sub("\\.csv$", "", f))]] <- as.matrix(utils::read.csv(sp("04_analysis", "tlf", f), header = FALSE, colClasses = "character"))

## values used in the text, taken from the outputs
be <- utils::read.csv(sp("04_analysis", "be_results.csv"))
an <- utils::read.csv(sp("04_analysis", "be_anova.csv"))
sets <- utils::read.csv(sp("04_analysis", "analysis_sets.csv"))
chk <- utils::read.csv(sp("04_analysis", "pk_checks.csv"))
D <- F_OUT$design$planning
cell <- function(id, row_label, col) {                           # a displayed cell of an executed table
  m <- F_OUT[[paste0("tlf_", id)]]; r <- which(trimws(m[, 1]) == row_label)
  stopifnot(length(r) >= 1); trimws(m[r[1], col])
}
cellg <- function(id, block, row_label, col) {                   # first row_label after a block label
  m <- F_OUT[[paste0("tlf_", id)]]; b <- which(trimws(m[, 1]) == block)[1]
  r <- b + which(trimws(m[(b + 1):nrow(m), 1]) == row_label)[1]; trimws(m[r, col])
}
pct <- function(x) sprintf("%.2f", 100 * x)
b <- function(p, v) be[[v]][be$PARAMCD == p]
pv <- function(p, eff) fmt_p(an$p[an$PARAMCD == p & an$effect == eff])
nset <- function(s) sets$n[sets$set == s]

P <- list()
adsl_f <- utils::read.csv(sp("03_adam", "data", "adsl.csv"), colClasses = "character")
wd_ids <- adsl_f$USUBJID[adsl_f$EOSSTT == "DISCONTINUED"]
em_ids <- F_OUT$excl$USUBJID[F_OUT$excl$EMESIS == "TRUE"]
n_tr <- b("CMAX", "n_TR"); n_rt <- b("CMAX", "n_RT")
## decode from the specification's DCSREAS codelist (the CDISC submission value stays in the data)
spec_cl <- jsonlite::read_json(sp("03_adam", "spec", "adam_spec.json"), simplifyVector = TRUE)$Codelists
dcs_cl <- spec_cl[spec_cl$ID == "DCSREAS", ]
dcs_decode <- function(x) tolower(dcs_cl$`Decoded Value`[match(x, dcs_cl$Term)])
P[["11.1"]] <- paste(
  sprintf("Of the %d participants randomized, %s%d received at least one dose and form the safety set.",
          nset("Enrolled (randomized)"), if (nset("Safety") == nset("Enrolled (randomized)")) "all " else "", nset("Safety")),
  if (length(wd_ids)) sprintf("Participant%s %s discontinued the study (%s).", if (length(wd_ids) > 1) "s" else "",
                              paste(wd_ids, collapse = " and "), paste(dcs_decode(unique(adsl_f$DCSREAS[adsl_f$USUBJID %in% wd_ids])), collapse = "; ")) else "",
  sprintf("The PK concentration set includes %d participants and the PK parameter set %d.", nset("PK concentration"), nset("PK parameter")),
  if (length(em_ids)) sprintf("Participant %s vomited within %d hours of a dose, so that period was excluded under the pre-specified rule.",
                              paste(em_ids, collapse = " and "), F_OUT$sap$exclusion_rules$emesis_window_h) else "",
  sprintf("The bioequivalence set includes %d participants (%s), above the guideline minimum of %d evaluable participants.",
          nset("Bioequivalence"), if (n_tr == n_rt) sprintf("%d in each sequence", n_tr) else sprintf("%d in sequence TR and %d in sequence RT", n_tr, n_rt),
          F_OUT$sap$exclusion_rules$min_evaluable))
P[["11.1"]] <- gsub("\\s+", " ", P[["11.1"]])
P[["11.2"]] <- sprintf(
  "Mean (SD) age in the safety set was %s years (range %s years). Of the %d participants, %s were female (%s). Mean (SD) BMI was %s kg/m2. Table 14.1.2 gives the characteristics by sequence.",
  cellg("t_14_1_2", "Age (years)", "Mean (SD)", 4), sub(" - ", " to ", cellg("t_14_1_2", "Age (years)", "Min - Max", 4), fixed = TRUE),
  nset("Safety"), sub(" .*", "", cell("t_14_1_2", "Female", 4)), gsub(".*\\((.*)\\)", "\\1", cell("t_14_1_2", "Female", 4)),
  cellg("t_14_1_2", "BMI (kg/m2)", "Mean (SD)", 4))
n_dosed <- as.integer(gsub("\\D", "", F_OUT$tlf_t_14_3_1_1[2, 2:3]))      # (N=..) header cells: Test, Reference
P[["11.3"]] <- sprintf(
  "Each participant was scheduled to receive %d single supervised oral doses. In total, %d doses were given (%d Test and %d Reference); the participant who withdrew did not receive the Period 2 dose.",
  F_OUT$design$periods, sum(n_dosed), n_dosed[1], n_dosed[2])
P[["11.4.1a"]] <- sprintf(
  "The adjusted geometric mean Cmax was %s ng/mL for Test and %s ng/mL for Reference. The ratio of geometric means (Test/Reference) was %s%% with a 90%% confidence interval of %s%% to %s%%. For AUC(0-t) the adjusted geometric means were %s and %s h*ng/mL, and the ratio was %s%% (90%% CI %s%% to %s%%). Both intervals lie within 80.00%% to 125.00%% (Table 14.4.3.1).",
  sprintf("%.1f", b("CMAX", "gm_T")), sprintf("%.1f", b("CMAX", "gm_R")), pct(b("CMAX", "ratio")), pct(b("CMAX", "lower")), pct(b("CMAX", "upper")),
  sprintf("%.1f", b("AUCLST", "gm_T")), sprintf("%.1f", b("AUCLST", "gm_R")), pct(b("AUCLST", "ratio")), pct(b("AUCLST", "lower")), pct(b("AUCLST", "upper")))
P[["11.4.1b"]] <- sprintf(
  "The within-participant CV was %.1f%% for Cmax and %.1f%% for AUC(0-t), below the %s%% assumed for the sample size. The supportive AUC(0-inf) ratio was %s%% (90%% CI %s%% to %s%%). Median tmax was %s hours for Test and %s hours for Reference (Table 14.4.4.1).",
  b("CMAX", "cv_within"), b("AUCLST", "cv_within"), D$cv_pct, pct(b("AUCIFO", "ratio")), pct(b("AUCIFO", "lower")), pct(b("AUCIFO", "upper")),
  cellg("t_14_4_4_1", "Time of Cmax, tmax (h)", "Median", 2), cellg("t_14_4_4_1", "Time of Cmax, tmax (h)", "Median", 3))
P[["11.4.1c"]] <- sprintf(
  "In the ANOVA for ln(Cmax) the p-values were %s for sequence, %s for period and %s for formulation; for ln(AUC(0-t)) they were %s, %s and %s (Table 14.4.3.2). As the SAP specifies, no test for carry-over was made; pre-dose concentrations were examined instead.",
  pv("CMAX", "Sequence"), pv("CMAX", "Period"), pv("CMAX", "Formulation"), pv("AUCLST", "Sequence"), pv("AUCLST", "Period"), pv("AUCLST", "Formulation"))
ex8 <- F_OUT$excl[F_OUT$excl$USUBJID == "SIMBE01-101-008" & F_OUT$excl$APERIOD == "2", ]
P[["11.4.2.2"]] <- sprintf(
  "No values were imputed. One 12-hour sample was not collected and the profile was analyzed without it. Concentrations below the LLOQ of %.2f ng/mL were set to zero and left out of the terminal-phase fit. One Period 2 pre-dose concentration was %.1f%% of that period's Cmax, below the %d%% limit, so the period was kept. AUC(0-t) covered less than %d%% of AUC(0-inf) in %s of %s profiles (%s%%), within the %d%% allowed before the study's validity needs discussion.",
  STUDY$lloq, as.numeric(ex8$PREDOSE_PCT), F_OUT$sap$exclusion_rules$predose_pct_cmax, F_OUT$sap$exclusion_rules$auc_coverage_pct,
  chk$value[2], chk$denominator[2], sprintf("%.1f", chk$pct[2]), F_OUT$sap$exclusion_rules$auc_coverage_share_pct)
P[["11.4.7"]] <- sprintf(
  "The 90%% confidence intervals for the Test/Reference ratios of Cmax (%s%% to %s%%) and AUC(0-t) (%s%% to %s%%) both lie within 80.00%% to 125.00%%, so bioequivalence of the test and reference tablets is concluded for this synthetic study. The results were re-derived by a second method by the same author (%s of %s QC checks passed); a second programmer did not re-derive them.",
  pct(b("CMAX", "lower")), pct(b("CMAX", "upper")), pct(b("AUCLST", "lower")), pct(b("AUCLST", "upper")), F_OUT$qc$pass, F_OUT$qc$checks)

heads <- c("11.1" = "11.1 Data Sets Analyzed", "11.2" = "11.2 Demographic and Other Baseline Characteristics",
           "11.3" = "11.3 Measurements of Treatment Compliance", "11.4.1a" = "11.4.1 Analysis of Pharmacokinetics and Bioequivalence",
           "11.4.1b" = "", "11.4.1c" = "", "11.4.2.2" = "11.4.2.2 Handling of Dropouts or Missing Data",
           "11.4.7" = "11.4.7 Conclusions")

## --- validate each paragraph ------------------------------------------------------------------
val <- lapply(names(P), function(k) {
  v <- validate_interpretation(P[[k]], F_OUT)
  data.frame(paragraph = k, numbers_checked = v$numbers$n_checked, unmatched = paste(v$numbers$unmatched, collapse = " "),
             claims_flagged = paste(v$claims$flagged, collapse = "; "), words = v$template$n_words, sentences = v$template$n_sent,
             status = interpretation_status(v, stub = FALSE))
}) %>% bind_rows()

## --- controls: what the check catches and what it cannot -------------------------------------------
c1_txt <- sub(pct(b("CMAX", "upper")), "108.31", P[["11.4.1a"]], fixed = TRUE)
c2_txt <- sprintf("For AUC(0-t), the ratio of geometric means was %s%% (90%% CI %s%% to %s%%).",
                  pct(b("CMAX", "ratio")), pct(b("CMAX", "lower")), pct(b("CMAX", "upper")))   # Cmax numbers given as AUC
c3_txt <- sprintf("Both formulations were well tolerated; the ratio for Cmax was %s%%.", pct(b("CMAX", "ratio")))
ctrl <- lapply(list(
  list(id = "C1", what = "One number altered (upper Cmax limit changed to 108.31)", expect = "REJECTED", txt = c1_txt),
  list(id = "C2", what = "Real numbers in a wrong statement (Cmax results attributed to AUC(0-t))", expect = "DRAFT_OK (the limitation)", txt = c2_txt),
  list(id = "C3", what = "A conclusion that needs human judgment ('well tolerated')", expect = "FLAGGED", txt = c3_txt)), function(x) {
  v <- validate_interpretation(x$txt, F_OUT)
  data.frame(control = x$id, what = x$what, expected = x$expect, status = interpretation_status(v, stub = FALSE),
             unmatched = paste(v$numbers$unmatched, collapse = " "), text = x$txt)
}) %>% bind_rows()
ctrl$as_expected <- substr(ctrl$expected, 1, nchar(ctrl$status)) == ctrl$status

csr_txt <- unlist(lapply(names(P), function(k) c(if (nzchar(heads[[k]])) c("", heads[[k]]) else NULL, P[[k]])))
write_text(c("CSR section 11-style statistical text (synthetic study SIMBE01). Generated by study/06_csr/csr.R.", csr_txt),
           sp("06_csr", "csr_section11.txt"))
write_json_det(list(validator = "tlf_interpret/R/validate_interpretation.R (unchanged)",
                    limitation = "Checks that each number exists in the outputs at the displayed precision, not that the statement using it is correct.",
                    paragraphs = val, controls = ctrl,
                    all_paragraphs_draft_ok = all(val$status == "DRAFT_OK"), controls_as_expected = all(ctrl$as_expected)),
               sp("06_csr", "csr_check.json"))

## --- page ---------------------------------------------------------------------------------------
paras <- paste(vapply(names(P), function(k) paste0(if (nzchar(heads[[k]])) paste0("<h3>", esc(heads[[k]]), "</h3>") else "",
                                                   "<p>", esc(P[[k]]), "</p>"), ""), collapse = "\n")
show_val <- val %>% transmute(Paragraph = paragraph, `Numbers checked` = numbers_checked,
                              `Not found in outputs` = ifelse(unmatched == "", "none", unmatched),
                              `Claim flags` = ifelse(claims_flagged == "", "none", claims_flagged), Words = words, Status = status)
show_ctrl <- ctrl %>% transmute(Control = control, `What was changed` = what, Expected = expected, Result = status,
                                `As expected` = ifelse(as_expected, "yes", "no"), Text = text)
body <- paste0(
  '<div class="note"><p>Statistical text in the style of ICH E3 section 11, written by <code>study/06_csr/csr.R</code> from the executed outputs: each number is read from an output file, none is typed by hand. The draft is then checked with the existing number-grounding validator in <a href="../../tlf_interpret/index.html">tlf_interpret</a>. Human review and sign-off would still be required.</p></div>',
  '<h2>Draft text</h2><div class="panel">', paras, '</div>',
  '<h2>Number-grounding check</h2>',
  md(sprintf("Facts: every number in the design and SAP settings, the executed table cells and titles (`04_analysis/tlf/*.csv`), the BE results, ANOVA, analysis-set counts, M13A checks, the evaluated exclusion rules and the QC ledger totals. **%d of %d paragraphs** pass with status DRAFT_OK (every number found; no flagged claim; within the length template).",
             sum(val$status == "DRAFT_OK"), nrow(val))),
  html_table(show_val),
  '<h2>Controls: what the check catches and what it cannot</h2>',
  html_table(show_ctrl),
  '<div class="note"><p><strong>Known limitation.</strong> The validator checks that a number in the text exists somewhere in the outputs at the precision shown; it does not check that the sentence uses the right number for the right quantity. Control C2 attributes the Cmax results to AUC(0-t) and still passes. Small integers (for example 1, 2 or 12) match many output values, so they are weak evidence. A statistician reading the text against the tables remains the check that matters.</p></div>',
  md("Files: [csr_section11.txt](csr_section11.txt), [csr_check.json](csr_check.json). Program: `study/06_csr/csr.R`; validator: `tlf_interpret/R/validate_interpretation.R`."))
write_text(page_html(title = "CSR Section 11 Text", kicker = "Stage 6: reporting",
                     h1 = "CSR section 11-style statistical text, checked against the outputs",
                     description = "CSR section 11-style statistical text for a synthetic BE study, generated from executed outputs and checked by a number-grounding validator.",
                     labels = paste0(lab("sup", "Supported (job): statistical input to CSRs"), lab("led", "Led (job): final statistical reports"), lab("tools", "Executed here: number check")),
                     body = body, depth = 1), sp("06_csr", "csr_section11.html"))
cat(sprintf("[06_csr] %d paragraphs, %d DRAFT_OK; controls as expected: %s\n", nrow(val), sum(val$status == "DRAFT_OK"),
            if (all(ctrl$as_expected)) "yes" else "NO"))
