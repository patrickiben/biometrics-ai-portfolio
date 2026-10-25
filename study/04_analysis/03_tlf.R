################################################################################
# 04_analysis/03_tlf.R: executed tables and figures with rtables 0.6.17 / tern 0.9.13,
# exported to RTF with formatters::export_as_rtf() (formatters 0.5.13, through r2rtf)
# and to HTML pages. SYNTHETIC DATA ONLY.
#   T 14.1.2   demographics (tern::analyze_vars)                     safety set
#   T 14.3.1.1 TEAE overview (tern::summarize_num_patients, count_patients_with_flags)
#   T 14.4.1.1 concentrations by nominal time (rtables, custom analysis function)
#   T 14.4.4.1 PK parameters (rtables, custom analysis function; baseline conventions)
#   T 14.4.3.1 bioequivalence result (rtables::df_to_tt from 02_be.R)
#   T 14.4.3.2 ANOVA effects (rtables::df_to_tt from 02_be.R)
#   F 14.4.2.1 mean concentrations, nominal time, linear and semi-log (ggplot2)
#   F 14.4.2.2 individual concentrations, actual time, semi-log (ggplot2)
#
# Inputs : objects adsl, adpc, adpp, adae, be_results, be_anova
# Outputs: 04_analysis/tlf/*.rtf, *.html, *.csv (displayed cells), *.png; objects `TLF`
################################################################################
suppressPackageStartupMessages({ library(rtables); library(tern); library(ggplot2) })
stopifnot(requireNamespace("r2rtf", quietly = TRUE))    # formatters::export_as_rtf() writes RTF through r2rtf
tdir <- sp("04_analysis", "tlf")
dir.create(tdir, showWarnings = FALSE)
FOOT_SYN <- "Synthetic data; not a regulatory deliverable."
prov <- sprintf("Program: study/04_analysis/03_tlf.R; data cut-off %s (synthetic).", STUDY$cutoff)
prov_be <- sprintf("Program: study/04_analysis/02_be.R and 03_tlf.R; data cut-off %s (synthetic).", STUDY$cutoff)
SAPT <- jsonlite::read_json(sp("02_sap", "analysis_parameters.json"), simplifyVector = TRUE)
TRT_LEV <- c("Test", "Reference")
f1 <- function(x, d) formatC(x, format = "f", digits = d)
## rtables HTML; the attribute stops Quarto from re-parsing the table when the report embeds it
tlf_html <- function(tt) sub("<table ", '<table data-quarto-disable-processing="true" ', as.character(as_html(tt)), fixed = TRUE)

## --- T 14.1.2 demographics --------------------------------------------------------------
dm_df <- adsl %>% filter(SAFFL == "Y") %>%
  mutate(TRTSEQP = factor(TRTSEQP, levels = c("TR", "RT")),
         SEX = factor(SEX, levels = c("F", "M"), labels = c("Female", "Male")),
         RACE = factor(RACE, levels = c("ASIAN", "BLACK OR AFRICAN AMERICAN", "MULTIPLE", "WHITE"),
                       labels = c("Asian", "Black or African American", "Multiple", "White")),
         ETHNIC = factor(ETHNIC, levels = c("HISPANIC OR LATINO", "NOT HISPANIC OR LATINO", "NOT REPORTED"),
                         labels = c("Hispanic or Latino", "Not Hispanic or Latino", "Not reported")))
lyt_dm <- basic_table(title = "Table 14.1.2 Demographic and Baseline Characteristics",
                      subtitles = c("Safety set", "Study SIMBE01 (synthetic)"),
                      main_footer = c("Percentages use the number of participants in the column.", FOOT_SYN),
                      prov_footer = prov, show_colcounts = TRUE) %>%
  split_cols_by("TRTSEQP") %>% add_overall_col("Total") %>%
  analyze_vars(c("AGE", "HEIGHTBL", "WEIGHTBL", "BMIBL", "SEX", "RACE", "ETHNIC"),
               var_labels = c("Age (years)", "Height (cm)", "Weight (kg)", "BMI (kg/m2)", "Sex, n (%)", "Race, n (%)", "Ethnicity, n (%)"),
               .stats = c("n", "mean_sd", "median", "range", "count_fraction"),
               .formats = c(mean_sd = "xx.x (xx.x)", median = "xx.x", range = "xx.x - xx.x", count_fraction = "xx (xx.x%)"))
