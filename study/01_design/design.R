################################################################################
# 01_design/design.R: sample size (PowerTOST) and the randomization schedule (blockrand)
# for the synthetic 2x2 bioequivalence study SIMBE01. SYNTHETIC DATA ONLY.
#
# Inputs : study/R/common.R (STUDY constants)
# Outputs: 01_design/sample_size.csv, sensitivity_n.csv, sensitivity_power.csv,
#          dropout_inflation.csv, randomization_schedule.csv, balance_check.csv,
#          design_parameters.json, protocol_statistics.html
################################################################################
suppressPackageStartupMessages({
  library(PowerTOST)   # 1.5-7
  library(blockrand)   # 1.5
})

out <- function(f) sp("01_design", f)

## --- planning assumptions --------------------------------------------------------
PLAN <- list(
  cv       = 0.25,   # within-participant CV (log scale), Cmax and AUC(0-t)
  theta0   = 0.95,   # assumed true T/R geometric mean ratio
  theta1   = 0.80, theta2 = 1.25,
  alpha    = 0.05,   # each one-sided test (equivalent to a two-sided 90% CI)
  power_primary = 0.90,
  dropout  = 0.05,
  design   = "2x2"
)

## --- 1. sample size at 80% and 90% power ----------------------------------------
ss <- do.call(rbind, lapply(c(0.80, 0.90), function(pw) {
  r <- sampleN.TOST(alpha = PLAN$alpha, targetpower = pw, theta0 = PLAN$theta0,
                    theta1 = PLAN$theta1, theta2 = PLAN$theta2, CV = PLAN$cv,
                    design = PLAN$design, method = "exact", print = FALSE)
  data.frame(target_power = pw, cv = PLAN$cv, theta0 = PLAN$theta0,
             n_evaluable = r[["Sample size"]], achieved_power = round(r[["Achieved power"]], 4))
}))
n_eval <- ss$n_evaluable[ss$target_power == PLAN$power_primary]

## --- 2. dropout inflation (rounded up to an even number for 1:1 sequences) --------
infl <- do.call(rbind, lapply(c(0, 0.05, 0.10, 0.15), function(d) {
  raw <- n_eval / (1 - d); n <- ceiling(raw); if (n %% 2) n <- n + 1L
  data.frame(dropout = d, n_evaluable = n_eval, n_enrolled = as.integer(n))
}))
n_enrol <- infl$n_enrolled[infl$dropout == PLAN$dropout]
stopifnot(n_enrol == STUDY$n_enrolled)   # the simulated study enrolls exactly this number

## --- 3. sensitivity: N over CV x GMR, and power at the planned evaluable N ---------
grid <- expand.grid(cv = c(0.15, 0.20, 0.25, 0.30, 0.35), theta0 = c(0.90, 0.95, 1.00, 1.05))
sens_n <- do.call(rbind, lapply(seq_len(nrow(grid)), function(i) {
  g <- grid[i, ]
  n80 <- sampleN.TOST(CV = g$cv, theta0 = g$theta0, targetpower = 0.80, design = "2x2", print = FALSE)[["Sample size"]]
  n90 <- sampleN.TOST(CV = g$cv, theta0 = g$theta0, targetpower = 0.90, design = "2x2", print = FALSE)[["Sample size"]]
  data.frame(cv = g$cv, theta0 = g$theta0, n_evaluable_80 = n80, n_evaluable_90 = n90)
}))
sens_pw <- do.call(rbind, lapply(seq_len(nrow(grid)), function(i) {
  g <- grid[i, ]
  data.frame(cv = g$cv, theta0 = g$theta0, n_evaluable = n_eval,
             power = round(power.TOST(CV = g$cv, theta0 = g$theta0, n = n_eval, design = "2x2"), 4))
}))
pa <- pa.ABE(CV = PLAN$cv, theta0 = PLAN$theta0, targetpower = PLAN$power_primary, minpower = 0.80)
## pa.ABE walks each assumption away from the plan until power falls to minpower; the
## row with the lowest power in each walk is the boundary.
pa_cv  <- round(pa$paCV$CV[which.min(pa$paCV$pwr)], 4)
pa_th  <- round(pa$paGMR$theta0[which.min(pa$paGMR$pwr)], 4)
pa_n   <- pa$paN$N[which.min(pa$paN$pwr)]

