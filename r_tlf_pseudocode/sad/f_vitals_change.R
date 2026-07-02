################################################################################
# FIGURE    : f_vitals_change  (Single Ascending Dose)
# TITLE     : Mean (+/-SE) Change from Baseline in Vital Signs by Visit
# POPULATION: Safety Population (SAFFL == "Y"), post-baseline
# INPUT     : ADVS (PARAMCD in SYSBP, DIABP, PULSE -- same panel as the SAS twin)
# NOTE      : PSEUDOCODE. Mean change from baseline (CHG) with +/-1 SE error
#             bars over scheduled post-baseline visits, one line per DOSE COHORT,
#             faceted by parameter. SAD: between-cohort comparison along ascending
#             dose, colour = dv$trtvar (TRT01A = dose level), ordered low -> high
#             so any dose-related drift in a vital sign reads left -> right.
#             Single dose -> no within-participant/period structure (no dv$byperiod).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")

## dose-cohort colour order: placebo first, then ascending by TRT01AN ----------
dose_order <- adam$adsl %>% filter(SAFFL == "Y") %>%
  distinct(trt = .data[[dv$trtvar]], trtn = .data[[dv$trtnvar]]) %>%
  arrange(trtn) %>% pull(trt)

## post-baseline analysis records (CHG defined); scheduled timepoints only
vs <- adam$advs %>%
  filter(SAFFL == "Y", ANL01FL == "Y", AVISITN > 0, !is.na(CHG),
         PARAMCD %in% c("SYSBP","DIABP","PULSE")) %>%   # same panel as SAS twin
  mutate(trt    = factor(.data[[dv$trtvar]], levels = dose_order),  # ascending dose
         PARAM  = factor(PARAM),
         AVISIT = factor(AVISIT, levels = unique(AVISIT[order(AVISITN)])))

## mean +/- SE of change by cohort x param x visit
sumdat <- vs %>%
  group_by(PARAM, AVISIT, AVISITN, trt) %>%
  summarise(n    = sum(!is.na(CHG)),
            mean = mean(CHG, na.rm = TRUE),
            se   = sd(CHG, na.rm = TRUE) / sqrt(n),
            .groups = "drop") %>%
  mutate(lo = mean - se, hi = mean + se)

ttl <- tfl_titles(num = "14.3.7.2", type = "Figure",
   text = "Mean (+/-SE) Change from Baseline in Vital Signs by Visit",
   pop  = "Safety Population",
   foot = "Lines = ascending SAD dose cohorts (placebo pooled). Points = cohort mean change from baseline; error bars = +/-1 SE. Baseline = last value prior to single dose. Dashed line = no change.")

pd <- position_dodge(width = 0.3)
p <- ggplot(sumdat, aes(x = AVISIT, y = mean, colour = trt, group = trt)) +
  geom_hline(yintercept = 0, linetype = "dashed") +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.2, position = pd) +
  geom_line(position = pd) +
  geom_point(size = 2, position = pd) +
  facet_wrap(~ PARAM, scales = "free_y") +
  scale_colour_viridis_d(option = "C", end = 0.9) +   # ordinal dose -> sequential ramp
  labs(x = "Visit", y = "Mean change from baseline (+/-SE)",
       colour = "Dose cohort", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 45, hjust = 1))
# ggsave(file.path(env$out, "f_vitals_change.png"), p, width = 10, height = 7, dpi = 300)
print(p)
