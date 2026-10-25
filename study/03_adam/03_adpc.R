################################################################################
# 03_adam/03_adpc.R: ADPC (PK concentrations, ADNCA-style) with admiral 1.5.0,
# following the ad_adpc.R template step by step. SYNTHETIC DATA ONLY.
#
# Template steps kept: derive_vars_dtm() on PCDTC/EXSTDTC, derive_var_nfrlt() for the
# nominal time from first dose (NFRLT; EXPERIMENTAL in admiral 1.5.0, so 05_qc
# re-derives it by plain arithmetic), create_single_dose_dataset(), first/previous/next
# dose joins with derive_vars_joined(), AFRLT and ARRLT with derive_vars_duration(),
# NRRLT, PCRFTDTM, ATPT/ATPTN, AVAL/AVALU/ALLOQ, ASEQ, and the dose records kept with
# PARAMCD = "DOSE" as in the template.
#
# Adaptations for a single-dose crossover, each stated where it happens:
#   (a) EX carries the formulation in EXTRT, so the analyte name DRUG = "SIMDRUG" is used
#       for both PC and EX joins (the template sets DRUG = EXTRT = PCTEST).
#   (b) A pre-dose sample belongs to the dose that follows it: it is referenced to the
#       next dose (ARRLT < 0, NRRLT = 0). The template does the same for its DTYPE "COPY"
#       records; here there is nothing to copy, so the record itself is re-referenced.
#   (c) BLQ is set to 0 in AVAL (SAP and ICH M13A), not to LLOQ/2: the template's
#       HALFLLOQ records are not created. AVALCAT1 = "BLQ" keeps the original result.
#   (d) Samples not collected stay in ADPC (ANL01FL not "Y") so listings can show them;
#       the template's date filter would drop them.
#   (e) APERIOD, APERIODC and TRTA/TRTAN come from the reference dose's period.
#
# Inputs : 03_adam/sdtm/{pc,ex,vs}.csv, object adsl_core
# Outputs: object `adpc`
################################################################################
pc <- read_sdtm("pc"); ex <- read_sdtm("ex")

adsl_vars <- exprs(TRTSDT, TRTSDTM, TRT01P, TRT01A)

pc_dates <- pc %>%
  derive_vars_merged(dataset_add = adsl_core, new_vars = adsl_vars, by_vars = exprs(STUDYID, USUBJID)) %>%
  derive_vars_dtm(new_vars_prefix = "A", dtc = PCDTC, time_imputation = "00:00:00", ignore_seconds_flag = FALSE) %>%
  derive_vars_dtm_to_dt(exprs(ADTM)) %>%
  derive_vars_dtm_to_tm(exprs(ADTM)) %>%
  derive_vars_dy(reference_date = TRTSDT, source_vars = exprs(ADT)) %>%
  mutate(EVID = 0, DRUG = PCTEST) %>%
  derive_var_nfrlt(new_var = NFRLT, new_var_unit = FRLTU, out_unit = "HOURS",
                   tpt_var = PCTPT, visit_day = VISITDY, treatment_duration = 0, range_method = "midpoint")

ex_dates <- ex %>%
  derive_vars_merged(dataset_add = adsl_core, new_vars = adsl_vars, by_vars = exprs(STUDYID, USUBJID)) %>%
  filter(EXDOSE > 0) %>%
  derive_vars_dtm(new_vars_prefix = "AST", dtc = EXSTDTC, time_imputation = "00:00:00") %>%
  derive_vars_dtm(new_vars_prefix = "AEN", dtc = EXENDTC, time_imputation = "00:00:00") %>%
  mutate(EVID = 1) %>%
  derive_var_nfrlt(new_var = NFRLT, new_var_unit = FRLTU, out_unit = "HOURS", visit_day = VISITDY) %>%
  mutate(AENDTM = case_when(is.na(AENDTM) ~ ASTDTM, TRUE ~ AENDTM)) %>%
  derive_vars_dtm_to_dt(exprs(ASTDTM)) %>%
  derive_vars_dtm_to_dt(exprs(AENDTM))

