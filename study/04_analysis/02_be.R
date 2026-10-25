################################################################################
# 04_analysis/02_be.R: bioequivalence analysis per the SAP and ICH M13A. SYNTHETIC DATA.
#   lm(log(AVAL) ~ SEQ + SUBJ + PER + TRT)  (participant nested in sequence; fixed effects)
#   * ANOVA: sequence tested against participant(sequence); participant(sequence), period
#     and formulation against the residual. Sequence and participant(sequence) sums of
#     squares are sequential; period and formulation are adjusted for all other terms.
#   * T - R difference of least-squares means, 90% CI from the residual MSE and its df,
#     back-transformed; decision on the unrounded limits (80.00% to 125.00%).
#   * within-participant CV% = 100*sqrt(exp(MSE) - 1).
# Primary: Cmax and AUC(0-t) on the bioequivalence set (ADPP.ANL02FL = Y). AUC(0-inf) is
# supportive, on participants whose AUC(0-inf) passes the SAP parameter rules in both
# periods. Two supplementary analyses (ICH E9(R1) term): (1) excluded periods put back for
# participants with both periods; (2) participants with Cmax at the first post-dose sample
# in either period removed (ICH M13A 2.1.8.1).
#
# Inputs : objects adpp, adpc, adsl, prof, exclusions; 02_sap/analysis_parameters.json
# Outputs: 04_analysis/be_results.csv, be_anova.csv, be_supplementary.csv, be_results.json,
#          pk_checks.csv (ICH M13A acceptability checks), first_point_cmax.csv
################################################################################
SAP <- jsonlite::read_json(sp("02_sap", "analysis_parameters.json"), simplifyVector = TRUE)
be_params <- c(SAP$primary_params, "AUCIFO")

be_fit <- function(d) {
  d <- d %>% mutate(SEQ = factor(TRTSEQP, levels = c("TR", "RT")), SUBJ = factor(USUBJID),
                    PER = factor(APERIOD), TRT = factor(TRTA, levels = c("Reference", "Test")), y = log(AVAL))
  stopifnot(all(table(d$USUBJID) == 2))                       # complete 2x2 data only
  fit <- lm(y ~ SEQ + SUBJ + PER + TRT, data = d)
  a1  <- anova(fit)                                           # sequential sums of squares
  d1  <- drop1(fit, scope = ~ PER + TRT, test = "F")          # adjusted for all other terms
  mse <- a1["Residuals", "Mean Sq"]; dfe <- a1["Residuals", "Df"]
  ms_subj <- a1["SUBJ", "Mean Sq"]; df_subj <- a1["SUBJ", "Df"]
  anova_tab <- data.frame(
    effect = c("Sequence", "Participant(sequence)", "Period", "Formulation", "Residual"),
    df = c(a1["SEQ", "Df"], df_subj, d1["PER", "Df"], d1["TRT", "Df"], dfe),
    ss = c(a1["SEQ", "Sum Sq"], a1["SUBJ", "Sum Sq"], d1["PER", "Sum of Sq"], d1["TRT", "Sum of Sq"], a1["Residuals", "Sum Sq"]),
    error_term = c("Participant(sequence)", "Residual", "Residual", "Residual", NA))
  anova_tab$ms <- anova_tab$ss / anova_tab$df
  anova_tab$F  <- c(anova_tab$ms[1] / ms_subj, anova_tab$ms[2:4] / mse, NA)
  anova_tab$p  <- c(pf(anova_tab$F[1], anova_tab$df[1], df_subj, lower.tail = FALSE),
                    pf(anova_tab$F[2:4], anova_tab$df[2:4], dfe, lower.tail = FALSE), NA)
  co  <- summary(fit)$coefficients["TRTTest", ]
  est <- unname(co["Estimate"]); se <- unname(co["Std. Error"])
  tq  <- qt(1 - (1 - SAP$ci_level) / 2, dfe)
  ## least-squares means: equal weight to each sequence (and so to each period)
  cell <- d %>% group_by(TRT, SEQ) %>% summarise(m = mean(y), .groups = "drop")
  lsm <- cell %>% group_by(TRT) %>% summarise(lsm = mean(m), .groups = "drop")
  list(fit = fit, anova = anova_tab,
       est = data.frame(n = length(unique(d$USUBJID)), n_TR = sum(d$SEQ == "TR") / 2, n_RT = sum(d$SEQ == "RT") / 2,
                        lsm_T = lsm$lsm[lsm$TRT == "Test"], lsm_R = lsm$lsm[lsm$TRT == "Reference"],
                        diff = est, se = se, df = dfe, mse = mse,
                        ratio = exp(est), lower = exp(est - tq * se), upper = exp(est + tq * se),
                        cv_within = 100 * sqrt(exp(mse) - 1)))
}

