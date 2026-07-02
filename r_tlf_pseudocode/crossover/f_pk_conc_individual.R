################################################################################
# FIGURE    : f_pk_conc_individual  (Crossover - 2x2 or Williams)
# TITLE     : Individual Plasma Drug Concentration vs Time by Participant and
#             Treatment (Semilog)
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (AVAL = concentration; ATPTN nominal / ARRLT actual time;
#             APERIOD; TRTA; TRTSEQP)
# NOTE      : PSEUDOCODE. Spaghetti plot of individual concentration-time
#             profiles, one line per participant, faceted by participant (or small
#             multiples) with the two crossover periods distinguished by colour
#             = actual treatment (TRTA). Within-participant design -> each participant's
#             panel shows BOTH treatment profiles, enabling visual paired
#             comparison. Semilog y (log10); actual relative time (ARRLT) on x
#             for fidelity. BLQ-as-0 excluded by the >0 filter for the log axis.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # TRTA + APERIOD + TRTSEQP

pc <- adam$adpc %>%
  filter(PKFL == "Y", AVAL > 0, !is.na(ARRLT)) %>%   # >0 for log axis
  transmute(
    subj  = str_extract(USUBJID, "[^-]+$"),
    seq   = .data[[dv$seqvar]],                  # TRTSEQP planned sequence
    trt   = .data[[dv$trtvar]],                  # TRTA actual treatment (colour)
    per   = .data[[dv$byperiod[2]]],             # APERIODC label (linetype option)
    time  = ARRLT,                               # actual relative time (h)
    conc  = AVAL) %>%
  arrange(subj, trt, time)

## --- per-participant panels; within each, one line per treatment (period) -----
p <- ggplot(pc, aes(time, conc, colour = trt, group = interaction(subj, trt))) +
  geom_line() +
  geom_point(size = 0.8) +
  scale_y_log10() +
  facet_wrap(~ subj, scales = "free_x") +       # one small panel per participant
  labs(x = "Actual Time Post-Dose (h)",
       y = "Concentration (log scale)",
       colour = "Treatment",
       caption = "Within-participant crossover: each panel overlays the participant's profiles across periods.") +
  theme_bw() +
  theme(legend.position = "bottom")

ttl <- tfl_titles(num = "14.4.2.3", type = "Figure",
   text = "Individual Plasma Drug Concentration vs Time by Participant and Treatment (Semilog)",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("One panel per participant; one line per actual treatment (TRTA),",
                "so both crossover periods appear together for paired visual comparison.",
                "Semilog y (concentrations > 0); x = actual relative time (h)."))

## render: facet_wrap paginates via ggforce::facet_wrap_paginate for many
## participants; ggsave one multi-page PDF. print() one page here.
print(p)
