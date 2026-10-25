################################################################################
# 03_adam/04_adae.R: ADAE (one record per adverse event) with admiral 1.5.0, following
# the ad_adae.R template (derive_vars_dtm, derive_vars_dy, derive_var_trtemfl) with the
# crossover period assigned through create_period_dataset() + derive_vars_joined():
# an event belongs to the treatment taken most recently before onset. SYNTHETIC DATA.
#
# Inputs : 03_adam/sdtm/ae.csv, object adsl_core
# Outputs: object `adae`
################################################################################
ae <- read_sdtm("ae")

periods <- create_period_dataset(adsl_core, new_vars = exprs(APERSDTM = APxxSDTM, APEREDTM = APxxEDTM, TRTA = TRTxxA, TRTAN = TRTxxAN))

adae <- ae %>%
  derive_vars_merged(dataset_add = adsl_core, new_vars = exprs(TRTSDTM, TRTEDTM, TRTSDT, TRTEDT, TRTSEQP, SAFFL),
                     by_vars = exprs(STUDYID, USUBJID)) %>%
  derive_vars_dtm(dtc = AESTDTC, new_vars_prefix = "AST", highest_imputation = "M", time_imputation = "first") %>%
  derive_vars_dtm(dtc = AEENDTC, new_vars_prefix = "AEN", highest_imputation = "M", time_imputation = "last") %>%
  derive_vars_dtm_to_dt(exprs(ASTDTM, AENDTM)) %>%
  derive_vars_dy(reference_date = TRTSDT, source_vars = exprs(ASTDT, AENDT)) %>%
  derive_vars_joined(dataset_add = periods, by_vars = exprs(STUDYID, USUBJID),
                     new_vars = exprs(APERIOD, TRTA, TRTAN), join_vars = exprs(APERSDTM, APEREDTM),
                     join_type = "all", filter_join = APERSDTM <= ASTDTM & ASTDTM <= APEREDTM,
                     mode = "first", order = exprs(APERSDTM), check_type = "none") %>%
  derive_var_trtemfl(start_date = ASTDTM, end_date = AENDTM, trt_start_date = TRTSDTM) %>%
  mutate(APERIODC = ifelse(is.na(APERIOD), NA_character_, paste("Period", APERIOD)),
         ASEV = AESEV, ASEVN = match(AESEV, c("MILD", "MODERATE", "SEVERE")),
         AREL = AEREL) %>%
  derive_var_obs_number(new_var = ASEQ, by_vars = exprs(STUDYID, USUBJID), order = exprs(ASTDTM, AESEQ), check_type = "error") %>%
  select(STUDYID, USUBJID, TRTSEQP, SAFFL, APERIOD, APERIODC, TRTA, TRTAN, ASEQ, AESEQ, AETERM, AEDECOD, AEBODSYS, AESOC,
         AESEV, ASEV, ASEVN, AESER, AEREL, AREL, AEACN, AEOUT, AESTDTC, AEENDTC, ASTDTM, ASTDT, ASTDY, AENDTM, AENDT, AENDY,
         TRTEMFL) %>%
  arrange(USUBJID, ASEQ)

stopifnot(all(!is.na(adae$TRTA[adae$TRTEMFL %in% "Y"])))
cat(sprintf("[03_adam/adae] %d events, %d treatment-emergent, %d participants with an event\n",
            nrow(adae), sum(adae$TRTEMFL %in% "Y"), length(unique(adae$USUBJID))))