t_dm <- build_table(lyt_dm, dm_df)

## --- T 14.3.1.1 TEAE overview by treatment at onset ------------------------------------------
expo <- bind_rows(adsl %>% filter(SAFFL == "Y") %>% transmute(USUBJID, TRTA = TRT01A),
                  adsl %>% filter(SAFFL == "Y", !is.na(TRT02A)) %>% transmute(USUBJID, TRTA = TRT02A)) %>%
  mutate(TRTA = factor(TRTA, levels = TRT_LEV))
ae_df <- adae %>% filter(TRTEMFL == "Y", SAFFL == "Y") %>%
  mutate(TRTA = factor(TRTA, levels = TRT_LEV),
         REL = AREL == "RELATED", SEV = ASEV == "SEVERE", SER = AESER == "Y",
         WD = AEACN == "DRUG WITHDRAWN", DTH = AEOUT == "FATAL")
lyt_ae <- basic_table(title = "Table 14.3.1.1 Overview of Treatment-Emergent Adverse Events",
                      subtitles = c("Safety set", "Study SIMBE01 (synthetic)"),
                      main_footer = c("TEAE = adverse event with onset on or after the first dose, assigned to the treatment taken most recently before onset.",
                                      "Each participant counts once per row; N = participants dosed with that treatment.",
                                      paste0("No total column: in a crossover a participant contributes to both columns. ", STUDY$dict_meddra, "."), FOOT_SYN),
                      prov_footer = prov, show_colcounts = TRUE) %>%
  split_cols_by("TRTA") %>%
  summarize_num_patients(var = "USUBJID", .stats = c("unique", "nonunique"),
                         .labels = c(unique = "Participants with at least one TEAE", nonunique = "Total number of TEAEs")) %>%
  count_patients_with_flags("USUBJID", flag_variables = c("REL", "SEV", "SER", "WD", "DTH"),
                            flag_labels = c("Participants with a related TEAE", "Participants with a severe TEAE",
                                            "Participants with a serious TEAE", "Participants with a TEAE leading to withdrawal",
                                            "Participants with a TEAE leading to death"),
                            denom = "N_col", .formats = c(count_fraction = format_count_fraction_fixed_dp),
                            .indent_mods = c(count_fraction = 0L))
t_ae <- build_table(lyt_ae, ae_df, alt_counts_df = expo)

## --- T 14.4.1.1 concentrations by nominal time ------------------------------------------------
conc_df <- adpc %>% filter(PARAMCD == "SIMDRUG", ANL02FL == "Y") %>%
  semi_join(filter(adsl, PKCFL == "Y"), by = "USUBJID") %>%
  mutate(TRTA = factor(TRTA, levels = TRT_LEV),
         TIME = factor(ifelse(NRRLT == 0, "0 (pre-dose)", formatC(NRRLT, format = "fg")),
                       levels = c("0 (pre-dose)", formatC(sort(unique(NRRLT[NRRLT > 0])), format = "fg"))))
