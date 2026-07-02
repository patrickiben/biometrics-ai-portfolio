################################################################################
# FIGURE    : f_vitals_change  (Crossover - 2x2 or Williams)
# TITLE     : Mean Change from Baseline in Vital Signs over Time by Treatment
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADVS (PARAMCD = SYSBP, DIABP, PULSE)
# NOTE      : PSEUDOCODE. Within-participant crossover view: mean (+/-SE) CHG from
#             the PERIOD baseline plotted over scheduled visit, one line per
#             treatment (dv$trtvar = TRTA). Each participant contributes a within-
#             period change profile to the treatment given in that period.
#             Faceted by parameter; CHG/BASE taken as-is from ADVS (no re-deriv.).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar = TRTA; byperiod = APERIOD/APERIODC

vs <- adam$advs %>%
  filter(SAFFL == "Y", ANL01FL == "Y",
         PARAMCD %in% c("SYSBP","DIABP","PULSE"), !is.na(CHG)) %>%
  mutate(trt = .data[[dv$trtvar]])

## mean +/- SE of CHG by treatment x parameter x scheduled visit
mc <- vs %>%
  group_by(PARAM, AVISITN, AVISIT, trt) %>%
  summarise(n    = sum(!is.na(CHG)),
            mean = mean(CHG, na.rm = TRUE),
            se   = sd(CHG, na.rm = TRUE) / sqrt(pmax(n, 1)),
            .groups = "drop") %>%
  mutate(lo = mean - se, hi = mean + se)

ttl <- tfl_titles(num = "14.3.7.2", type = "Figure",
   text = "Mean Change from Baseline in Vital Signs over Time by Treatment",
   pop  = "Safety Population",
   foot = "Points = mean change from period baseline; error bars = +/-1 SE. One profile per treatment (crossover, within-participant). Dashed line = no change.")

## dodge so overlapping treatment means/SE bars are readable at each visit
pd <- position_dodge(width = 0.3)
p <- ggplot(mc, aes(x = AVISITN, y = mean, colour = trt, group = trt)) +
  geom_hline(yintercept = 0, linetype = "dashed") +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.2, position = pd) +
  geom_line(position = pd) + geom_point(size = 2, position = pd) +
  facet_wrap(~ PARAM, scales = "free_y") +
  scale_x_continuous(breaks = sort(unique(mc$AVISITN)),
                     labels = function(b) mc$AVISIT[match(b, mc$AVISITN)]) +
  labs(x = "Scheduled visit", y = "Mean change from baseline (+/- SE)",
       colour = "Treatment", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom",
                     axis.text.x = element_text(angle = 45, hjust = 1))
# ggsave(file.path(env$out, "f_vitals_change.png"), p, width = 10, height = 6, dpi = 300)
print(p)
