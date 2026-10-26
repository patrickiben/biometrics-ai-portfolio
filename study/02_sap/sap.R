################################################################################
# 02_sap/sap.R: SAP statistical-methods excerpt, mock shells, and the machine-readable
# analysis settings that the analysis programs read. SYNTHETIC STUDY.
#
# Inputs : 01_design/design_parameters.json
# Outputs: 02_sap/analysis_parameters.json, sap_excerpt.html, mock_shells.html
################################################################################
out <- function(f) sp("02_sap", f)
DESIGN <- jsonlite::read_json(sp("01_design", "design_parameters.json"))

## --- the settings the analysis programs read (one source of truth) ------------------
SAP <- list(
  study = STUDY$studyid, synthetic = TRUE,
  ci_level = 0.90, be_lower = 0.80, be_upper = 1.25,
  be_rule = "both primary parameters: 90% CI of the T/R geometric mean ratio within 80.00% to 125.00%, judged on unrounded limits",
  primary_params = c("CMAX", "AUCLST"),
  secondary_params = c("AUCIFO", "TMAX", "LAMZHL", "LAMZ", "AUCPEO"),
  model = "ln(AVAL) ~ sequence + participant(sequence) + period + formulation (fixed effects, GLM)",
  nca = list(
    engine = "PKNCA",
    auc_method = "lin up/log down",
    conc_blq = list(first = "keep", middle = "keep", last = "keep"),
    blq_value = 0,
    time_variable = "ARRLT (actual time from the period's dose); pre-dose samples set to time 0",
    min_hl_points = 3,
    allow_tmax_in_half_life = FALSE,
    lambda_z_selection = "largest number of points whose adjusted R-squared is within 1e-4 of the best (PKNCA default)",
    zero_segment = "linear trapezoid for a segment that starts or ends at a zero (BLQ) concentration; log-down only when both concentrations are positive",
    ## parameter rules, applied with PKNCA exclude(); excluded values stay in ADPP with NCAEXRSN set
    min_hl_adj_r_squared = 0.9,
    min_hl_adj_r_squared_rule = "lambda z, t1/2, AUC(0-inf) and the extrapolated percentage are not summarized or analyzed when the adjusted R-squared of the terminal fit is below 0.90",
    max_aucinf_pext_pct = 20,
    max_aucinf_pext_rule = "AUC(0-inf) is not summarized or analyzed when more than 20% of it is extrapolated; the extrapolated percentage itself is still summarized"
  ),
  exclusion_rules = list(
    emesis_window_h = 2, emesis_rule = "period excluded if emesis occurs within 2 h of dosing (twice the expected median tmax of 1 h); a protocol violation documented when it happens, before bioanalysis (ICH M13A 2.2.1)",
    predose_pct_cmax = 5, predose_rule = "period excluded if the pre-dose concentration is above 5% of that period's Cmax; applied to the bioanalytical results (ICH M13A 2.2.3.3)",
    low_exposure_pct = 5, low_exposure_rule = "period may be excluded if its AUC is below 5% of the product's geometric mean AUC calculated without the participant, at most 1 participant expected; applied to the bioanalytical results (ICH M13A 2.2.1.1)",
    min_evaluable = 12,
    auc_coverage_pct = 80, auc_coverage_share_pct = 20,
    first_point_cmax_rule = "participants whose Cmax is at the first post-dose sample in either period are removed in a supplementary analysis; the primary analysis keeps them (ICH M13A 2.1.8.1)"
  ),
  summary_stats = c("n", "arithmetic mean", "SD", "CV%", "geometric mean", "geometric CV%", "median", "minimum", "maximum"),
  conventions = list(geometric_mean = "exp(mean(log x))", geometric_cv = "100*sqrt(exp(s^2_log) - 1)",
                     within_cv = "100*sqrt(exp(MSE) - 1)", tmax = "median (minimum, maximum)")
)
write_json_det(SAP, out("analysis_parameters.json"))