afun_conc <- function(df, .var, ...) {
  x <- df$AVAL; n <- sum(!is.na(x)); nb <- sum(df$BLQFL %in% "Y")
  m <- mean(x); s <- stats::sd(x)
  in_rows(
    "n (n BLQ)" = rcell(sprintf("%d (%d)", n, nb), format = "xx"),
    "Mean (SD)" = rcell(sprintf("%s (%s)", f1(m, 2), f1(s, 2)), format = "xx"),
    "CV%" = rcell(if (m > 0) f1(100 * s / m, 1) else "NE", format = "xx"),
    "Median" = rcell(f1(stats::median(x), 2), format = "xx"),
    "Min - Max" = rcell(sprintf("%s - %s", f1(min(x), 2), f1(max(x), 2)), format = "xx"))
}
lyt_conc <- basic_table(title = "Table 14.4.1.1 Summary of Plasma SIMDRUG Concentrations (ng/mL) by Nominal Time",
                        subtitles = c("PK concentration set", "Study SIMBE01 (synthetic)"),
                        main_footer = c("BLQ (below 0.50 ng/mL) set to 0 (ICH M13A); n BLQ in parentheses. NE = not estimable.",
                                        "Periods excluded under the SAP rules are not summarized (ADPC.ANL02FL).", FOOT_SYN),
                        prov_footer = prov, show_colcounts = TRUE) %>%
  split_cols_by("TRTA") %>%
  split_rows_by("TIME", label_pos = "visible", split_label = "Nominal time (h)") %>%
  analyze("AVAL", afun = afun_conc)
t_conc <- build_table(lyt_conc, conc_df, alt_counts_df = conc_df %>% distinct(USUBJID, TRTA))

## --- T 14.4.4.1 PK parameters -------------------------------------------------------------------
pk_show <- c(CMAX = 1, AUCLST = 1, AUCIFO = 1, AUCPEO = 2, LAMZHL = 2, LAMZ = 4, TMAX = 2)
## values flagged by the SAP parameter rules (ADPP.NCAEXRSN) in periods that are otherwise summarized
n_rule <- function(term) adpp %>% filter(NCAEXRSN %in% term, PARAMCD == "AUCIFO", is.na(PKEXRSN)) %>%
  semi_join(filter(adsl, PKPFL == "Y"), by = "USUBJID") %>% nrow()
rule_terms <- nca_rule_terms(SAPT)
par_df <- adpp %>% filter(ANL01FL == "Y", PARAMCD %in% names(pk_show), !is.na(AVAL)) %>%
  semi_join(filter(adsl, PKPFL == "Y"), by = "USUBJID") %>%
  mutate(TRTA = factor(TRTA, levels = TRT_LEV), PARAM = factor(PARAM, levels = unique(PARAM[order(match(PARAMCD, names(pk_show)))])))
afun_par <- function(df, .var, ...) {
  x <- df$AVAL; p <- unique(df$PARAMCD); d <- pk_show[[p]]
  rng <- sprintf("%s - %s", f1(min(x), d), f1(max(x), d))
  if (p == "TMAX")
    return(in_rows("n" = rcell(length(x), format = "xx"), "Median" = rcell(f1(stats::median(x), d), format = "xx"),
                   "Min - Max" = rcell(rng, format = "xx")))
  in_rows("n" = rcell(length(x), format = "xx"),
          "Mean (SD)" = rcell(sprintf("%s (%s)", f1(mean(x), d), f1(stats::sd(x), d)), format = "xx"),
          "CV%" = rcell(f1(100 * stats::sd(x) / mean(x), 1), format = "xx"),
          "Geometric mean" = rcell(f1(geomean(x), d), format = "xx"),
          "Geometric CV%" = rcell(f1(geocv(x), 1), format = "xx"),
          "Median" = rcell(f1(stats::median(x), d), format = "xx"),
          "Min - Max" = rcell(rng, format = "xx"))
}
lyt_par <- basic_table(title = "Table 14.4.4.1 Summary of Plasma SIMDRUG PK Parameters",
                       subtitles = c("PK parameter set", "Study SIMBE01 (synthetic)"),
                       main_footer = c(sprintf("NCA with PKNCA %s on actual sampling times; AUC by linear-up/log-down; BLQ = 0 and omitted from lambda z (ICH M13A).", pkg_version("PKNCA")),
                                       "Geometric mean = exp(mean(log x)); geometric CV% = 100*sqrt(exp(s^2) - 1) on the log scale.",
                                       "Periods excluded under the SAP rules are not summarized (ADPP.ANL01FL).",
                                       sprintf("AUC(0-inf) is not summarized when more than %g%% is extrapolated (%d profiles); lambda z-based parameters are not summarized when the adjusted R-squared is below %.2f (%d profiles). Values kept in ADPP (NCAEXRSN).",
                                               SAPT$nca$max_aucinf_pext_pct, n_rule(rule_terms[["pext"]]), SAPT$nca$min_hl_adj_r_squared, n_rule(rule_terms[["r2"]])),
                                       FOOT_SYN),
                       prov_footer = prov, show_colcounts = TRUE) %>%
  split_cols_by("TRTA") %>%
  split_rows_by("PARAM", label_pos = "hidden", split_fun = drop_split_levels) %>%
  analyze("AVAL", afun = afun_par)
