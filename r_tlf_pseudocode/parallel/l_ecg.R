################################################################################
# LISTING   : l_ecg  (Parallel-group)
# TITLE     : Listing of Electrocardiogram (ECG) Results
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADEG
# NOTE      : PSEUDOCODE. One row per ECG assessment, ordered by participant,
#             parameter, then visit/timepoint. Shows observed value, baseline,
#             change, range indicator, and the overall ECG interpretation.
#             Parallel: one treatment per participant; column = dv$trtvar (TRT01A).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")

eg <- adam$adeg %>% filter(SAFFL == "Y") %>%
  transmute(
    Treatment   = .data[[dv$trtvar]],
    Participant     = str_extract(USUBJID, "[^-]+$"),    # short site-participant id
    Parameter   = PARAM,
    PARAMCD,
    Visit       = AVISIT,
    AVISITN,
    Timepoint   = ATPT,
    ATPTN,
    `Result`    = AVAL,
    `Unit`      = AVALU,
    `Baseline`  = BASE,
    `Change`    = CHG,
    `Range Ind` = ANRIND,                            # LOW / NORMAL / HIGH
    `Interpretation` = if ("EGINTP" %in% names(adam$adeg)) EGINTP else NA_character_,  # overall read
    `Anl Flag`  = ANL01FL,
    ADT) %>%
  arrange(Treatment, Participant, PARAMCD, AVISITN, ATPTN, ADT)   # sort on numeric keys/date

ttl <- tfl_titles(num = "16.2.8.1", type = "Listing",
   text = "Listing of Electrocardiogram (ECG) Results",
   pop = "Safety Population",
   foot = "Change = result - baseline. QTcF = Fridericia-corrected QT. Interpretation = investigator overall ECG read. Anl Flag = record used in by-visit summaries.")

## render: one block per treatment (page break), columns as ordered above
## listings::create_listing(eg, ...) or gt::gt(eg %>% select(-ADT, -PARAMCD, -AVISITN, -ATPTN))
print(eg %>% select(-ADT, -PARAMCD, -AVISITN, -ATPTN))