## --- SAP excerpt ---------------------------------------------------------------------
ice <- data.frame(
  `Intercurrent event` = c("Emesis within 2 h of dosing", "Withdrawal before the second period",
                           "Pre-dose concentration above 5% of the period's Cmax", "Period AUC below 5% of the product's geometric mean AUC",
                           "Prohibited medication that could change exposure"),
  Strategy = c("Hypothetical", "Hypothetical", "Hypothetical", "Hypothetical", "Hypothetical"),
  `How it is implemented` = c("The period's PK parameters are excluded (ADPP ANL01FL not Y; PKEXRSN gives the reason)",
                              "The participant contributes one period and leaves the bioequivalence set (ADSL BEFL = N)",
                              "The period is excluded from the primary analysis (ICH M13A 2.2.3.3, carry-over)",
                              "The period may be excluded; at most one participant per study is expected (ICH M13A 2.2.1.1)",
                              "The period is excluded if the medication is judged to affect exposure (not exercised: no concomitant medications were simulated)"),
  `When the rule is applied` = c("Documented when it happens, before bioanalysis (ICH M13A 2.2.1)",
                                 "Documented when it happens, before bioanalysis (ICH M13A 2.2.1)",
                                 "After bioanalysis: needs the measured concentrations",
                                 "After bioanalysis: needs the measured concentrations",
                                 "Documented when it happens, before bioanalysis (ICH M13A 2.2.1)"),
  check.names = FALSE)
strategies <- data.frame(
  `E9(R1) strategy` = c("Treatment policy", "Hypothetical", "Composite variable", "While on treatment", "Principal stratum"),
  `Used here` = c("No", "Yes", "No", "No", "No"),
  Reason = c("Would fold events unrelated to the formulations (for example emesis) into the formulation comparison",
             "Targets exposure had the event not occurred; matches the pre-specified M13A rules for removing periods (2.2.1, 2.2.1.1, 2.2.3.3)",
             "The variable is a continuous exposure measure; no event outcome is combined with it",
             "Single doses; there is no treatment duration to truncate",
             "The target population is all eligible participants, not a stratum defined by a post-randomization event"),
  check.names = FALSE)
sets <- data.frame(
  `Analysis set` = c("Enrolled", "Safety", "PK concentration", "PK parameter", "Bioequivalence"),
  `ADaM flag` = c("ADSL.RANDFL", "ADSL.SAFFL", "ADSL.PKCFL", "ADSL.PKPFL", "ADSL.BEFL"),
  Definition = c("Randomized", "Received at least one dose", "Safety set and at least one quantifiable post-dose concentration",
                 "At least one profile with evaluable Cmax and AUC(0-t) and no exclusion",
                 "Evaluable Cmax and AUC(0-t) after both T and R, after exclusions"),
  `Used for` = c("Disposition", "Demographics, adverse events", "Concentration summaries and figures", "PK parameter summaries", "Bioequivalence analysis"),
  check.names = FALSE)