## --- 4. randomization schedule: permuted blocks of 4, sequences TR and RT 1:1 -------
## Seed 2026 (the study master seed). In a real study the schedule is generated and
## held by a statistician outside the study team and the block size stays out of the
## protocol; this synthetic schedule is published only as a worked example.
set.seed(STUDY$seed)
rs <- blockrand(n = STUDY$n_enrolled, num.levels = 2, levels = STUDY$sequences,
                block.sizes = 2, id.prefix = "R", block.prefix = "B")   # block.sizes x levels = 4
rs <- data.frame(RANDNO = sprintf("R%04d", 1000 + seq_len(nrow(rs))),
                 BLOCK = as.character(rs$block.id), BLOCKSIZE = rs$block.size,
                 SEQUENCE = as.character(rs$treatment))
rs$SEQUENCE_LABEL <- ifelse(rs$SEQUENCE == "TR", "Test then Reference", "Reference then Test")
stopifnot(nrow(rs) == STUDY$n_enrolled)

## balance check: every block 2 TR + 2 RT; overall 1:1; running imbalance never above 2
bal_blocks <- rs %>% group_by(BLOCK) %>%
  summarise(n = n(), n_TR = sum(SEQUENCE == "TR"), n_RT = sum(SEQUENCE == "RT"), .groups = "drop") %>%
  mutate(balanced = n_TR == n_RT)
run_imb <- max(abs(cumsum(ifelse(rs$SEQUENCE == "TR", 1, -1))))
balance <- rbind(
  data.frame(check = "Schedule length equals planned enrollment", value = as.character(nrow(rs)),
             expected = as.character(STUDY$n_enrolled), pass = nrow(rs) == STUDY$n_enrolled),
  data.frame(check = "Blocks with 2 TR and 2 RT", value = sprintf("%d of %d", sum(bal_blocks$balanced), nrow(bal_blocks)),
             expected = sprintf("%d of %d", nrow(bal_blocks), nrow(bal_blocks)), pass = all(bal_blocks$balanced)),
  data.frame(check = "Overall TR : RT", value = sprintf("%d : %d", sum(rs$SEQUENCE == "TR"), sum(rs$SEQUENCE == "RT")),
             expected = "20 : 20", pass = sum(rs$SEQUENCE == "TR") == STUDY$n_enrolled / 2),
  data.frame(check = "Largest running imbalance (TR minus RT)", value = as.character(run_imb),
             expected = "2 or less", pass = run_imb <= 2))
stopifnot(all(balance$pass))

## --- 5. write outputs ---------------------------------------------------------------
write_csv_det(ss, out("sample_size.csv"))
write_csv_det(infl, out("dropout_inflation.csv"))
write_csv_det(sens_n, out("sensitivity_n.csv"))
write_csv_det(sens_pw, out("sensitivity_power.csv"))
write_csv_det(rs, out("randomization_schedule.csv"))
write_csv_det(balance, out("balance_check.csv"))

DESIGN <- list(
  study = STUDY$studyid, synthetic = TRUE, design = "2x2 crossover, sequences TR and RT",
  dose_mg = STUDY$dose_mg, washout_days = STUDY$washout_d, periods = 2L,
  planning = list(cv_pct = 100 * PLAN$cv, gmr_pct = 100 * PLAN$theta0, lower_pct = 80, upper_pct = 125,
                  alpha_one_sided = PLAN$alpha, ci_level_pct = 90,
                  n_evaluable_80 = ss$n_evaluable[ss$target_power == 0.80],
                  n_evaluable_90 = n_eval, power_90_achieved = ss$achieved_power[ss$target_power == 0.90],
                  power_80_achieved = ss$achieved_power[ss$target_power == 0.80],
                  dropout_pct = 100 * PLAN$dropout, n_enrolled = n_enrol,
                  pa_abe_min_power = 0.80, pa_abe_cv_pct = round(100 * pa_cv, 2),
                  pa_abe_gmr_pct = round(100 * pa_th, 2), pa_abe_n = pa_n),
  randomization = list(seed = STUDY$seed, method = "permuted blocks (blockrand 1.5)", block_size = 4L,
                       n_blocks = nrow(bal_blocks), n_TR = sum(rs$SEQUENCE == "TR"), n_RT = sum(rs$SEQUENCE == "RT"),
                       max_running_imbalance = run_imb),
  software = list(PowerTOST = as.character(packageVersion("PowerTOST")),
                  blockrand = as.character(packageVersion("blockrand")))
)
write_json_det(DESIGN, out("design_parameters.json"))