t_par <- build_table(lyt_par, par_df, alt_counts_df = par_df %>% distinct(USUBJID, TRTA))

## --- T 14.4.3.1 bioequivalence result ----------------------------------------------------------
plab <- c(CMAX = "Cmax (ng/mL)", AUCLST = "AUC(0-t) (h*ng/mL)", AUCIFO = "AUC(0-inf) (h*ng/mL), supportive")
be_show <- be_results %>% transmute(
  `n` = as.character(n),
  `Adjusted geometric mean, Test` = f1(gm_T, 1), `Adjusted geometric mean, Reference` = f1(gm_R, 1),
  `Ratio T/R (%)` = f1(100 * ratio, 2), `90% CI (%)` = sprintf("%s, %s", f1(100 * lower, 2), f1(100 * upper, 2)),
  `Within-participant CV%` = f1(cv_within, 1), `Within 80.00 to 125.00%` = ifelse(within_limits, "Yes", "No"))
rownames(be_show) <- unname(plab[be_results$PARAMCD])
t_be <- df_to_tt(be_show)
main_title(t_be) <- "Table 14.4.3.1 Bioequivalence Analysis: Ratio of Geometric Means (Test/Reference) and 90% CI"
subtitles(t_be) <- c("Bioequivalence set", "Study SIMBE01 (synthetic)")
main_footer(t_be) <- c("General linear model on ln(parameter): sequence, participant(sequence), period, formulation (fixed effects; ICH M13A).",
                       "Adjusted geometric mean = exp(least-squares mean). Ratio and 90% CI back-transformed from the T - R difference; decision on unrounded limits.",
                       "Within-participant CV% = 100*sqrt(exp(MSE) - 1).",
                       sprintf("AUC(0-inf): participants whose AUC(0-inf) passes the SAP parameter rules (at most %g%% extrapolated, adjusted R-squared at least %.2f) in both periods.",
                               SAPT$nca$max_aucinf_pext_pct, SAPT$nca$min_hl_adj_r_squared), FOOT_SYN)
prov_footer(t_be) <- prov_be

## --- T 14.4.3.2 ANOVA effects ---------------------------------------------------------------------
an_show <- be_anova %>% filter(PARAMCD %in% c("CMAX", "AUCLST")) %>% transmute(
  `DF` = as.character(df), `Sum of squares` = f1(ss, 4), `Mean square` = f1(ms, 4),
  `F` = ifelse(is.na(F), "", f1(F, 2)), `Error term` = ifelse(is.na(error_term), "", error_term),
  `p-value` = ifelse(is.na(p), "", fmt_p(p)))
rownames(an_show) <- paste0(ifelse(be_anova$PARAMCD[be_anova$PARAMCD %in% c("CMAX", "AUCLST")] == "CMAX", "ln(Cmax): ", "ln(AUC(0-t)): "),
                            be_anova$effect[be_anova$PARAMCD %in% c("CMAX", "AUCLST")])
