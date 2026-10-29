################################################################################
# TABLE     : t_ae_by_soc_pt  (Multiple Ascending Dose)
# TITLE     : Treatment-Emergent Adverse Events by System Organ Class and
#             Preferred Term, by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y")
# NOTE      : ANALYSIS TEMPLATE. MAD = parallel ascending-dose cohorts, repeated dosing;
#             one treatment per participant, so column = dose level (dv$trtvar =
#             TRT01A) ordered ascending by TRT01AN. Counts = PARTICIPANTS with >=1
#             event (n_distinct USUBJID), NOT event rows. n (%) per dose;
#             % denominator = SAFFL N per dose. SOC sorted by overall frequency
#             desc; PT within SOC desc.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # trtvar = TRT01A (dose level)

# Planned safety columns come from the population source, including zero-event arms.
denom <- bign(adam$adsl, dv$trtvar, "SAFFL")
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")
rep <- ae_hierarchy(adae, dv$trtvar, denom)

ttl <- tfl_titles(num = "14.3.1.1", type = "Table",
   text = "Treatment-Emergent Adverse Events by System Organ Class and Preferred Term, by Dose Level",
   pop  = "Safety Population",
   foot = paste("MAD: parallel ascending-dose cohorts, repeated dosing; columns = dose",
                "level (ascending). A participant is counted once at each level. {meddra}.",
                "% = participants with the event / N at dose."))

## rtables/gt rendering; split_cols_by(dose) ascending; SOC bold (level 1),
## PT indented (level 2)
print(rep)
