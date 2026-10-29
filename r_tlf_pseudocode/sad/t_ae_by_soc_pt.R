################################################################################
# TABLE     : t_ae_by_soc_pt  (Single Ascending Dose)
# TITLE     : Treatment-Emergent Adverse Events by System Organ Class and
#             Preferred Term, by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y")
# NOTE      : ANALYSIS TEMPLATE. Counts = PARTICIPANTS with >=1 event (n_distinct USUBJID),
#             NOT event rows. n (%) per dose level; % denominator = SAFFL N per
#             dose level. SAD: parallel cohorts -> column = dose level
#             (dv$trtvar = TRT01A); columns ordered low->high by dose (TRT01AN),
#             placebo often pooled. SOC sorted by overall frequency desc; PT
#             within SOC desc. Single dose -> no accumulation.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                       # trtvar = TRT01A

# Planned safety columns come from the population source, including zero-event arms.
denom <- bign(adam$adsl, dv$trtvar, "SAFFL")
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")
rep <- ae_hierarchy(adae, dv$trtvar, denom)

ttl <- tfl_titles(num = "14.3.1.1", type = "Table",
   text = "Treatment-Emergent Adverse Events by System Organ Class and Preferred Term, by Dose Level",
   pop  = "Safety Population",
   foot = paste("SAD: each column = single ascending dose level (TRT01A), ordered",
                "low to high; placebo may be pooled across cohorts. A participant is",
                "counted once at each level. {meddra}. % = participants with the",
                "event / N in dose level."))

## rtables/gt rendering; split_cols_by(dv$trtvar) (ascending dose);
## SOC bold (level 1), PT indented (level 2).
print(rep)
