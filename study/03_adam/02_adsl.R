################################################################################
# 03_adam/02_adsl.R: ADSL (one record per participant) with admiral 1.5.0, following
# the ad_adsl.R template pattern adapted to a 2x2 crossover (period variables
# TRxxSDTM/APxxSDTM/TRTxxA via derive_vars_period()). SYNTHETIC DATA ONLY.
# The PK and bioequivalence population flags (PKCFL, PKPFL, BEFL) need the NCA results,
# so 05_adpp.R adds them; this script builds everything else.
#
# Inputs : 03_adam/sdtm/{dm,ex,ds,vs}.csv
# Outputs: object `adsl_core` (used by 03_adpc.R, 04_adae.R, 05_adpp.R)
################################################################################
suppressPackageStartupMessages({ library(admiral); library(lubridate) })

dm <- read_sdtm("dm"); ex <- read_sdtm("ex"); ds <- read_sdtm("ds"); vs <- read_sdtm("vs")

ex_ext <- ex %>%
  derive_vars_dtm(dtc = EXSTDTC, new_vars_prefix = "EXST", time_imputation = "first") %>%
  derive_vars_dtm(dtc = EXENDTC, new_vars_prefix = "EXEN", time_imputation = "first") %>%
  mutate(TRTA = ifelse(grepl("TEST", EXTRT), "Test", "Reference"), APERIOD = as.integer(VISITNUM))

## period reference dataset: one record per participant and period
next_start <- ex_ext %>% group_by(USUBJID) %>% arrange(APERIOD, .by_group = TRUE) %>%
  mutate(next_dose = lead(EXSTDTM)) %>% ungroup()
eos <- ds %>% filter(DSCAT == "DISPOSITION EVENT") %>%
  derive_vars_dt(dtc = DSSTDTC, new_vars_prefix = "EOS") %>% select(STUDYID, USUBJID, EOSDT)
period_ref <- next_start %>% left_join(eos, by = c("STUDYID", "USUBJID")) %>%
  transmute(STUDYID, USUBJID, APERIOD,
            APERSDTM = EXSTDTM,
            APEREDTM = if_else(is.na(next_dose),
                               as.POSIXct(paste(EOSDT, "23:59:59"), tz = "UTC"),
                               next_dose - 60),          # a period ends one minute before the next dose
            TRTA, TRTAN = ifelse(TRTA == "Test", 1L, 2L))

adsl_core <- dm %>%
  select(-DOMAIN) %>%
  mutate(TRTSEQP = ARMCD, TRT01P = ifelse(ARMCD == "TR", "Test", "Reference"),
         TRT02P = ifelse(ARMCD == "TR", "Reference", "Test"),
         TRT01PN = ifelse(TRT01P == "Test", 1L, 2L), TRT02PN = ifelse(TRT02P == "Test", 1L, 2L)) %>%
  ## treatment start and end (first and last dose)
  derive_vars_merged(dataset_add = ex_ext, filter_add = EXDOSE > 0 & !is.na(EXSTDTM),
                     new_vars = exprs(TRTSDTM = EXSTDTM), order = exprs(EXSTDTM, EXSEQ), mode = "first",
                     by_vars = exprs(STUDYID, USUBJID)) %>%
  derive_vars_merged(dataset_add = ex_ext, filter_add = EXDOSE > 0 & !is.na(EXENDTM),
                     new_vars = exprs(TRTEDTM = EXENDTM), order = exprs(EXENDTM, EXSEQ), mode = "last",
                     by_vars = exprs(STUDYID, USUBJID)) %>%
  derive_vars_dtm_to_dt(source_vars = exprs(TRTSDTM, TRTEDTM)) %>%
  ## period variables: AP01SDTM, AP01EDTM, AP02SDTM, AP02EDTM, TRT01A, TRT02A, TRT01AN, TRT02AN
  derive_vars_period(dataset_ref = period_ref,
                     new_vars = exprs(APxxSDTM = APERSDTM, APxxEDTM = APEREDTM, TRTxxA = TRTA, TRTxxAN = TRTAN)) %>%
  mutate(TR01SDTM = AP01SDTM, TR02SDTM = AP02SDTM,
         TRTSEQA = paste0(substr(TRT01A, 1, 1), ifelse(is.na(TRT02A), "", substr(TRT02A, 1, 1)))) %>%
  ## disposition
  derive_vars_merged(dataset_add = ds, filter_add = DSCAT == "DISPOSITION EVENT",
                     new_vars = exprs(EOSSTT = DSDECOD, DCSREAS = DSDECOD), by_vars = exprs(STUDYID, USUBJID)) %>%
  mutate(EOSSTT = ifelse(EOSSTT == "COMPLETED", "COMPLETED", "DISCONTINUED"),
         DCSREAS = ifelse(DCSREAS == "COMPLETED", NA_character_, DCSREAS)) %>%
  derive_vars_merged(dataset_add = eos, new_vars = exprs(EOSDT), by_vars = exprs(STUDYID, USUBJID)) %>%
  ## baseline height, weight, BMI
  derive_vars_merged(dataset_add = vs, filter_add = VSTESTCD == "HEIGHT", new_vars = exprs(HEIGHTBL = VSSTRESN),
                     by_vars = exprs(STUDYID, USUBJID)) %>%
  derive_vars_merged(dataset_add = vs, filter_add = VSTESTCD == "WEIGHT" & VSBLFL == "Y", new_vars = exprs(WEIGHTBL = VSSTRESN),
                     by_vars = exprs(STUDYID, USUBJID)) %>%
  mutate(BMIBL = round(compute_bmi(height = HEIGHTBL, weight = WEIGHTBL), 1),
         AGEGR1 = case_when(AGE < 30 ~ "18-29", AGE < 45 ~ "30-44", TRUE ~ "45-65"),
         AGEGR1N = case_when(AGE < 30 ~ 1L, AGE < 45 ~ 2L, TRUE ~ 3L)) %>%
  ## population flags available before NCA
  derive_var_merged_exist_flag(dataset_add = ds, by_vars = exprs(STUDYID, USUBJID), new_var = RANDFL,
                               condition = DSDECOD == "RANDOMIZED", false_value = "N", missing_value = "N") %>%
  derive_var_merged_exist_flag(dataset_add = ex, by_vars = exprs(STUDYID, USUBJID), new_var = SAFFL,
                               condition = EXDOSE > 0, false_value = "N", missing_value = "N")

stopifnot(nrow(adsl_core) == STUDY$n_enrolled, !anyDuplicated(adsl_core$USUBJID))
cat(sprintf("[03_adam/adsl] %d participants, SAFFL=Y %d, discontinued %d\n",
            nrow(adsl_core), sum(adsl_core$SAFFL == "Y"), sum(adsl_core$EOSSTT == "DISCONTINUED")))