## admiral 1.5.0 create_single_dose_dataset() raises a lubridate "All formats failed to
## parse" warning when no record needs expanding (every EXDOSFRQ here is ONCE). Only that
## warning is muffled, and the record count is checked to be unchanged.
muffle_parse <- function(expr) withCallingHandlers(expr, warning = function(w)
  if (grepl("All formats failed to parse", conditionMessage(w))) invokeRestart("muffleWarning"))
ex_exp <- muffle_parse(ex_dates %>%
  create_single_dose_dataset(
    dose_freq = EXDOSFRQ, start_date = ASTDT, start_datetime = ASTDTM, end_date = AENDT, end_datetime = AENDTM,
    nominal_time = NFRLT, lookup_table = dose_freq_lookup, lookup_column = CDISC_VALUE,
    keep_source_vars = exprs(STUDYID, USUBJID, EVID, EXDOSFRQ, EXDOSFRM, NFRLT, EXDOSE, EXDOSU, EXTRT,
                             ASTDT, ASTDTM, AENDT, AENDTM, VISIT, VISITNUM, VISITDY, TRT01A, TRT01P, DOMAIN, EXSEQ,
                             !!!adsl_vars)) %>%
  mutate(AVISITN = NFRLT %/% 24 + 1, AVISIT = paste("Day", AVISITN), ADTM = ASTDTM,
         DRUG = "SIMDRUG") %>%                                   # adaptation (a)
  derive_vars_dtm_to_dt(exprs(ADTM)) %>%
  derive_vars_dtm_to_tm(exprs(ADTM)) %>%
  derive_vars_dtm_to_tm(exprs(ASTDTM)) %>%
  derive_vars_dtm_to_tm(exprs(AENDTM)) %>%
  derive_vars_dy(reference_date = TRTSDT, source_vars = exprs(ADT)))
stopifnot(nrow(ex_exp) == nrow(ex_dates))

## first dose per analyte; keep participants with dosing
adpc_first_dose <- pc_dates %>%
  derive_vars_merged(dataset_add = ex_exp, filter_add = (EXDOSE > 0 & !is.na(ADTM)),
                     new_vars = exprs(FANLDTM = ADTM), order = exprs(ADTM, EXSEQ), mode = "first",
                     by_vars = exprs(STUDYID, USUBJID, DRUG)) %>%
  filter(!is.na(FANLDTM)) %>%
  mutate(AVISITN = NFRLT %/% 24 + 1, AVISIT = paste("Day", AVISITN))

## previous and next dose (actual), previous and next dose (nominal)
adpc_prev <- adpc_first_dose %>%
  derive_vars_joined(dataset_add = ex_exp, by_vars = exprs(USUBJID), order = exprs(ADTM),
                     new_vars = exprs(ADTM_prev = ADTM, EXDOSE_prev = EXDOSE, AVISIT_prev = AVISIT, AENDTM_prev = AENDTM,
                                      VISITNUM_prev = VISITNUM),
                     join_vars = exprs(ADTM), join_type = "all", filter_add = NULL,
                     filter_join = ADTM > ADTM.join, mode = "last", check_type = "none")
adpc_next <- adpc_prev %>%
  derive_vars_joined(dataset_add = ex_exp, by_vars = exprs(USUBJID), order = exprs(ADTM),
                     new_vars = exprs(ADTM_next = ADTM, EXDOSE_next = EXDOSE, AVISIT_next = AVISIT, AENDTM_next = AENDTM,
                                      VISITNUM_next = VISITNUM),
                     join_vars = exprs(ADTM), join_type = "all", filter_add = NULL,
                     filter_join = ADTM <= ADTM.join, mode = "first", check_type = "none")
adpc_nom_prev <- adpc_next %>%
  derive_vars_joined(dataset_add = ex_exp, by_vars = exprs(USUBJID), order = exprs(NFRLT),
                     new_vars = exprs(NFRLT_prev = NFRLT), join_vars = exprs(NFRLT), join_type = "all",
                     filter_add = NULL, filter_join = NFRLT > NFRLT.join, mode = "last", check_type = "none")
