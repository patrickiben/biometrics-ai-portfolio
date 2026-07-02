################################################################################
# FIGURE    : f_pk_conc_individual  (Parallel-group / per-dose)
# TITLE     : Individual Plasma Concentration-Time Profiles by Treatment
#             (Semi-Logarithmic, Faceted by Participant)
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (PARAMCD = analyte concentration; ATM actual elapsed time)
# NOTE      : PSEUDOCODE. Spaghetti / faceted individual profiles on the ACTUAL
#             time grid (ATM), semilog y. One line per participant, coloured by
#             treatment (= dose group, TRT01A). BLQ excluded from the log plot.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")

pc <- adam$adpc %>%
  filter(PKFL == "Y", ANL01FL == "Y",
         !(AVAL <= 0 | toupper(coalesce(AVALC,"")) == "BLQ")) %>%   # log plot: drop BLQ
  transmute(USUBJID, PARAM,
            trt  = .data[[dv$trtvar]],                  # = dose group
            subj = str_extract(USUBJID, "[^-]+$"),
            t    = ATM,                                 # individual ACTUAL time
            conc = AVAL) %>%
  arrange(trt, USUBJID, t)

ttl <- tfl_titles(num = "14.4.2.2", type = "Figure",
   text = "Individual Plasma Concentration-Time Profiles by Treatment",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("One line per participant on actual sampling times; semi-log y-axis.",
                "BLQ values omitted from the logarithmic plot.",
                "Colour / facet = treatment (dose group, TRT01A)."))

## overlaid spaghetti, faceted by treatment so dose groups don't overplot
p <- ggplot(pc, aes(t, conc, group = USUBJID, colour = trt)) +
  geom_line(alpha = 0.5) + geom_point(size = 0.9, alpha = 0.6) +
  scale_y_log10() +
  facet_wrap(~ trt) +
  labs(x = "Actual Time (h)", y = "Concentration (log scale)", colour = "Treatment",
       title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom")

## alternative deliverable: one page per participant (facet_wrap(~ subj)) for the CSR appendix
# ggsave(file.path(env$out, "f_pk_conc_individual.png"), p, width = 10, height = 7, dpi = 300)
print(p)