## --- 6. protocol statistical-section excerpt (ICH M11 headings) ----------------------
sens_wide <- sens_n %>%
  mutate(cell = sprintf("%d / %d", n_evaluable_80, n_evaluable_90),
         theta0 = sprintf("GMR %.2f", theta0), cv = sprintf("%.0f%%", 100 * cv)) %>%
  select(cv, theta0, cell) %>% pivot_wider(names_from = theta0, values_from = cell) %>%
  rename(`Within-participant CV` = cv)
pw_wide <- sens_pw %>%
  mutate(theta0 = sprintf("GMR %.2f", theta0), cv = sprintf("%.0f%%", 100 * cv), power = sprintf("%.1f%%", 100 * power)) %>%
  select(cv, theta0, power) %>% pivot_wider(names_from = theta0, values_from = power) %>%
  rename(`Within-participant CV` = cv)

body <- paste0(
'<div class="note"><p>This is an excerpt of the statistical content of a protocol for a synthetic study. The headings and numbers follow the ICH M11 template (CeSHarP; Step 4 19 Nov 2025; FDA final guidance May 2026). Only the sections that carry statistical content are shown, and the protocol for a real study would be reviewed and signed by its study team.</p></div>',
md(
"## 3 Trial Objectives and Associated Estimands",
"",
"### 3.1 Primary Objective and Associated Estimand",
"",
"**Primary objective.** To show that a single oral 100 mg dose of the SIMDRUG test tablet (T) is bioequivalent to the reference tablet (R) in healthy adults under fasting conditions, in rate (Cmax) and extent (AUC(0-t)) of exposure.",
"",
"**Estimand.** The five attributes follow ICH E9(R1):",
"",
"- *Treatment:* one 100 mg tablet of T, and one 100 mg tablet of R, each taken fasting, in a 2x2 crossover with a 14-day washout.",
"- *Population:* healthy adults who meet the eligibility criteria.",
"- *Variable:* Cmax and AUC(0-t) of SIMDRUG in plasma, from actual sampling times, for each participant and period.",
"- *Intercurrent events:* emesis within 2 hours of dosing, withdrawal before the second period, and a pre-dose concentration above 5% of that period's Cmax are handled with a hypothetical strategy (exposure had the event not occurred). The handling is set out in section 10.4.1.2 and in the statistical analysis plan.",
"- *Population-level summary:* the ratio of geometric means T/R with its two-sided 90% confidence interval. Bioequivalence is concluded for a parameter when the interval lies within 80.00% to 125.00%.",
"",
"### 3.2 Secondary Objectives and Associated Estimands",
"",
"- To compare AUC(0-inf), tmax and the terminal half-life between T and R (supportive, same estimand attributes).",
"- To describe the safety of single doses of T and R (treatment-emergent adverse events by treatment at onset).",
"",
"## 4 Trial Design",
"",
"### 4.1 Description of Trial Design",
"",
"Randomized, open-label, single-center, single-dose, two-period, two-sequence crossover. Participants are randomized 1:1 to the sequence TR or RT and receive one dose on Day 1 and one on Day 15. Plasma is sampled before dosing and at 0.25, 0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 36 and 48 hours after each dose.",
"",
"### 4.2.1 Rationale for Estimand(s)",
"",
"The question is whether the two formulations deliver the same exposure when each is taken as directed. Events that interfere with absorption or with the comparison (emesis soon after dosing, carry-over, a missing period) do not reflect the formulations, so a hypothetical strategy targets exposure in their absence. A treatment-policy strategy is not used: it would mix formulation differences with events unrelated to them.",
"",
"## 6 Trial Intervention and Concomitant Therapy",
"",
"### 6.7.2 Randomization",
"",
"A computer-generated permuted-block schedule assigns sequences TR and RT 1:1. The schedule is generated with a documented seed by a statistician outside the study team and loaded into the randomization system before the first participant is dosed. Following the M11 template, the block size is not stated in the protocol. (This worked example publishes its synthetic schedule and block size on the design page so that the generation and balance check can be inspected.)",
"",
"## 10 Statistical Considerations",
"",
"### 10.1 General Considerations",
"",
"Analyses use R (R >= 4.4.0; this example ran on R 4.6.0) with package versions pinned in the study lockfile. Pharmacokinetic parameters are log-transformed (natural log) before inferential analysis. Bioequivalence is tested with two one-sided tests at the 5% level, equivalent to a two-sided 90% confidence interval for the T/R ratio of geometric means.",
"",
"### 10.2 Analysis Sets",
"",
"- *Enrolled set:* every participant who is randomized.",
"- *Safety set:* every participant who receives at least one dose.",
"- *PK concentration set:* participants in the safety set with at least one quantifiable post-dose concentration.",
"- *PK parameter set:* participants with at least one profile that yields the primary parameters.",
"- *Bioequivalence set:* participants with evaluable Cmax and AUC(0-t) after both T and R, after the exclusions in section 10.4.1.2 (ICH M13A: the primary analysis includes every participant with evaluable data for both products).",
"",
"### 10.3 Analyses of Demographics and Other Baseline Variables",
"",
"Demographics and baseline characteristics are summarized by sequence and overall for the safety set. No formal tests are performed.",
"",
"### 10.4 Analyses Associated with the Primary Objective",
"",
"#### 10.4.1.1 Statistical Analysis Method",
"",
"For each of ln(Cmax) and ln(AUC(0-t)), a general linear model with fixed effects for sequence, period, formulation and participant within sequence is fitted to the bioequivalence set (ICH M13A, Step 4 23 Jul 2024; FDA final 30 Oct 2024; EU effective 25 Jan 2025). The sequence effect is tested against the participant-within-sequence mean square; the other effects are tested against the residual mean square, and all four tests are reported. The T minus R difference in least-squares means and its 90% confidence interval are back-transformed to a ratio. Bioequivalence is concluded when both 90% intervals lie within 80.00% to 125.00%, judged on the unrounded limits. No test for carry-over is performed.",
"",
"#### 10.4.1.2 Handling of Data in Relation to Primary Estimand",
"",
"Exclusions are decided and documented before bioanalysis, from the pre-specified rules: a period with emesis within 2 hours of dosing (twice the expected median tmax of 1 hour) is excluded; a period with a pre-dose concentration above 5% of that period's Cmax is excluded (ICH M13A); a period whose AUC is below 5% of the geometric mean AUC of that product, calculated without the participant, may be excluded (ICH M13A). A participant without evaluable data for both products leaves the bioequivalence set but stays in the safety and PK sets.",
"",
"#### 10.4.1.3 Handling of Missing Data in Relation to Primary Estimand",
"",
"No values are imputed. Missed samples are omitted from the profile. Concentrations below the lower limit of quantification (0.50 ng/mL) are set to zero in PK calculations and omitted from the estimate of the terminal rate constant (ICH M13A).",
"",
"#### 10.4.1.5 Supplementary Analysis",
"",
"A supplementary analysis repeats the primary model with the periods excluded under section 10.4.1.2 put back, for participants who have both periods. No separate sensitivity analysis is planned.",
"",
"### 10.7 Safety Analyses",
"",
"Treatment-emergent adverse events are summarized by the treatment taken at onset, counting each participant once per row, with the number of participants exposed to that treatment as the denominator.",
"",
"### 10.9 Interim Analyses",
"",
"None.",
"",
"### 10.10 Multiplicity Adjustments",
"",
"Bioequivalence requires both primary parameters to pass, so each is tested at the full 5% level (an intersection-union test) without adjustment.",
"",
"### 10.11 Sample Size Determination",
"",
sprintf("No earlier study of this synthetic product exists. The planning within-participant CV of %.0f%% applies to both primary parameters. The simulator behind this example (`sim_lifecycle/priors.R`) puts occasion-to-occasion variability at 15%% on apparent clearance plus an 8%% proportional assay error; %.0f%% adds a margin for a formulation that behaves less well than the simulator. The assumed true ratio is %.2f, a conventional allowance for a test product close to the reference (the simulator's true ratio is 1.00).",
        100 * PLAN$cv, 100 * PLAN$cv, PLAN$theta0),
"",
sprintf("With two one-sided tests at the 5%% level, acceptance limits of 80.00%% to 125.00%%, CV %.0f%% and a ratio of %.2f, PowerTOST %s (exact method) gives **%d evaluable participants for 80%% power** (achieved %.1f%%) and **%d for 90%% power** (achieved %.1f%%). The study plans for 90%% power and allows for %.0f%% of participants not being evaluable: %d / (1 - %.2f), rounded up to an even number, gives **%d participants enrolled** (%d per sequence). ICH M13A requires at least 12 evaluable participants; the plan exceeds that.",
        100 * PLAN$cv, PLAN$theta0, packageVersion("PowerTOST"),
        ss$n_evaluable[1], 100 * ss$achieved_power[1], ss$n_evaluable[2], 100 * ss$achieved_power[2],
        100 * PLAN$dropout, n_eval, PLAN$dropout, n_enrol, n_enrol / 2),
"",
sprintf("From `pa.ABE()`, power stays at or above 80%% when one assumption moves while the others stay at plan: a CV up to %.1f%%, a ratio down to %.4f, or as few as %d evaluable participants. The tables below show the rest of the sensitivity grid.",
        100 * pa_cv, pa_th, pa_n)
),
'<h3>Evaluable participants needed (80% / 90% power)</h3>',
html_table(sens_wide, caption = "PowerTOST sampleN.TOST, exact method, 2x2 design, alpha 0.05, limits 80.00% to 125.00%. Cells: evaluable participants for 80% / 90% power."),
'<h3>Power with the planned 38 evaluable participants</h3>',
html_table(pw_wide, caption = sprintf("PowerTOST power.TOST with n = %d evaluable participants.", n_eval)),
'<h3>Dropout inflation</h3>',
html_table(transmute(infl, `Not evaluable` = sprintf("%.0f%%", 100 * dropout), `Evaluable needed` = n_evaluable, `Enrolled (even)` = n_enrolled),
           caption = "Enrolled = evaluable / (1 - rate), rounded up to an even number for 1:1 sequences. The plan uses 5%."),
'<h2>Randomization schedule (synthetic)</h2>',
md(sprintf("Generated with `blockrand` %s, seed %d, permuted blocks of 4 (block size shown here only because the study is synthetic). Balance check:", packageVersion("blockrand"), STUDY$seed)),
html_table(transmute(balance, Check = check, Result = value, Expected = expected, Status = ifelse(pass, "pass", "FAIL"))),
md("Files: [randomization_schedule.csv](randomization_schedule.csv), [balance_check.csv](balance_check.csv), [sample_size.csv](sample_size.csv), [sensitivity_n.csv](sensitivity_n.csv), [sensitivity_power.csv](sensitivity_power.csv), [dropout_inflation.csv](dropout_inflation.csv), [design_parameters.json](design_parameters.json). Program: `study/01_design/design.R`.")
)

write_text(page_html(
  title = "Protocol Statistics Excerpt", kicker = "Stage 1: design",
  h1 = "Protocol statistical sections: sample size and randomization",
  description = "Protocol statistical-section excerpt for a synthetic 2x2 bioequivalence study, with ICH M11 headings, a PowerTOST sample size and a seeded randomization schedule.",
  labels = paste0(lab("led", "Led (job): protocol statistical sections and randomization schedules"), lab("tools", "Runs here: PowerTOST, blockrand")),
  body = body, depth = 1), out("protocol_statistics.html"))

cat(sprintf("[01_design] n evaluable 80%%/90%%: %d/%d; enrolled %d; schedule TR:RT %d:%d; balance %s\n",
            ss$n_evaluable[1], ss$n_evaluable[2], n_enrol, sum(rs$SEQUENCE == "TR"), sum(rs$SEQUENCE == "RT"),
            if (all(balance$pass)) "pass" else "FAIL"))
