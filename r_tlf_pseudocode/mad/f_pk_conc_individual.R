################################################################################
# FIGURE    : f_pk_conc_individual  (MAD - Multiple Ascending Dose / per-cohort)
# TITLE     : Individual Plasma Concentration-Time Profiles by Dose Cohort and
#             Dosing Day (Semi-Logarithmic, Faceted)
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (PARAMCD = analyte concentration; ATM actual elapsed time;
#             AVISIT/ADY dosing day)
# NOTE      : PSEUDOCODE. Spaghetti / faceted individual profiles on the ACTUAL
#             time grid (ATM), semilog y. One line per participant, coloured by dose
#             cohort (TRT01A). MAD: repeated daily dosing -> facet by dose cohort
#             x dosing day (Day 1 single dose vs Day N steady state) so the
#             ascending cohorts and the two occasions do not overplot. BLQ
#             excluded from the log plot.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")

pc <- adam$adpc %>%
  filter(PKFL == "Y", ANL01FL == "Y",
         !(AVAL <= 0 | toupper(coalesce(AVALC,"")) == "BLQ")) %>%   # log plot: drop BLQ
  transmute(USUBJID, PARAM,
            trt  = .data[[dv$trtvar]],                  # = dose cohort
            trtn = .data[[dv$trtnvar]],
            subj = str_extract(USUBJID, "[^-]+$"),
            day  = AVISIT,                              # dosing occasion (Day 1 ... Day N)
            t    = ATM,                                 # individual ACTUAL time
            conc = AVAL) %>%
  mutate(trt = factor(trt, levels = unique(trt[order(trtn)])),  # ascending dose order
         day = factor(day)) %>%
  arrange(trt, USUBJID, day, t)

ttl <- tfl_titles(num = "14.4.2.2", type = "Figure",
   text = "Individual Plasma Concentration-Time Profiles by Dose Cohort and Dosing Day",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("One line per participant on actual sampling times; semi-log y-axis.",
                "BLQ values omitted from the logarithmic plot.",
                "Colour = dose cohort (TRT01A); facet = dose cohort x dosing day",
                "(Day 1 single dose vs Day N steady state). Repeated daily dosing."))

## overlaid spaghetti, faceted by cohort x dosing day so groups/occasions don't overplot
p <- ggplot(pc, aes(t, conc, group = USUBJID, colour = trt)) +
  geom_line(alpha = 0.5) + geom_point(size = 0.9, alpha = 0.6) +
  scale_y_log10() +
  facet_grid(day ~ trt) +
  labs(x = "Actual Time (h)", y = "Concentration (log scale)", colour = "Dose Cohort",
       title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom")

## alternative deliverable: one page per participant (facet_wrap(~ subj)) for the CSR appendix
# ggsave(file.path(env$out, "f_pk_conc_individual.png"), p, width = 10, height = 7, dpi = 300)
print(p)
