################################################################################
# FIGURE    : f_pkpd_overlay  (Single-/Fixed-Sequence DDI)
# TITLE     : Mean Plasma Concentration and Pharmacodynamic Response over Time
#             by Period (PK/PD Overlay)
# POPULATION: PK Population (PKFL=="Y", concentration series) /
#             PD Population (PDFL=="Y", PD series) -- each flag applies only to
#             its own domain, matching the SAS twin
# INPUT     : ADPC (AVAL = plasma concentration; NRRELTM/ATPTN = nominal time),
#             ADPD (AVAL = PD response; ATPTN/AVISITN = nominal time);
#             APERIOD/APERIODC
# NOTE      : PSEUDOCODE. Dual-axis overlay matching the SAS twin: mean PK
#             concentration on a LOG10 (semilog) LEFT/primary y-axis vs mean PD
#             response on a LINEAR RIGHT/secondary y-axis, over a common
#             nominal-time axis. ggplot2 has one primary scale, so the figure is
#             built in log10-concentration space and the linear PD series is
#             rescaled into that space, with sec_axis() recovering the true linear
#             PD labels on the right (an explicit, monotone affine rescale --
#             this is the standard idiom for a log-primary / linear-secondary
#             overlay). Columns = PERIOD (APERIODC): Period 1 = reference (victim
#             alone), Period 2 = test (victim + perpetrator). Descriptive temporal
#             alignment, NOT a fitted PK/PD model. n per period x time from the
#             respective ADaM domain (ADPC/ADPD), NOT ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
options(tfl.study = env$study)
perC <- dv$byperiod[2]                          # character period label

PCCD <- "DRUGA"      # parent analyte (victim) in ADPC  (same pair as SAS twin)
PDCD <- "INHIB"      # PD endpoint in ADPD              (same pair as SAS twin)

## --- mean PK concentration by PERIOD x nominal time (ADPC) ------------------
## Time grid = coalesce(NRRELTM, ATPTN) (nominal relative time, h) and arithmetic
## mean over all non-missing AVAL -- same rule and denominator as the SAS twin.
## Non-positive means simply do not render on the log axis (matching SAS rowaxis
## type=log); they are NOT dropped before averaging.
pk <- adam$adpc %>%
  filter(PKFL == "Y", PARAMCD == PCCD, !is.na(AVAL)) %>%
  mutate(reltm = dplyr::coalesce(NRRELTM, ATPTN)) %>%
  group_by(per = .data[[perC]], tpt = reltm) %>%
  summarise(n = n(), conc = mean(AVAL, na.rm = TRUE), .groups = "drop")

## --- mean PD response by PERIOD x nominal time (ADPD) ----------------------
## Time grid = coalesce(ATPTN, AVISITN) to align onto the PK grid -- same rule as
## the SAS twin; n = record count (PROC MEANS n).
pd <- adam$adpd %>%
  filter(PDFL == "Y", PARAMCD == PDCD, !is.na(AVAL)) %>%
  mutate(reltm = dplyr::coalesce(ATPTN, AVISITN)) %>%
  group_by(per = .data[[perC]], tpt = reltm) %>%
  summarise(n = n(), resp = mean(AVAL, na.rm = TRUE), .groups = "drop")

ttl <- tfl_titles(num = "14.4.5.1", type = "Figure",
   text = "Mean Plasma Concentration and Pharmacodynamic Response over Time by Period",
   pop  = "Pharmacokinetic and Pharmacodynamic Populations",
   foot = paste("Single-fixed-sequence DDI: Period 1 = reference (victim alone),",
                "Period 2 = test (victim + perpetrator). Left axis (LOG10,",
                "semilog) = mean plasma concentration (", PCCD, "); right axis",
                "(linear) = mean PD response (", PDCD, "); common nominal-time",
                "axis. Arithmetic mean over all non-missing values at each period x",
                "nominal time (ADPC/ADPD). Single-/fixed-sequence. Descriptive",
                "exposure-response, not a fitted PK/PD model."))

xbreaks <- sort(unique(c(pk$tpt, pd$tpt)))

## --- dual-axis overlay: concentration LOG10 (left) + PD LINEAR (right) ------
## ggplot2 has a single primary scale, so the plot is drawn in log10-concentration
## space and the linear PD series is mapped into that space with a monotone affine
## rescale; sec_axis() then prints the TRUE linear PD values on the right axis.
## This matches the SAS twin (concentration = left/primary log10; PD = right/
## secondary linear) and the PK semi-log convention.
## log range uses positive means only (non-positive means do not render on a log
## axis, as in the SAS rowaxis type=log); the means themselves already include all
## non-missing AVAL, so the displayed range matches the SAS twin
clog <- log10(pk$conc[pk$conc > 0])            # concentration in log10 space
c_lo <- min(clog); c_hi <- max(clog)           # log10 conc range (left axis)
r_lo <- min(pd$resp, na.rm = TRUE); r_hi <- max(pd$resp, na.rm = TRUE)  # PD range
## affine map PD (linear) -> log10-conc space, and its inverse for sec_axis labels
to_log   <- function(resp) c_lo + (resp - r_lo) * (c_hi - c_lo) / (r_hi - r_lo)
from_log <- function(y)    r_lo + (y    - c_lo) * (r_hi - r_lo) / (c_hi - c_lo)

p <- ggplot() +
  ## concentration on the PRIMARY (left) LOG10 axis
  geom_line(data = pk, aes(tpt, log10(conc))) +
  geom_point(data = pk, aes(tpt, log10(conc)), size = 1.8) +
  ## PD response rescaled into log10 space, shown via the SECONDARY (right) axis
  geom_line(data = pd, aes(tpt, to_log(resp)), linetype = "longdash") +
  geom_point(data = pd, aes(tpt, to_log(resp)), size = 1.8, shape = 17) +
  facet_wrap(~ per) +                          # one column per PERIOD (ref vs test)
  scale_x_continuous(breaks = xbreaks) +
  scale_y_continuous(
    name     = sprintf("Mean concentration (%s), log10 scale", PCCD),
    labels   = function(y) sprintf("%g", 10^y),               # left = true conc
    sec.axis = sec_axis(~ from_log(.),
                        name = sprintf("Mean PD response (%s)", PDCD))) +  # right = linear PD
  labs(x = "Nominal time post-dose",
       title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw()

# ggsave(file.path(env$out, "f_pkpd_overlay.png"), p, width = 10, height = 7, dpi = 300)
print(p)
