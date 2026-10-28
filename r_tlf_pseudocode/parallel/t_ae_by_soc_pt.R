################################################################################
# TABLE     : t_ae_by_soc_pt  (Parallel-group)
# TITLE     : Treatment-Emergent Adverse Events by System Organ Class and
#             Preferred Term
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y")
# NOTE      : ANALYSIS TEMPLATE. Counts = PARTICIPANTS with >=1 event (n_distinct USUBJID),
#             NOT event rows. n (%) per arm; % denominator = SAFFL N per arm.
#             SOC sorted by overall frequency desc; PT within SOC desc.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                 # trtvar = TRT01A

# Planned safety columns come from the population source, including zero-event arms.
denom <- bign(adam$adsl, dv$trtvar, "SAFFL")
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")
rep <- ae_hierarchy(adae, dv$trtvar, denom)

ttl <- tfl_titles(num = "14.3.1.1", type = "Table",
   text = "Treatment-Emergent Adverse Events by System Organ Class and Preferred Term",
   pop  = "Safety Population",
   foot = "A participant is counted once at each level. {meddra}. % = participants with the event / N in arm.")

## rtables/gt rendering; SOC bold (level 1), PT indented (level 2)
print(rep)
