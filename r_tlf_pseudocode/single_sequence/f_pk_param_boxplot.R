################################################################################
# FIGURE    : f_pk_param_boxplot  (Single-/fixed-sequence DDI)
# TITLE     : Distribution of Plasma PK Parameters of the Victim Drug by Period
#             (Box Plot)
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (PARAMCD/PARAM; AVAL; APERIOD/APERIODC; USUBJID)
# NOTE      : PSEUDOCODE. Box plots of key exposure parameters (Cmax, AUClast,
#             AUCinf) by study PERIOD. Single-/fixed-sequence DDI: x = study
#             PERIOD (dv$byperiod) -- Period 1 = victim alone (reference),
#             Period 2 = victim + perpetrator (test); overlay individual points
#             with within-participant pairing lines (group = USUBJID) so the paired
#             reference-vs-test structure is visible (the DDI read-out). Exposure
#             params are right-skewed -> log10 y-axis (consistent with the
#             log-scale ratio analysis); AVAL > 0 filter for the log axis.
#             Faceted by parameter (free y scales since units differ).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # x = study PERIOD (no sequence)

params <- c("CMAX","AUCLST","AUCIFO")

pp <- adam$adpp %>%
  filter(PKFL == "Y", PARAMCD %in% params, AVAL > 0) %>%   # >0 for log axis
  transmute(
    subj   = USUBJID,
    period = .data[[dv$byperiod[2]]],           # APERIODC label: Reference / Test (x)
    PARAM  = factor(PARAMCD, levels = params,
                    labels = c("Cmax","AUClast","AUCinf")),
    val    = AVAL)

## --- boxplot + within-participant pairing lines + jittered points -------------
p <- ggplot(pp, aes(period, val)) +
  geom_boxplot(outlier.shape = NA, width = 0.5) +
  ## connect each participant's reference and test values (within-participant DDI pairing)
  geom_line(aes(group = subj), colour = "grey60", alpha = 0.4,
            position = position_dodge(0)) +
  geom_point(aes(group = subj), alpha = 0.5, size = 1.2) +
  scale_y_log10() +
  facet_wrap(~ PARAM, scales = "free_y") +      # different units per parameter
  labs(x = "Period", y = "Parameter Value (log scale)",
       caption = "Grey lines connect each participant's reference vs test value (within-participant pairing).") +
  theme_bw()

ttl <- tfl_titles(num = "14.4.4.2", type = "Figure",
   text = "Distribution of Plasma Pharmacokinetic Parameters of the Victim Drug by Period (Box Plot)",
   pop  = "Pharmacokinetic Parameter Population",
   foot = paste("Box = median + IQR; whiskers 1.5*IQR. Points = individual participants;",
                "grey lines connect each participant's reference vs test value (within-participant DDI design).",
                "Log10 y-axis (values > 0); x = study PERIOD (Period 1 = victim alone / reference,",
                "Period 2 = victim + perpetrator / test); fixed-sequence design (no randomized sequence)."))

## render: ggsave(file.path(env$out, "f_pk_param_boxplot.png"), p, ...)
print(p)