adpc_nom_next <- adpc_nom_prev %>%
  derive_vars_joined(dataset_add = ex_exp, by_vars = exprs(USUBJID), order = exprs(NFRLT),
                     new_vars = exprs(NFRLT_next = NFRLT), join_vars = exprs(NFRLT), join_type = "all",
                     filter_add = NULL, filter_join = NFRLT <= NFRLT.join, mode = "first", check_type = "none")

## combine with dose records; actual relative times
adpc_arrlt <- bind_rows(adpc_nom_next, ex_exp) %>%
  group_by(USUBJID, DRUG) %>%
  mutate(FANLDTM = min(FANLDTM, na.rm = TRUE),
         min_NFRLT = min(NFRLT_prev, na.rm = TRUE),
         maxdate = max(ADT[EVID == 0], na.rm = TRUE), .after = USUBJID) %>%
  arrange(USUBJID, ADTM) %>%
  ungroup() %>%
  filter(is.na(ADT) | ADT <= maxdate) %>%                            # adaptation (d)
  derive_vars_duration(new_var = AFRLT, start_date = FANLDTM, end_date = ADTM,
                       out_unit = "HOURS", floor_in = FALSE, add_one = FALSE) %>%
  derive_vars_duration(new_var = ARRLT, new_var_unit = RRLTU, start_date = ADTM_prev, end_date = ADTM,
                       out_unit = "HOURS", floor_in = FALSE, add_one = FALSE) %>%
  derive_vars_duration(new_var = AXRLT, start_date = ADTM_next, end_date = ADTM,
                       out_unit = "HOURS", floor_in = FALSE, add_one = FALSE) %>%
  mutate(
    predose = EVID == 0 & PCTPTNUM == 0,                              # adaptation (b)
    ARRLT = case_when(EVID == 1 ~ 0, predose ~ AXRLT, is.na(ARRLT) ~ AXRLT, TRUE ~ ARRLT),
    PCRFTDTM = case_when(EVID == 1 ~ ADTM, predose ~ ADTM_next, is.na(ADTM_prev) ~ ADTM_next, TRUE ~ ADTM_prev),
    REFVISN = case_when(EVID == 1 ~ VISITNUM, predose ~ VISITNUM_next, is.na(ADTM_prev) ~ VISITNUM_next, TRUE ~ VISITNUM_prev),
    RRLTU = "HOURS"
  ) %>%
  derive_vars_dtm_to_dt(exprs(FANLDTM)) %>%
  derive_vars_dtm_to_tm(exprs(FANLDTM)) %>%
  derive_vars_dtm_to_dt(exprs(PCRFTDTM)) %>%
  derive_vars_dtm_to_tm(exprs(PCRFTDTM))

## nominal time from the reference dose
adpc_nrrlt <- adpc_arrlt %>%
  mutate(NRRLT = case_when(EVID == 1 ~ 0, predose ~ NFRLT - NFRLT_next, is.na(NFRLT_prev) ~ NFRLT - min_NFRLT,
                           TRUE ~ NFRLT - NFRLT_prev),
         NXRLT = case_when(EVID == 1 ~ 0, TRUE ~ NFRLT - NFRLT_next),
         ## a missed sample has no actual time; its reference dose is its own period's dose
         REFVISN = coalesce(REFVISN, VISITNUM))