body <- paste0(
'<div class="note"><p>Excerpt of the statistical methods of a statistical analysis plan (SAP) for the synthetic study SIMBE01. The numerical settings in this plan (acceptance limits, exclusion thresholds and NCA options) are also written to <a href="analysis_parameters.json">analysis_parameters.json</a>, which the analysis programs read, so a change to a setting reaches the code and this plan together.</p></div>',
md(
"## 1 Estimand (ICH E9(R1))",
"",
"| Attribute | Primary estimand |",
"|---|---|",
"| Treatment | One 100 mg tablet of the test product (T) and of the reference product (R; the comparator in ICH M13A terms), fasting, in a 2x2 crossover with a 14-day washout |",
"| Population | Healthy adults meeting the protocol's eligibility criteria |",
"| Variable | Cmax and AUC(0-t) of SIMDRUG in plasma from actual sampling times |",
"| Intercurrent events | Handled with a hypothetical strategy; see the table below |",
"| Population-level summary | Ratio of geometric means T/R with a two-sided 90% confidence interval; bioequivalence if both intervals lie within 80.00% to 125.00% |",
"",
"ICH E9(R1) was adopted at Step 4 on 20 Nov 2019 (FDA final guidance May 2021). It lists five strategies for intercurrent events; the table after the next one says which one is used and why."),
html_table(ice, caption = "Intercurrent events and their handling. Every rule is pre-specified in the protocol and this plan (ICH M13A 2.2.1.1). Events such as emesis are documented when they happen, before any concentration is known; the carry-over and very-low-exposure rules can only be applied to the bioanalytical results."),
html_table(strategies, caption = "The five ICH E9(R1) strategies and why only one applies here."),
md("## 2 Analysis sets"),
html_table(sets),
md(
"## 3 Pharmacokinetic parameters",
"",
"Parameters come from non-compartmental analysis (NCA) with PKNCA 0.12.1 on **actual** sampling times relative to each period's dose (ADPC.ARRLT). Pre-dose samples are assigned time 0. The NCA settings follow ICH M13A (Step 4 23 Jul 2024; FDA final 30 Oct 2024; EU effective 25 Jan 2025):",
"",
"- AUC by the linear-up/log-down trapezoidal method (M13A gives the linear trapezoidal method as an example and asks that the method be reported). The log-down rule applies only when both concentrations are positive; a segment that starts or ends at a zero (BLQ) concentration uses the linear trapezoid, as PKNCA does.",
"- Concentrations below the LLOQ (0.50 ng/mL) are treated as zero wherever they fall in the profile (ICH M13A 2.2.2.2): `PKNCA.options(conc.blq = list(first = \"keep\", middle = \"keep\", last = \"keep\"))`. PKNCA treats a kept BLQ value as zero. This changes the PKNCA default, which drops BLQ values in the middle of a profile. One simulated profile has a BLQ result between quantifiable samples, and the analysis page shows how much the choice changes its AUC(0-t).",
"- BLQ values are omitted from the terminal rate constant: PKNCA excludes zeros from the log-linear fit.",
"- The terminal phase uses at least 3 points after tmax, chosen by adjusted R-squared (PKNCA defaults `min.hl.points = 3`, `allow.tmax.in.half.life = FALSE`).",
"- Primary: Cmax and AUC(0-t) (AUC to the last quantifiable concentration). Additional: AUC(0-inf), AUC(0-t)/AUC(0-inf), tmax, the terminal rate constant (lambda z) and t1/2.",
"- Parameter rules: lambda z, t1/2, AUC(0-inf) and the extrapolated percentage are not summarized or analyzed when the adjusted R-squared of the terminal fit is below 0.90; AUC(0-inf) is not summarized or analyzed when more than 20% of it is extrapolated (the extrapolated percentage itself is still summarized). They are applied with PKNCA `exclude()`, with a rule function that flags every parameter that depends on lambda z (`get.parameter.deps(\"half.life\")`) or AUC(0-inf) alone. The values stay in ADPP, with ANL01FL and ANL02FL not Y and NCAEXRSN giving the rule.",
"- AUC(0-t) should cover at least 80% of AUC(0-inf). If coverage is below 80% in more than 20% of profiles, the report discusses the study's validity (ICH M13A 2.2.2.2). This check counts every evaluable profile, including those whose AUC(0-inf) is not summarized under the 20% rule.",
"- Summary statistics: n, arithmetic mean, SD, CV%, geometric mean, geometric CV%, median, minimum and maximum; tmax as median (minimum, maximum). Geometric mean = exp(mean(log x)); geometric CV% = 100*sqrt(exp(s^2) - 1) on the log scale.",
"- Individual profiles are plotted against actual times; mean profiles against nominal times (ICH M13A).",
"",
"## 4 Bioequivalence model",
"",
"For each primary parameter, on the bioequivalence set:",
"",
"```",
"lm(log(AVAL) ~ SEQUENCE + USUBJID + PERIOD + TRTA)      # USUBJID nested in SEQUENCE",
"```",
"",
"- Fixed effects for sequence, participant within sequence, period and formulation (a general linear model, as ICH M13A allows).",
"- The ANOVA table reports all four effects. Sequence is tested against the participant-within-sequence mean square; participant within sequence, period and formulation are tested against the residual mean square. Sequence and participant-within-sequence sums of squares are sequential; period and formulation sums of squares are adjusted for every other term (so the table matches a Type III table when the sequences are unequal in size).",
"- The T minus R difference of least-squares means and its 90% confidence interval use the residual mean square with its degrees of freedom; the limits are exponentiated to a ratio. The decision uses the unrounded limits; the tables show two decimals.",
"- Within-participant CV% = 100*sqrt(exp(MSE) - 1).",
"- No carry-over test (ICH M13A). Carry-over is addressed by the pre-dose concentration rule.",
"- Supportive AUC(0-inf) analysis: the same model, on participants in the bioequivalence set whose AUC(0-inf) passes the parameter rules in both periods.",
"- Supplementary analysis 1 (ICH E9(R1) term): the same model with the excluded periods put back, for participants who have both periods. It changes how the intercurrent events are handled, so it is supplementary, not a sensitivity analysis of the primary estimand.",
"- Supplementary analysis 2 (ICH M13A 2.1.8.1): the same model without the participants whose Cmax is at the first post-dose sample (0.25 h) in either period, since their true Cmax may have come earlier. The report discusses whether the conclusion depends on them.",
"",
"## 5 Missing data and values below the LLOQ",
"",
"- No imputation. A missed sample is omitted and the profile is analyzed with the remaining samples; the listing flags it.",
"- BLQ values are zero in PK calculations and omitted from lambda z (ICH M13A). Concentration summaries by nominal time also use zero for BLQ and report how many values were BLQ.",
"- A participant without evaluable primary parameters for both products leaves the bioequivalence set (ICH M13A: the primary analysis includes all participants with evaluable data for both products). At least 12 evaluable participants are required for the study to be acceptable.",
"",
"## 6 Safety",
"",
sprintf("Treatment-emergent adverse events (onset on or after the first dose) are assigned to the treatment taken most recently before onset. Each participant counts once per row; the denominator is the number of participants exposed to that treatment. Coding: MedDRA, version set at study start: %s, the version current when this synthetic study started.", STUDY$dict_meddra),
"",
"## 7 Outputs",
"",
"Mock shells for every planned output are on the [mock shells page](mock_shells.html): Table 14.1.2 demographics, 14.3.1.1 adverse-event overview, 14.4.1.1 concentration summary, 14.4.4.1 PK parameter summary, 14.4.3.1 bioequivalence results and 14.4.3.2 the ANOVA effects table. The executed versions are in the [analysis stage](../04_analysis/index.html).")
)
write_text(page_html(
  title = "SAP Excerpt", kicker = "Stage 2: statistical analysis plan",
  h1 = "SAP statistical methods: estimand, analysis sets and the BE model",
  description = "Statistical analysis plan excerpt for a synthetic 2x2 bioequivalence study: E9(R1) estimand, analysis sets, the ICH M13A model, BLQ and missing-data rules.",
  labels = paste0(lab("tools", "Settings feed the code: analysis_parameters.json")),
  body = body, depth = 1), out("sap_excerpt.html"))