t_an <- df_to_tt(an_show)
main_title(t_an) <- "Table 14.4.3.2 ANOVA Effects for ln(Cmax) and ln(AUC(0-t))"
subtitles(t_an) <- c("Bioequivalence set", "Study SIMBE01 (synthetic)")
main_footer(t_an) <- c("Sequence is tested against participant(sequence); the other effects against the residual mean square.",
                       "Sequence and participant(sequence) sums of squares are sequential; period and formulation are adjusted for all other terms.",
                       "No test for carry-over (ICH M13A).", FOOT_SYN)
prov_footer(t_an) <- prov_be

TLF <- list(
  t_14_1_2   = list(tt = t_dm,   title = "Table 14.1.2 Demographics", pop = "Safety set"),
  t_14_3_1_1 = list(tt = t_ae,   title = "Table 14.3.1.1 Overview of TEAEs", pop = "Safety set"),
  t_14_4_1_1 = list(tt = t_conc, title = "Table 14.4.1.1 Concentrations by nominal time", pop = "PK concentration set"),
  t_14_4_4_1 = list(tt = t_par,  title = "Table 14.4.4.1 PK parameters", pop = "PK parameter set"),
  t_14_4_3_1 = list(tt = t_be,   title = "Table 14.4.3.1 Bioequivalence result", pop = "Bioequivalence set"),
  t_14_4_3_2 = list(tt = t_an,   title = "Table 14.4.3.2 ANOVA effects", pop = "Bioequivalence set"))

write_csv_det(data.frame(id = names(TLF), title = vapply(TLF, function(x) main_title(x$tt), ""), file = paste0(names(TLF), ".rtf")),
              file.path(tdir, "tlf_titles.csv"))
for (id in names(TLF)) {
  tt <- TLF[[id]]$tt
  formatters::export_as_rtf(tt, file = file.path(tdir, paste0(id, ".rtf")), landscape = TRUE, font_size = 8)
  cells <- formatters::matrix_form(tt)$strings
  utils::write.table(cells, file.path(tdir, paste0(id, ".csv")), sep = ",", row.names = FALSE, col.names = FALSE, qmethod = "double")
  body <- paste0('<div class="tlf tblwrap">', tlf_html(tt), '</div>',
                 md(sprintf("Files: [%s.rtf](%s.rtf) (RTF from `formatters::export_as_rtf()`), [%s.csv](%s.csv) (the displayed cells). Program: `study/04_analysis/03_tlf.R`.", id, id, id, id)))
  write_text(page_html(title = TLF[[id]]$title, kicker = "Stage 4: analysis (executed output)", h1 = TLF[[id]]$title,
                       description = paste(TLF[[id]]$title, "for the synthetic study SIMBE01, produced with rtables/tern."),
                       labels = lab("tools", sprintf("Executed: rtables %s / tern %s", pkg_version("rtables"), pkg_version("tern"))), body = body, depth = 2),
             file.path(tdir, paste0(id, ".html")))
}

## --- figures ------------------------------------------------------------------------------------
pal <- c(Test = "#1F5FA8", Reference = "#B4531C")
mean_df <- conc_df %>% group_by(TRTA, NRRLT) %>% summarise(m = mean(AVAL), s = stats::sd(AVAL), n = n(), .groups = "drop")
base_theme <- theme_bw(base_size = 11) + theme(legend.position = "bottom", plot.caption = element_text(hjust = 0, size = 8))
p_lin <- ggplot(mean_df, aes(NRRLT, m, colour = TRTA, shape = TRTA)) +
  geom_errorbar(aes(ymin = pmax(m - s, 0), ymax = m + s), width = 0.6, alpha = 0.6) + geom_line() + geom_point(size = 1.8) +
  scale_colour_manual(values = pal) + scale_x_continuous(breaks = c(0, 4, 8, 12, 16, 24, 36, 48)) +
  labs(x = "Nominal time after dose (h)", y = "Mean (SD) SIMDRUG concentration (ng/mL)", colour = NULL, shape = NULL,
       title = "Figure 14.4.2.1a Mean plasma concentrations, linear scale (PK concentration set)",
       caption = "Nominal times (ICH M13A). BLQ = 0. Synthetic data; not a regulatory deliverable.") + base_theme
