################################################################################
# FIGURE    : f_pk_param_boxplot  (Crossover - 2x2 or Williams)
# TITLE     : Distribution of Plasma PK Parameters by Treatment (Box Plot)
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (PARAMCD/PARAM; AVAL; TRTA; TRTSEQP; USUBJID)
# NOTE      : PSEUDOCODE. Box plots of key exposure parameters (Cmax, AUClast,
#             AUCinf) by treatment. Crossover: x = actual treatment (dv$trtvar);
#             overlay individual points with within-participant pairing lines
#             (group = USUBJID) so the paired structure is visible. Exposure
#             params are right-skewed -> plot on a log10 y-axis (consistent with
#             log-scale geometric analysis); AVAL > 0 filter for the log axis.
#             Faceted by parameter (free y scales since units differ).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # TRTA + APERIOD + TRTSEQP

params <- c("CMAX","AUCLST","AUCIFO")

pp <- adam$adpp %>%
  filter(PKFL == "Y", PARAMCD %in% params, AVAL > 0) %>%   # >0 for log axis
  transmute(
    subj  = USUBJID,
    trt   = .data[[dv$trtvar]],                 # actual treatment on x
    seq   = .data[[dv$seqvar]],                 # planned sequence (optional facet/colour)
    PARAM = factor(PARAMCD, levels = params,
                   labels = c("Cmax","AUClast","AUCinf")),
    val   = AVAL)

## --- boxplot + within-participant pairing lines + jittered points -------------
p <- ggplot(pp, aes(trt, val)) +
  geom_boxplot(outlier.shape = NA, width = 0.5) +
  ## connect each participant's two treatments (within-participant crossover pairing)
  geom_line(aes(group = subj), colour = "grey60", alpha = 0.4,
            position = position_dodge(0)) +
  geom_point(aes(group = subj), alpha = 0.5, size = 1.2) +
  scale_y_log10() +
  facet_wrap(~ PARAM, scales = "free_y") +      # different units per parameter
  labs(x = "Treatment", y = "Parameter Value (log scale)",
       caption = "Grey lines connect each participant's values across treatments (within-participant pairing).") +
  theme_bw()

ttl <- tfl_titles(num = "14.4.4.2", type = "Figure",
   text = "Distribution of Plasma Pharmacokinetic Parameters by Treatment (Box Plot)",
   pop  = "Pharmacokinetic Parameter Population",
   foot = paste("Box = median + IQR; whiskers 1.5*IQR. Points = individual participants;",
                "grey lines connect each participant across treatments (within-participant design).",
                "Log10 y-axis (values > 0); x = actual treatment (TRTA)."))

## render: ggsave(file.path(env$out, "f_pk_param_boxplot.png"), p, ...)
print(p)