## --- mock shells -------------------------------------------------------------------------
shell <- function(num, title, pop, df, foot) {
  paste0('<section class="shell"><h2>Table ', esc(num), ': ', esc(title), '</h2><p class="small">', esc(pop), '</p>',
         html_table(df, cls = "data shell"), '<p class="small">', esc(foot), '</p></section>')
}
demo_rows <- c("Age (years)", "  n", "  Mean (SD)", "  Median", "  Min - Max",
               "Height (cm), Weight (kg), BMI (kg/m2)", "  (n, Mean (SD), Median, Min - Max as for age)",
               "Sex, n (%)", "  n", "  Female", "  Male", "Race, n (%)", "  n", "  <category>", "Ethnicity, n (%)", "  n", "  <category>")
demo_cell <- c("", "xx", "xx.x (xx.x)", "xx.x", "xx.x - xx.x", "", "", "", "xx", "xx (xx.x%)", "xx (xx.x%)", "", "xx", "xx (xx.x%)", "", "xx", "xx (xx.x%)")
demo <- data.frame(Characteristic = demo_rows, `TR (N=xx)` = demo_cell, `RT (N=xx)` = demo_cell, `Total (N=xx)` = demo_cell, check.names = FALSE)
aeo <- data.frame(Category = c("Participants with at least one TEAE", "Total number of TEAEs", "Participants with a related TEAE",
                               "Participants with a severe TEAE", "Participants with a serious TEAE",
                               "Participants with a TEAE leading to withdrawal", "Participants with a TEAE leading to death"),
                  `Test (N=xx)` = c("xx (xx.x%)", "xx", rep("xx (xx.x%)", 5)), `Reference (N=xx)` = c("xx (xx.x%)", "xx", rep("xx (xx.x%)", 5)),
                  check.names = FALSE)
conc <- data.frame(`Nominal time (h)` = c("0 (pre-dose)", "", "", "", "", "0.25 ... 48", ""),
                   Statistic = c("n (n BLQ)", "Mean (SD)", "CV%", "Median", "Min - Max", "(as above)", ""),
                   `Test (N=xx)` = c("xx (xx)", "xx.xx (xx.xx)", "xx.x", "xx.xx", "xx.xx - xx.xx", "", ""),
                   `Reference (N=xx)` = c("xx (xx)", "xx.xx (xx.xx)", "xx.x", "xx.xx", "xx.xx - xx.xx", "", ""), check.names = FALSE)