## analysis variables
adpc_aval <- adpc_nrrlt %>%
  mutate(
    PARCAT1 = ifelse(EVID == 1, NA_character_, PCSPEC),
    ATPTN = case_when(EVID == 1 ~ 0, TRUE ~ PCTPTNUM),
    ATPT = case_when(EVID == 1 ~ "Dose", TRUE ~ PCTPT),
    ATPTREF = paste("Period", REFVISN, "Dose"),
    BASETYPE = paste(ATPTREF, "Baseline"),
    DOSEA = case_when(EVID == 1 ~ EXDOSE, predose ~ EXDOSE_next, is.na(EXDOSE_prev) ~ EXDOSE_next, TRUE ~ EXDOSE_prev),
    DOSEP = STUDY$dose_mg, DOSEU = "mg",
    PARAMCD = coalesce(PCTESTCD, "DOSE"),
    ALLOQ = PCLLOQ,
    BLQFL = ifelse(EVID == 0 & PCSTRESC %in% "<BLQ", "Y", NA_character_),
    AVAL = case_when(EVID == 1 ~ EXDOSE, BLQFL %in% "Y" ~ 0, TRUE ~ PCSTRESN),   # adaptation (c)
    AVALU = case_when(EVID == 1 ~ EXDOSU, TRUE ~ PCSTRESU),
    AVALCAT1 = case_when(EVID == 1 ~ NA_character_, BLQFL %in% "Y" ~ "BLQ", is.na(AVAL) ~ NA_character_,
                         TRUE ~ prettyNum(signif(AVAL, digits = 3))),
    SRCDOM = DOMAIN, SRCVAR = "SEQ", SRCSEQ = coalesce(PCSEQ, EXSEQ),
    APERIOD = as.integer(REFVISN), APERIODC = paste("Period", APERIOD)) %>%      # adaptation (e)
  ## a sample not collected has no actual time, so no previous/next dose: take its period's dose
  left_join(distinct(ex_exp, USUBJID, REFVISN = VISITNUM, EXDOSE_ref = EXDOSE), by = c("USUBJID", "REFVISN")) %>%
  mutate(DOSEA = coalesce(DOSEA, EXDOSE_ref)) %>%
  derive_vars_merged(dataset_add = select(adsl_core, STUDYID, USUBJID, TRT01A, TRT02A) %>%
                       rename(T1 = TRT01A, T2 = TRT02A), by_vars = exprs(STUDYID, USUBJID)) %>%
  mutate(TRTA = ifelse(APERIOD == 1, T1, T2), TRTAN = ifelse(TRTA == "Test", 1L, 2L),
         ANL01FL = ifelse(EVID == 0 & !is.na(AVAL) & !is.na(ARRLT), "Y", NA_character_),
         ABLFL = ifelse(ATPT == "Pre-dose" & !is.na(AVAL), "Y", NA_character_))

adpc <- adpc_aval %>%
  derive_var_obs_number(new_var = ASEQ, by_vars = exprs(STUDYID, USUBJID),
                        order = exprs(APERIOD, EVID, ATPTN, SRCSEQ), check_type = "error") %>%
  mutate(PARAM = ifelse(PARAMCD == "DOSE", "SIMDRUG Dose", "SIMDRUG Concentration in Plasma"),
         PARAMN = ifelse(PARAMCD == "DOSE", 2L, 1L), FRLTU = "HOURS") %>%
  derive_vars_merged(dataset_add = select(adsl_core, STUDYID, USUBJID, SUBJID, SITEID, AGE, SEX, RACE, TRTSEQP, SAFFL),
                     by_vars = exprs(STUDYID, USUBJID)) %>%
  select(STUDYID, USUBJID, SUBJID, SITEID, AGE, SEX, RACE, TRTSEQP, SAFFL, APERIOD, APERIODC, TRTA, TRTAN,
         PARAMCD, PARAM, PARAMN, PARCAT1, AVAL, AVALU, AVALCAT1, BLQFL, ALLOQ, ABLFL, ANL01FL,
         ADTM, ADT, ATM, ADY, FANLDTM, PCRFTDTM, AFRLT, NFRLT, FRLTU, ARRLT, NRRLT, RRLTU,
         ATPT, ATPTN, ATPTREF, BASETYPE, DOSEA, DOSEP, DOSEU, AVISIT, AVISITN,
         PCSTAT, PCREASND, SRCDOM, SRCVAR, SRCSEQ, ASEQ) %>%
  arrange(USUBJID, ASEQ) %>%
  num_round()

stopifnot(!anyDuplicated(adpc[, c("USUBJID", "ASEQ")]))
cat(sprintf("[03_adam/adpc] %d records (%d concentrations, %d BLQ set to 0, %d not collected, %d dose records)\n",
            nrow(adpc), sum(adpc$PARAMCD == "SIMDRUG"), sum(adpc$BLQFL %in% "Y"), sum(!is.na(adpc$PCSTAT)),
            sum(adpc$PARAMCD == "DOSE")))
