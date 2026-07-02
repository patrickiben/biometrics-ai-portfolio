################################################################################
# FIGURE    : f_pk_conc_individual  (SAD - Single Ascending Dose / per-cohort)
# TITLE     : Individual Plasma Concentration-Time Profiles by Dose Cohort
#             (Semi-Logarithmic, Faceted by Cohort)
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (PARAMCD = analyte concentration; NRRELTM actual elapsed time)
# NOTE      : PSEUDOCODE. Spaghetti / faceted individual profiles on the ACTUAL
#             time grid (NRRELTM), semilog y. One line per participant, coloured by dose
#             cohort (TRT01A). SAD: single dosing occasion per participant, faceted
#             by cohort so the ascending dose groups do not overplot. BLQ
#             excluded from the log plot.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")

pc <- adam$adpc %>%
  filter(PKFL == "Y", ANL01FL == "Y",
         !(AVAL <= 0 | toupper(coalesce(AVALC,"")) == "BLQ")) %>%   # log plot: drop BLQ
  transmute(USUBJID, PARAM,
            trt  = .data[[dv$trtvar]],                  # = dose cohort
            trtn = .data[[dv$trtnvar]],
            subj = str_extract(USUBJID, "[^-]+$"),
            t    = NRRELTM,                             # individual ACTUAL time (same var as SAS)
            conc = AVAL) %>%
  mutate(trt = factor(trt, levels = unique(trt[order(trtn)]))) %>% # ascending dose order
  arrange(trt, USUBJID, t)

ttl <- tfl_titles(num = "14.4.2.2", type = "Figure",
   text = "Individual Plasma Concentration-Time Profiles by Dose Cohort",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("One line per participant on actual sampling times; semi-log y-axis.",
                "BLQ values omitted from the logarithmic plot.",
                "Colour / facet = dose cohort (TRT01A); single ascending dose."))

## overlaid spaghetti, faceted by cohort so ascending dose groups don't overplot
p <- ggplot(pc, aes(t, conc, group = USUBJID, colour = trt)) +
  geom_line(alpha = 0.5) + geom_point(size = 0.9, alpha = 0.6) +
  scale_y_log10() +
  facet_wrap(~ trt) +
  labs(x = "Actual Time (h)", y = "Concentration (log scale)", colour = "Dose Cohort",
       title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom")

## alternative deliverable: one page per participant (facet_wrap(~ subj)) for the CSR appendix
# ggsave(file.path(env$out, "f_pk_conc_individual.png"), p, width = 10, height = 7, dpi = 300)
print(p)