ppar <- data.frame(Parameter = c("Cmax (ng/mL)", "", "", "", "", "", "",
                                 "AUC(0-t), AUC(0-inf), AUC(0-inf) extrapolated (%), t1/2 (h), lambda z (1/h)", "tmax (h)", "", ""),
                   Statistic = c("n", "Mean (SD)", "CV%", "Geometric mean", "Geometric CV%", "Median", "Min - Max", "(as Cmax)",
                                 "n", "Median", "Min - Max"),
                   `Test (N=xx)` = c("xx", "xx.x (xx.x)", "xx.x", "xx.x", "xx.x", "xx.x", "xx.x - xx.x", "", "xx", "x.xx", "x.xx - x.xx"),
                   `Reference (N=xx)` = c("xx", "xx.x (xx.x)", "xx.x", "xx.x", "xx.x", "xx.x", "xx.x - xx.x", "", "xx", "x.xx", "x.xx - x.xx"),
                   check.names = FALSE)
bes <- data.frame(Parameter = c("Cmax (ng/mL)", "AUC(0-t) (h*ng/mL)", "AUC(0-inf) (h*ng/mL), supportive"), n = "xx",
                  `Adjusted geometric mean, Test` = "xxx.x", `Adjusted geometric mean, Reference` = "xxx.x",
                  `Ratio T/R (%)` = "xxx.xx", `90% CI (%)` = "xx.xx, xxx.xx", `Within-participant CV%` = "xx.x",
                  `Within 80.00 to 125.00%` = "Yes/No", check.names = FALSE)
anv <- data.frame(Parameter = "Cmax / AUC(0-t)", Effect = c("Sequence", "Participant(sequence)", "Period", "Formulation", "Residual"),
                  DF = "xx", `Sum of squares` = "x.xxxx", `Mean square` = "x.xxxx", F = c("xx.xx", "xx.xx", "xx.xx", "xx.xx", ""),
                  `Error term` = c("Participant(sequence)", "Residual", "Residual", "Residual", ""), `p-value` = c("x.xxxx", "x.xxxx", "x.xxxx", "x.xxxx", ""), check.names = FALSE)
shells <- paste0(
  md("Planned layouts with placeholders (x). Titles, populations and footnotes match the executed outputs in the analysis stage. Every output carries the footnote: \"Synthetic data; not a regulatory deliverable.\""),
  shell("14.1.2", "Demographic and Baseline Characteristics", "Safety set", demo, "Percentages use the number of participants in the column."),
  shell("14.3.1.1", "Overview of Treatment-Emergent Adverse Events", "Safety set", aeo, paste0("Counted by treatment at onset; each participant counts once per row; N = participants dosed with that treatment. No total column: in a crossover a participant contributes to both columns. ", STUDY$dict_meddra, ".")),
  shell("14.4.1.1", "Summary of Plasma SIMDRUG Concentrations (ng/mL) by Nominal Time", "PK concentration set", conc, "BLQ (below 0.50 ng/mL) set to 0 (ICH M13A); n BLQ in parentheses. Periods excluded under the SAP rules are not summarized."),
  shell("14.4.4.1", "Summary of Plasma SIMDRUG PK Parameters", "PK parameter set", ppar, "Actual sampling times. AUC by linear-up/log-down. Geometric CV% = 100*sqrt(exp(s^2) - 1). Periods excluded under the SAP rules are not summarized. AUC(0-inf) is not summarized when more than 20% is extrapolated; lambda z-based parameters are not summarized when the adjusted R-squared is below 0.90 (n excluded given in a footnote)."),
  shell("14.4.3.1", "Bioequivalence Analysis: Ratio of Geometric Means (Test/Reference) and 90% CI", "Bioequivalence set", bes, "GLM on ln(parameter): sequence, participant(sequence), period, formulation. Decision on unrounded limits. AUC(0-inf): participants whose AUC(0-inf) passes the parameter rules in both periods."),
  shell("14.4.3.2", "ANOVA Effects for ln(Cmax) and ln(AUC(0-t))", "Bioequivalence set", anv, "Sequence tested against participant(sequence); other effects against the residual. No carry-over test (ICH M13A).")
)
write_text(page_html(
  title = "Mock Shells", kicker = "Stage 2: statistical analysis plan",
  h1 = "Mock shells for the planned outputs",
  description = "Mock table shells for a synthetic 2x2 bioequivalence study: demographics, adverse events, PK concentrations, PK parameters and the bioequivalence result.",
  labels = paste0(lab("tools", "Shells for the six executed tables")),
  body = shells, depth = 1), out("mock_shells.html"))
cat("[02_sap] analysis_parameters.json, sap_excerpt.html, mock_shells.html written\n")
