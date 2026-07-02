################################################################################
# FIGURE    : f_pkpd_overlay  (Multiple Ascending Dose)
# TITLE     : Mean Plasma Concentration and Pharmacodynamic Response over the
#             Multiple-Dose Period by Dose Level (Dual-Axis Overlay)
# POPULATION: PK + PD-Evaluable Population (PKFL == "Y" and PDFL == "Y")
# INPUT     : ADPC (AVAL = concentration), ADPD (AVAL = PD response), matched on
#             treatment-time
# NOTE      : PSEUDOCODE. Overlays mean PD response over time (LEFT axis, linear)
#             with mean PK concentration-time (RIGHT axis, SEMILOG log10), faceted
#             by DOSE LEVEL -- matching the SAS house convention.
#             MAD = parallel cohorts, REPEATED dosing, one dose level per participant
#             -> facet/group = dv$trtvar (TRT01A = dose level; placebo pooled).
#             Repeated dosing -> the x axis is continuous treatment-time over the
#             multiple-dose period (ADY + within-day ATPTN), so accumulation of
#             both exposure and effect across the saw-tooth dosing profile is
#             visible, and the approach of trough exposure / trough effect to a
#             plateau (steady state) can be read across days. Descriptive
#             temporal alignment of exposure vs effect; NOT a fitted PK/PD model.
#             n per dose x time from the respective ADaM domain (ADPC/ADPD), NOT
#             ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                      # facet = TRT01A (= dose level)

PCCD <- "CONC"       # parent analyte concentration in ADPC (matches SAS PCPARM)
PDCD <- "PDMARK1"    # PD biomarker endpoint in ADPD (matches SAS PDPARM)

## consistent dose-level ordering (numeric) for both domains' facets
dose_levels <- adam$adpc %>%
  filter(PKFL == "Y") %>%
  distinct(trt = .data[[dv$trtvar]], dosen = .data[[dv$trtnvar]]) %>%
  arrange(dosen) %>% pull(trt)

## continuous treatment-time helper: study day + fractional within-day hours
add_ttime <- function(df) df %>% mutate(ttime = ADY + coalesce(ATPTN, 0) / 24)

## --- mean PK concentration by dose level x treatment-time (ADPC) ------------
pk <- adam$adpc %>%
  filter(PKFL == "Y", PARAMCD == PCCD, !is.na(AVAL)) %>%
  add_ttime() %>%
  group_by(trt = .data[[dv$trtvar]], ttime) %>%
  summarise(n = n_distinct(USUBJID), conc = mean(AVAL, na.rm = TRUE), .groups = "drop")

## --- mean PD response by dose level x treatment-time (ADPD) -----------------
pd <- adam$adpd %>%
  filter(PDFL == "Y", PARAMCD == PDCD, !is.na(AVAL)) %>%
  add_ttime() %>%
  group_by(trt = .data[[dv$trtvar]], ttime) %>%
  summarise(n = n_distinct(USUBJID), resp = mean(AVAL, na.rm = TRUE), .groups = "drop")

## --- dual-axis overlay: PD on the PRIMARY (left, LINEAR) axis; concentration on
##     the SECONDARY (right, SEMILOG log10) axis -- matching the SAS convention.
## A single ggplot linear axis cannot host a log primary, so map log10(conc) into
## the PD axis range and back-transform with a log-scaled sec_axis (10^ labels).
lc      <- log10(pk$conc[pk$conc > 0])
log_min <- min(lc, na.rm = TRUE)                       # log10 concentration range
log_max <- max(lc, na.rm = TRUE)
pd_min  <- min(pd$resp, na.rm = TRUE)                  # PD (primary) axis range
pd_max  <- max(pd$resp, na.rm = TRUE)
## linear map: log10(conc) -> PD axis units, and its inverse for the sec_axis
to_pd   <- function(logc) pd_min + (logc - log_min) / (log_max - log_min) * (pd_max - pd_min)
to_logc <- function(y)    log_min + (y - pd_min) / (pd_max - pd_min) * (log_max - log_min)

ov <- bind_rows(
  pd %>% transmute(trt, ttime, y = resp,                       series = "PD response"),
  pk %>% filter(conc > 0) %>%
         transmute(trt, ttime, y = to_pd(log10(conc)),         series = "PK concentration")) %>%
  mutate(trt = factor(trt, levels = dose_levels))     # ascending-dose panel order

## right-axis breaks at decade concentrations, placed via the log->PD map
conc_breaks <- 10 ^ seq(floor(log_min), ceiling(log_max))
conc_breaks <- conc_breaks[conc_breaks >= 10^log_min & conc_breaks <= 10^log_max]

ttl <- tfl_titles(num = "14.4.5.1", type = "Figure",
   text = "Mean Plasma Concentration and Pharmacodynamic Response over the Multiple-Dose Period by Dose Level",
   pop  = "PK- and PD-Evaluable Population",
   foot = paste("Left axis = mean PD response (", PDCD, "); right axis (semilog) = mean concentration (",
                PCCD, "). Means over PK-/PD-evaluable participants at each time (ADPC/ADPD), not ADSL.",
                "Multiple ascending dose: one panel per dose level (placebo pooled);",
                "x axis = continuous treatment-time over the repeated-dose period so the",
                "accumulation/saw-tooth profile and approach to steady state are visible.",
                "Descriptive temporal overlay, not a fitted PK/PD model."))

p <- ggplot(ov, aes(ttime, y, colour = series, linetype = series)) +
  geom_line() + geom_point(size = 1.4) +
  facet_wrap(~ trt) +                       # one panel per dose level
  scale_y_continuous(
    name = sprintf("Mean PD response (%s)", PDCD),                    # PRIMARY = PD, linear
    sec.axis = sec_axis(~ 10 ^ to_logc(.),                            # SECONDARY = concentration, semilog
                        name   = sprintf("Mean concentration (%s, log scale)", PCCD),
                        breaks = conc_breaks)) +
  scale_x_continuous(name = "Treatment time (study day)") +
  labs(colour = NULL, linetype = NULL,
       title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom")
# ggsave(file.path(env$out, "f_pkpd_overlay.png"), p, width = 10, height = 6, dpi = 300)
print(p)
