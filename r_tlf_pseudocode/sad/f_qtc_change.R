################################################################################
# FIGURE    : f_qtc_change  (Single Ascending Dose)
# TITLE     : Mean (+/-95% CI) Change from Baseline in QTcF by Dose and Timepoint
# POPULATION: Safety Population (SAFFL == "Y"), post-baseline
# INPUT     : ADEG (PARAMCD == "QTCF")
# NOTE      : PSEUDOCODE. Descriptive mean change-from-baseline (CHG) QTcF with
#             95% confidence-interval error bars over nominal post-dose timepoints
#             (ATPTN), one line per DOSE COHORT. Horizontal reference lines at 0 ms
#             and at the ICH E14 thresholds of 30 ms and 60 ms. Descriptive only
#             (no model embedded). SAD: between-cohort comparison along ascending
#             dose, colour = dv$trtvar (TRT01A = dose level), ordered low -> high.
#             Single dose -> profile is the Day-1 post-dose time course (ATPTN),
#             not multi-day accumulation.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")

## dose-cohort colour order: placebo first, then ascending by TRT01AN ----------
dose_order <- adam$adsl %>% filter(SAFFL == "Y") %>%
  distinct(trt = .data[[dv$trtvar]], trtn = .data[[dv$trtnvar]]) %>%
  arrange(trtn) %>% pull(trt)

## post-baseline QTcF analysis records (CHG defined); x-axis = nominal post-dose
## timepoint (ATPTN), tick labels = ATPT text ordered by ATPTN.
eg <- adam$adeg %>%
  filter(SAFFL == "Y", ANL01FL == "Y", PARAMCD == "QTCF", !is.na(CHG)) %>%
  mutate(trt = factor(.data[[dv$trtvar]], levels = dose_order),
         tp  = factor(ATPT, levels = unique(ATPT[order(ATPTN)])))

## descriptive mean +/- 95% CI of change by cohort x timepoint
sumdat <- eg %>%
  group_by(trt, tp) %>%
  summarise(n    = sum(!is.na(CHG)),
            mean = mean(CHG, na.rm = TRUE),
            se   = sd(CHG, na.rm = TRUE) / sqrt(n),
            lo   = mean - qt(0.975, df = pmax(n - 1, 1)) * se,   # 95% CI of mean
            hi   = mean + qt(0.975, df = pmax(n - 1, 1)) * se,
            .groups = "drop")

ttl <- tfl_titles(num = "14.3.5.3", type = "Figure",
   text = "Mean (+/-95% CI) Change from Baseline in QTcF by Dose and Timepoint",
   pop  = "Safety Population",
   foot = "Lines = ascending SAD dose cohorts (placebo pooled). QTcF = Fridericia-corrected QT. Points = descriptive cohort mean change; error bars = 95% confidence interval. Horizontal reference lines at 0 ms and at the ICH E14 thresholds of 30 ms and 60 ms. Descriptive only (no model embedded). Baseline = pre-dose; profile = Day 1 post-single-dose time course.")

pd <- position_dodge(width = 0.3)
p <- ggplot(sumdat, aes(x = tp, y = mean, colour = trt, group = trt)) +
  geom_hline(yintercept = 0,  linetype = "solid") +
  geom_hline(yintercept = 30, linetype = "dashed", colour = "grey50") +   # 30 ms (E14)
  geom_hline(yintercept = 60, linetype = "dashed", colour = "grey50") +   # 60 ms (E14)
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.2, position = pd) +
  geom_line(position = pd) +
  geom_point(size = 2, position = pd) +
  scale_colour_viridis_d(option = "C", end = 0.9) +   # ordinal dose -> sequential ramp
  labs(x = "Nominal post-dose timepoint", y = "Mean change in QTcF from baseline (+/-95% CI), ms",
       colour = "Dose cohort", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 45, hjust = 1))
# ggsave(file.path(env$out, "f_qtc_change.png"), p, width = 9, height = 6, dpi = 300)
print(p)