p_log <- ggplot(filter(mean_df, m > 0), aes(NRRLT, m, colour = TRTA, shape = TRTA)) +
  geom_line() + geom_point(size = 1.8) + scale_y_log10() +
  scale_colour_manual(values = pal) + scale_x_continuous(breaks = c(0, 4, 8, 12, 16, 24, 36, 48)) +
  labs(x = "Nominal time after dose (h)", y = "Mean SIMDRUG concentration (ng/mL, log scale)", colour = NULL, shape = NULL,
       title = "Figure 14.4.2.1b Mean plasma concentrations, semi-log scale (PK concentration set)",
       caption = "Nominal times; time points with a zero mean are not shown on the log scale. Synthetic data.") + base_theme
excl_ids <- sub("^SIMBE01-101-", "", unique(exclusions$USUBJID[!is.na(exclusions$PKEXRSN)]))
ind_df <- adpc %>% filter(PARAMCD == "SIMDRUG", ANL01FL == "Y", AVAL > 0) %>% mutate(TRTA = factor(TRTA, levels = TRT_LEV),
                                                                                    ID = sub("^SIMBE01-101-", "", USUBJID))
p_ind <- ggplot(ind_df, aes(ARRLT, AVAL, colour = TRTA)) + geom_line(linewidth = 0.4) + geom_point(size = 0.6) +
  scale_y_log10() + facet_wrap(~ID, ncol = 8) + scale_colour_manual(values = pal) +
  scale_x_continuous(breaks = c(0, 24, 48)) +
  labs(x = "Actual time after dose (h)", y = "SIMDRUG concentration (ng/mL, log scale)", colour = NULL,
       title = "Figure 14.4.2.2 Individual plasma concentrations, semi-log scale, actual times",
       caption = sprintf("Actual sampling times (ICH M13A). Quantifiable values only (a BLQ value between two samples is not drawn). Includes the excluded period(s) of participant(s) %s. Synthetic data.",
                         paste(excl_ids, collapse = ", "))) +
  theme_bw(base_size = 9) + theme(legend.position = "bottom", strip.text = element_text(size = 7), plot.caption = element_text(hjust = 0, size = 7))
ggsave(file.path(tdir, "f_14_4_2_1a_mean_linear.png"), p_lin, width = 8, height = 5, dpi = 110, device = grDevices::png, type = "cairo")
ggsave(file.path(tdir, "f_14_4_2_1b_mean_semilog.png"), p_log, width = 8, height = 5, dpi = 110, device = grDevices::png, type = "cairo")
ggsave(file.path(tdir, "f_14_4_2_2_individual.png"), p_ind, width = 10, height = 8, dpi = 100, device = grDevices::png, type = "cairo")
FIG <- list(p_lin = p_lin, p_log = p_log, p_ind = p_ind)

## analysis-set counts (used by the report and the CSR text)
analysis_sets <- data.frame(set = c("Enrolled (randomized)", "Safety", "PK concentration", "PK parameter", "Bioequivalence"),
                            flag = c("RANDFL", "SAFFL", "PKCFL", "PKPFL", "BEFL"))
analysis_sets$n <- vapply(analysis_sets$flag, function(f) sum(adsl[[f]] == "Y"), integer(1))
write_csv_det(analysis_sets, sp("04_analysis", "analysis_sets.csv"))
cat(sprintf("[04_analysis/tlf] %d tables (RTF, HTML, CSV) and 3 figures written\n", length(TLF)))
