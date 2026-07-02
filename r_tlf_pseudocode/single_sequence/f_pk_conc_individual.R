################################################################################
# FIGURE    : f_pk_conc_individual  (Single-/fixed-sequence DDI)
# TITLE     : Individual Plasma Concentration-Time Profiles by Participant
#             (Semi-Logarithmic)
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (AVAL = concentration; ATPTN nominal time; APERIOD)
# NOTE      : PSEUDOCODE. ONE PANEL PER PARTICIPANT (the within-participant DDI
#             "own-control" view, matching the SAS twin), with that participant's
#             Reference (victim alone) and Test (victim + perpetrator) period
#             profiles OVERLAID on the same axes, coloured by study PERIOD
#             (dv$byperiod). Nominal time grid (ATPTN), semilog y. Single-/fixed-
#             sequence DDI: each participant serves as their own control so the
#             interaction effect is read panel by panel. BLQ excluded from the
#             log plot.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # period via dv$byperiod (no sequence)

pc <- adam$adpc %>%
  filter(PKFL == "Y", ANL01FL == "Y",
         !(AVAL <= 0 | toupper(coalesce(AVALC,"")) == "BLQ")) %>%   # log plot: drop BLQ
  transmute(USUBJID, PARAM,
            period = .data[[dv$byperiod[2]]],           # APERIODC label: Reference / Test
            subj   = str_extract(USUBJID, "[^-]+$"),
            t      = ATPTN,                             # nominal time (same as SAS)
            conc   = AVAL) %>%
  arrange(subj, period, t)

ttl <- tfl_titles(num = "14.4.2.3", type = "Figure",
   text = "Individual Plasma Concentration-Time Profiles by Participant (Semi-Logarithmic)",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("One panel per participant; Reference and Test period profiles",
                "overlaid (study PERIOD, APERIODC) so each participant serves as",
                "own control. Semi-log y; BLQ omitted. Nominal sampling times.",
                "Period 1 = victim alone (reference), Period 2 = victim +",
                "perpetrator (test); fixed-sequence design (no randomized sequence)."))

## one panel per participant; Reference vs Test overlaid (colour = period)
p <- ggplot(pc, aes(t, conc, group = period, colour = period)) +
  geom_line(linewidth = 0.6) + geom_point(size = 1.2) +
  scale_y_log10() +
  facet_wrap(~ subj) +
  labs(x = "Nominal Time (h)", y = "Concentration (unit), log scale", colour = "Period",
       title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom")
# ggsave(file.path(env$out, "f_pk_conc_individual.png"), p, width = 10, height = 7, dpi = 300)
print(p)
