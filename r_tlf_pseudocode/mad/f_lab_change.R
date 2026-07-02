################################################################################
# FIGURE    : f_lab_change  (Multiple Ascending Dose)
# TITLE     : Mean (SE) Change from Baseline in Laboratory Values by Visit and
#             Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, CHG, AVISIT/AVISITN, ANL01FL)
# NOTE      : PSEUDOCODE. MAD = parallel dose cohorts with REPEATED dosing; mean
#             change from baseline (CHG) is plotted across the scheduled on-
#             treatment visits (x = AVISITN, ordered) so any across-visit trend /
#             plateau over the repeated-dose period is visible. One panel per
#             analyte, one line/colour per dose level (= dv$trtvar), error bars =
#             +/- 1 SE. Between-cohort, descriptive; n shown per point.
#             [The analogous PK readout -- pre-dose trough (Ctrough) trend across
#              dosing days to assess attainment of steady state -- is in the
#              companion t_accumulation / f_pk_conc_mean (MAD); this figure is the
#              safety-lab counterpart of that across-visit trend view.]
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                      # colour/line = TRT01A (= dose level)

## post-baseline analysis records (one per participant/param/visit via ANL01FL)
lb <- adam$adlb %>%
  filter(SAFFL == "Y", ANL01FL == "Y", AVISITN > 0, !is.na(CHG),
         PARAMCD %in% c("ALT","AST","BILI","CREAT","ALP","GGT")) %>%
  mutate(trt = .data[[dv$trtvar]])

## --- mean +/- SE of change, per param x visit x dose level ------------------
## SE = sd / sqrt(n); carry AVISITN as the ordered repeated-dosing visit axis
summ <- descstat(lb, var = "CHG", by = c("PARAMCD","PARAM","AVISITN","AVISIT", dv$trtvar)) %>%
  transmute(PARAM, AVISITN, AVISIT, trt = .data[[dv$trtvar]],
            n, mean, sd, se = sd / sqrt(n),
            lo = mean - se, hi = mean + se) %>%
  arrange(PARAM, AVISITN)

ttl <- tfl_titles(num = "14.3.4.4", type = "Figure",
   text = "Mean (SE) Change from Baseline in Laboratory Values by Visit and Dose Level",
   pop  = "Safety Population",
   foot = paste("Points = arithmetic mean change from the Day 1 pre-dose baseline;",
                "error bars = +/- 1 SE; dose levels overlaid. One profile per dose-level",
                "cohort (MAD; one dose per participant). Visits span the multiple-dose",
                "period. Descriptive, between-cohort. SI units."))

## --- faceted trend plot: x = visit (AVISITN, repeated dosing), y = mean CHG
p <- ggplot(summ, aes(x = AVISITN, y = mean, colour = trt, group = trt)) +
  geom_hline(yintercept = 0, linetype = "dotted") +
  geom_line(position = position_dodge(width = 0.6)) +
  geom_point(position = position_dodge(width = 0.6), size = 1.8) +
  geom_errorbar(aes(ymin = lo, ymax = hi),
                width = 0.6, position = position_dodge(width = 0.6)) +
  facet_wrap(~ PARAM, scales = "free_y") +
  labs(x = "Visit",
       y = "Mean Change from Baseline (+/- SE)",
       colour = "Dose Level", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() +
  theme(legend.position = "bottom")
# ggsave(file.path(env$out, "f_lab_change.png"), p, width = 10, height = 7, dpi = 300)
print(p)
