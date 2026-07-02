################################################################################
# FIGURE    : f_pkpd_overlay  (Parallel-group)
# TITLE     : Mean Plasma Concentration and Pharmacodynamic Response over Time
#             by Treatment (Dual-Axis Overlay)
# POPULATION: PK + PD-Evaluable Population (PKFL == "Y" and PDFL == "Y")
# INPUT     : ADPC (AVAL = concentration), ADPD (AVAL = PD response), matched on
#             nominal time
# NOTE      : PSEUDOCODE. Overlays mean PK concentration-time (left axis) with
#             mean PD response over time (right axis), faceted by treatment.
#             Parallel-group: one treatment per participant -> facet/group =
#             dv$trtvar (TRT01A, = dose for ascending-dose layouts). Descriptive
#             temporal alignment of exposure vs effect; NOT a fitted PK/PD model.
#             n per treatment x time from the respective ADaM domain, NOT ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")

PCCD <- "DRUGA"      # parent analyte in ADPC
PDCD <- "INHIB"      # PD endpoint in ADPD

## --- mean PK concentration by treatment x nominal time (ADPC) ---------------
pk <- adam$adpc %>%
  filter(PKFL == "Y", PARAMCD == PCCD, !is.na(AVAL)) %>%
  group_by(trt = .data[[dv$trtvar]], tpt = ATPTN) %>%
  summarise(n = n_distinct(USUBJID), conc = mean(AVAL, na.rm = TRUE), .groups = "drop")

## --- mean PD response by treatment x nominal time (ADPD) --------------------
pd <- adam$adpd %>%
  filter(PDFL == "Y", PARAMCD == PDCD, !is.na(AVAL)) %>%
  group_by(trt = .data[[dv$trtvar]], tpt = ATPTN) %>%
  summarise(n = n_distinct(USUBJID), resp = mean(AVAL, na.rm = TRUE), .groups = "drop")

## --- rescale PD onto the PK axis for a shared-y dual-axis overlay -----------
## scale factor maps PD range onto PK range so both curves are visible
sf <- max(pk$conc, na.rm = TRUE) / max(pd$resp, na.rm = TRUE)
ov <- bind_rows(
  pk %>% transmute(trt, tpt, y = conc,      series = "PK concentration"),
  pd %>% transmute(trt, tpt, y = resp * sf, series = "PD response"))

ttl <- tfl_titles(num = "14.4.5.1", type = "Figure",
   text = "Mean Plasma Concentration and Pharmacodynamic Response over Time by Treatment",
   pop  = "PK- and PD-Evaluable Population",
   foot = paste("Left axis = mean concentration (", PCCD, "); right axis = mean PD response (",
                PDCD, "). Means over PK-/PD-evaluable participants at each nominal time (ADPC/ADPD).",
                "Descriptive temporal overlay, not a fitted PK/PD model."))

p <- ggplot(ov, aes(tpt, y, colour = series, linetype = series)) +
  geom_line() + geom_point(size = 1.8) +
  facet_wrap(~ trt) +                       # one panel per treatment (= dose)
  scale_y_continuous(
    name = sprintf("Mean concentration (%s)", PCCD),
    sec.axis = sec_axis(~ . / sf, name = sprintf("Mean PD response (%s)", PDCD))) +
  scale_x_continuous(breaks = sort(unique(ov$tpt))) +
  labs(x = "Nominal time post-dose", colour = NULL, linetype = NULL,
       title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom")
# ggsave(file.path(env$out, "f_pkpd_overlay.png"), p, width = 10, height = 6, dpi = 300)
print(p)
