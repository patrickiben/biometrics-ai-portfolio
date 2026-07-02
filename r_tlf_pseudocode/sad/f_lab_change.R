################################################################################
# FIGURE    : f_lab_change  (Single Ascending Dose)
# TITLE     : Mean (+/- SE) Change from Baseline in Laboratory Values Over Time
#             by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, CHG, AVISIT/AVISITN, ANL01FL)
# NOTE      : PSEUDOCODE. SAD = parallel dose cohorts; colour/line = DOSE LEVEL
#             (dv$trtvar = TRT01A, ordered by TRT01AN; placebo pooled). Mean
#             change from baseline (CHG) by scheduled visit, one panel per
#             analyte, one line/colour per dose level, error bars = +/- 1 SE
#             (identical dispersion stat to the SAS twin). Analyte panel set =
#             ALT/AST/CREAT/K (same PARAMCDs as the SAS twin). Analysis-record
#             filter = ANL01FL + AVISITN>0 in both. Between-cohort, descriptive
#             (single dose -> no accumulation). n shown per point per SAP.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                      # colour/line = TRT01A (= dose level)

## post-baseline analysis records (one per participant/param/visit via ANL01FL)
lb <- adam$adlb %>%
  filter(SAFFL == "Y", ANL01FL == "Y", AVISITN > 0, !is.na(CHG),
         PARAMCD %in% c("ALT","AST","CREAT","K")) %>%   # same panel as SAS twin
  mutate(trt = .data[[dv$trtvar]])             # dose-level grouping

## --- mean +/- SE of change, per param x visit x dose -----------------------
## Keep TRT01AN so the dose colour order is ascending (escalation), not alpha.
## SE = sd / sqrt(n) (descstat returns n and sd).
summ <- descstat(lb, var = "CHG",
                 by = c("PARAMCD","PARAM","AVISITN","AVISIT", dv$trtvar, dv$trtnvar)) %>%
  transmute(PARAM, AVISITN, AVISIT,
            trt  = .data[[dv$trtvar]],
            trtn = .data[[dv$trtnvar]],
            n, mean, se = sd / sqrt(n),
            lo = mean - sd / sqrt(n), hi = mean + sd / sqrt(n)) %>%
  mutate(trt = reorder(trt, trtn)) %>%         # ascending-dose colour/line order
  arrange(PARAM, AVISITN, trtn)

ttl <- tfl_titles(num = "14.3.4.4", type = "Figure",
   text = "Mean (+/- SE) Change from Baseline in Laboratory Values Over Time by Dose Level",
   pop  = "Safety Population",
   foot = paste("Points = arithmetic mean change from baseline by scheduled visit;",
                "error bars = +/- 1 standard error; dose cohorts overlaid (ascending). Descriptive,",
                "between-cohort (SAD, single dose). Visits with n < 3 may be suppressed per SAP."))

## --- faceted line plot: x = visit (ordered by AVISITN), y = mean CHG -------
p <- ggplot(summ, aes(x = reorder(AVISIT, AVISITN), y = mean,
                      colour = trt, group = trt)) +
  geom_hline(yintercept = 0, linetype = "dotted") +
  geom_line(position = position_dodge(width = 0.3)) +
  geom_point(position = position_dodge(width = 0.3), size = 1.8) +
  geom_errorbar(aes(ymin = lo, ymax = hi),
                width = 0.2, position = position_dodge(width = 0.3)) +
  facet_wrap(~ PARAM, scales = "free_y") +
  labs(x = "Scheduled Visit", y = "Mean Change from Baseline (+/- SE)",
       colour = "Dose Level", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() +
  theme(legend.position = "bottom", axis.text.x = element_text(angle = 45, hjust = 1))
# ggsave(file.path(env$out, "f_lab_change.png"), p, width = 10, height = 7, dpi = 300)
print(p)