run_be <- function(flag, drop_subj = character()) {
  out <- lapply(be_params, function(p) {
    d <- adpp %>% filter(PARAMCD == p, .data[[flag]] == "Y", !is.na(AVAL), AVAL > 0, !USUBJID %in% drop_subj) %>%
      group_by(USUBJID) %>% filter(n() == 2) %>% ungroup()      # both periods (an AUC(0-inf) value can be flagged in one)
    r <- be_fit(d)
    list(est = cbind(PARAMCD = p, r$est), anova = cbind(PARAMCD = p, r$anova))
  })
  list(est = do.call(rbind, lapply(out, `[[`, "est")), anova = do.call(rbind, lapply(out, `[[`, "anova")))
}

## primary: bioequivalence set
prim <- run_be("ANL02FL")
be_results <- prim$est %>%
  mutate(role = ifelse(PARAMCD %in% SAP$primary_params, "primary", "supportive"),
         gm_T = exp(lsm_T), gm_R = exp(lsm_R),
         within_limits = lower >= SAP$be_lower & upper <= SAP$be_upper)   # unrounded limits
be_anova <- prim$anova
stopifnot(all(be_results$n[be_results$role == "primary"] == sum(adsl$BEFL == "Y")))

## --- Cmax at the first post-dose sample (ICH M13A 2.1.8.1) -------------------------------
## the first collected post-dose sample of each profile; Cmax there may have been missed
first_pd <- adpc %>% filter(PARAMCD == "SIMDRUG", ANL01FL == "Y", NRRLT > 0) %>%
  group_by(USUBJID, APERIOD) %>% slice_min(NRRLT, n = 1, with_ties = FALSE) %>% ungroup() %>%
  select(USUBJID, APERIOD, FIRST_NRRLT = NRRLT, FIRST_ARRLT = ARRLT)
first_point <- adpp %>% filter(PARAMCD == "TMAX", !is.na(AVAL)) %>% select(USUBJID, APERIOD, TRTA, TMAX = AVAL) %>%
  inner_join(first_pd, by = c("USUBJID", "APERIOD")) %>%
  left_join(select(prof, USUBJID, APERIOD, PROFILE_EVALUABLE = ANL01FL), by = c("USUBJID", "APERIOD")) %>%
  filter(abs(TMAX - FIRST_ARRLT) < 1e-6) %>%
  mutate(BEFL = adsl$BEFL[match(USUBJID, adsl$USUBJID)]) %>% arrange(USUBJID, APERIOD) %>% as.data.frame()
fp_subj <- unique(first_point$USUBJID[first_point$BEFL == "Y"])

## --- supplementary analyses --------------------------------------------------------------
## (1) excluded periods put back for participants with both periods (parameter rules still apply)
adpp <- adpp %>% group_by(USUBJID, PARAMCD) %>%
  mutate(SUPPFL = ifelse(PARAMCD %in% be_params & !is.na(AVAL) & is.na(NCAEXRSN) &
                           sum(!is.na(AVAL) & is.na(NCAEXRSN)) == 2, "Y", NA_character_)) %>% ungroup()
supp1 <- run_be("SUPPFL")
adpp <- adpp %>% select(-SUPPFL)
## (2) bioequivalence set without the participants with Cmax at the first post-dose sample
supp2 <- run_be("ANL02FL", drop_subj = fp_subj)
be_supplementary <- bind_rows(
  cbind(analysis = "1 Excluded periods put back", removed = NA_character_, supp1$est),
  cbind(analysis = "2 Without participants with Cmax at the first post-dose sample (ICH M13A 2.1.8.1)",
        removed = paste(fp_subj, collapse = " "), supp2$est)) %>%
  mutate(within_limits = lower >= SAP$be_lower & upper <= SAP$be_upper,
         ratio_pct = 100 * ratio, lower_pct = 100 * lower, upper_pct = 100 * upper)   # as the report displays them

be_pass <- all(be_results$within_limits[be_results$role == "primary"])

## --- ICH M13A acceptability checks ------------------------------------------------------
## counted on every evaluable profile (period rules applied), whether or not a parameter rule
## flags a value: the coverage check must see the profiles whose AUC(0-inf) is not summarized
nca_terms <- nca_rule_terms(SAP)
prof_ok <- prof %>% filter(ANL01FL == "Y") %>% select(USUBJID, APERIOD)
w <- adpp %>% filter(PARAMCD %in% c("AUCLST", "AUCIFO", "LAMZNPT", "LAMZ")) %>% semi_join(prof_ok, by = c("USUBJID", "APERIOD")) %>%
  group_by(USUBJID, APERIOD) %>% mutate(R2_RULE = any(NCAEXRSN %in% nca_terms[["r2"]])) %>% ungroup() %>%
  select(USUBJID, APERIOD, R2_RULE, PARAMCD, AVAL) %>% pivot_wider(names_from = PARAMCD, values_from = AVAL)
w_cov <- w %>% filter(!is.na(AUCIFO), !R2_RULE)                # coverage needs a usable lambda z
cov_low <- sum(100 * w_cov$AUCLST / w_cov$AUCIFO < SAP$exclusion_rules$auc_coverage_pct)
flag_prof <- function(term) adpp %>% filter(NCAEXRSN %in% term) %>% semi_join(prof_ok, by = c("USUBJID", "APERIOD")) %>%
  distinct(USUBJID, APERIOD) %>% nrow()
n_fp <- nrow(semi_join(first_point, prof_ok, by = c("USUBJID", "APERIOD")))
pk_checks <- data.frame(
  id = c("be_set", "auc_coverage", "lambda_z_points", "aucinf_pext", "adj_r2", "first_point_cmax",
         "emesis", "predose", "low_auc"),
  check = c("Participants with evaluable data for both products (bioequivalence set)",
            sprintf("Profiles with AUC(0-t)/AUC(0-inf) below %g%%", SAP$exclusion_rules$auc_coverage_pct),
            sprintf("Profiles with fewer than %d points in the terminal phase", SAP$nca$min_hl_points),
            sprintf("Profiles whose AUC(0-inf) is more than %g%% extrapolated (AUC(0-inf) not summarized or analyzed)", SAP$nca$max_aucinf_pext_pct),
            sprintf("Profiles with adjusted R-squared below %.2f (lambda z-based parameters not summarized or analyzed)", SAP$nca$min_hl_adj_r_squared),
            "Profiles with Cmax at the first post-dose sample",
            sprintf("Periods excluded for emesis within %g h of dosing", SAP$exclusion_rules$emesis_window_h),
            sprintf("Periods excluded for a pre-dose concentration above %g%% of Cmax", SAP$exclusion_rules$predose_pct_cmax),
            sprintf("Periods with AUC(0-t) below %g%% of the product geometric mean (without the participant)", SAP$exclusion_rules$low_exposure_pct)),
  value = c(sum(adsl$BEFL == "Y"), cov_low, sum(w$LAMZNPT < SAP$nca$min_hl_points, na.rm = TRUE),
            flag_prof(nca_terms[["pext"]]), flag_prof(nca_terms[["r2"]]), n_fp,
            sum(exclusions$EMESIS), sum(exclusions$PREDOSE_X), sum(exclusions$LOWEXP)),
  denominator = c(nrow(adsl), nrow(w_cov), nrow(w), nrow(w), nrow(w), nrow(w), nrow(exclusions), nrow(exclusions), nrow(exclusions)),
  rule = c(sprintf("ICH M13A 2.2.3.1: at least %d", SAP$exclusion_rules$min_evaluable),
           sprintf("ICH M13A 2.2.2.2: discuss validity if more than %g%% of profiles", SAP$exclusion_rules$auc_coverage_share_pct),
           "SAP and ICH M13A: at least 3 points",
           "SAP parameter rule: value kept in ADPP (NCAEXRSN), not summarized",
           "SAP parameter rule: values kept in ADPP (NCAEXRSN), not summarized",
           sprintf("ICH M13A 2.1.8.1: discuss robustness; supplementary analysis 2 removes %d participant(s) of the bioequivalence set", length(fp_subj)),
           "SAP rule: documented before bioanalysis (ICH M13A 2.2.1)",
           "ICH M13A 2.2.3.3: exclude the period (applied to the bioanalytical results)",
           "ICH M13A 2.2.1.1: may exclude, at most 1 participant (applied to the bioanalytical results)"))
pk_checks$pct <- round(100 * pk_checks$value / pk_checks$denominator, 1)
pk_checks$ok <- c(pk_checks$value[1] >= SAP$exclusion_rules$min_evaluable,
                  pk_checks$pct[2] <= SAP$exclusion_rules$auc_coverage_share_pct,
                  pk_checks$value[3] == 0, TRUE, TRUE, TRUE, TRUE, TRUE, pk_checks$value[9] <= 1)

write_csv_det(be_results, sp("04_analysis", "be_results.csv"))
write_csv_det(be_anova, sp("04_analysis", "be_anova.csv"))
write_csv_det(be_supplementary, sp("04_analysis", "be_supplementary.csv"))
write_csv_det(pk_checks, sp("04_analysis", "pk_checks.csv"))
write_csv_det(first_point, sp("04_analysis", "first_point_cmax.csv"))
write_json_det(list(conclusion = if (be_pass) "bioequivalent" else "not shown",
                    rule = SAP$be_rule, results = round_df(be_results), supplementary = round_df(be_supplementary)),
               sp("04_analysis", "be_results.json"))
cat(sprintf("[04_analysis/be] %s; Cmax ratio %.2f%% (%.2f, %.2f); AUC(0-t) ratio %.2f%% (%.2f, %.2f); n = %d; AUC(0-inf) n = %d; Cmax at first sample: %d profiles\n",
            if (be_pass) "BE shown" else "BE not shown",
            100 * be_results$ratio[1], 100 * be_results$lower[1], 100 * be_results$upper[1],
            100 * be_results$ratio[2], 100 * be_results$lower[2], 100 * be_results$upper[2], be_results$n[1],
            be_results$n[be_results$PARAMCD == "AUCIFO"], n_fp))
