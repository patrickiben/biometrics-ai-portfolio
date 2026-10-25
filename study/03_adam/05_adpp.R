################################################################################
# 03_adam/05_adpp.R: ADPP (PK parameters) from the SDTM-like PP domain, following the
# admiral 1.5.0 ad_adpp.R template, then the SAP exclusion rules, ADPC.ANL02FL and the
# ADSL PK and bioequivalence population flags. SYNTHETIC DATA ONLY.
#
# Template steps kept: derive_vars_merged() of ADSL variables, derive_vars_dt() of ADT
# from PPRFTDTC, derive_vars_dy(), the PARAMCD/PARAM/PARAMN lookup, AVAL/AVALU,
# SRCDOM/SRCVAR/SRCSEQ, AVISIT/AVISITN.
# Adaptation: in a crossover TRTA/TRTP come from the period of the reference dose
# (TRTxxA/TRTxxP), not from TRT01A/TRT01P as in the template.
#
# Period exclusion rules (02_sap/analysis_parameters.json), pre-specified in the protocol
# and SAP (ICH M13A 2.2.1, 2.2.1.1). They apply at different times in a real study:
#   EMESIS    emesis within 2 h of the period's dose -> period excluded. A protocol
#             violation, documented when it happens, before bioanalysis (from ADAE).
#   PREDOSE   pre-dose concentration > 5% of the period's Cmax -> period excluded
#             (M13A 2.2.3.3). Applied to the bioanalytical results.
#   LOWEXP    AUC(0-t) < 5% of the product's geometric mean AUC without the participant
#             (M13A 2.2.1.1; at most 1 participant). Applied to the bioanalytical results.
#
# Inputs : 03_adam/sdtm/pp.csv, objects adsl_core, adpc, adae
# Outputs: objects `adpp`, `adsl` (final), `adpc` (with ANL02FL), `exclusions`
################################################################################
pp <- read_sdtm("pp")
SAP <- jsonlite::read_json(sp("02_sap", "analysis_parameters.json"), simplifyVector = TRUE)
rules <- SAP$exclusion_rules

param_lookup <- tibble::tribble(
  ~PPTESTCD, ~PARAMCD,  ~PARAM,                                              ~PARAMN,
  "CMAX",    "CMAX",    "Maximum concentration (Cmax) (ng/mL)",              1,
  "AUCLST",  "AUCLST",  "AUC to last quantifiable conc, AUC(0-t) (h*ng/mL)", 2,
  "AUCIFO",  "AUCIFO",  "AUC to infinity, AUC(0-inf) (h*ng/mL)",             3,
  "AUCPEO",  "AUCPEO",  "AUC(0-inf) extrapolated (%)",                       4,
  "TMAX",    "TMAX",    "Time of Cmax, tmax (h)",                            5,
  "LAMZHL",  "LAMZHL",  "Terminal half-life, t1/2 (h)",                      6,
  "LAMZ",    "LAMZ",    "Terminal rate constant, lambda z (1/h)",            7,
  "LAMZNPT", "LAMZNPT", "Number of points for lambda z",                     8,
  "R2ADJ",   "R2ADJ",   "Adjusted R-squared for lambda z",                   9,
  "LAMZLL",  "LAMZLL",  "Lambda z lower time limit (h)",                     10,
  "LAMZUL",  "LAMZUL",  "Lambda z upper time limit (h)",                     11,
  "TLST",    "TLST",    "Time of last quantifiable conc, tlast (h)",         12,
  "CLST",    "CLST",    "Last quantifiable conc, Clast (ng/mL)",             13)

adsl_vars <- exprs(TRTSDT, TRTEDT, EOSDT, TRT01P, TRT01A, TRT02P, TRT02A, TR01SDTM, TR02SDTM)

adpp_pp <- pp %>%
  derive_vars_merged(dataset_add = adsl_core, new_vars = adsl_vars, by_vars = exprs(STUDYID, USUBJID)) %>%
  derive_vars_dt(new_vars_prefix = "A", dtc = PPRFTDTC) %>%
  derive_vars_dy(reference_date = TRTSDT, source_vars = exprs(ADT))

adpp_aval <- adpp_pp %>%
  left_join(select(param_lookup, PPTESTCD, PARAMCD), by = "PPTESTCD") %>%
  mutate(PARCAT1 = PPCAT, AVAL = PPSTRESN, AVALU = PPSTRESU) %>%
  select(-PPSTRESN, -PPSTRESC) %>%
  mutate(SRCDOM = DOMAIN, SRCVAR = "SEQ", SRCSEQ = PPSEQ) %>%
  select(-DOMAIN, -PPSEQ)

adpp_avisit <- adpp_aval %>%
  mutate(APERIOD = as.integer(VISITNUM), APERIODC = paste("Period", APERIOD),
         AVISITN = ADY, AVISIT = paste("Day", ADY),
         TRTP = ifelse(APERIOD == 1, TRT01P, TRT02P),
         TRTA = ifelse(APERIOD == 1, TRT01A, TRT02A),
         TRTAN = ifelse(TRTA == "Test", 1L, 2L)) %>%
  left_join(select(param_lookup, PARAMCD, PARAM, PARAMN), by = "PARAMCD")

## --- exclusion rules -------------------------------------------------------------------
dose_t <- adpc %>% filter(PARAMCD == "DOSE") %>% select(USUBJID, APERIOD, DOSEDTM = ADTM)
emesis <- adae %>% filter(AEDECOD == "Vomiting", !is.na(APERIOD)) %>%
  inner_join(dose_t, by = c("USUBJID", "APERIOD")) %>%
  mutate(h_after = as.numeric(difftime(ASTDTM, DOSEDTM, units = "hours"))) %>%
  filter(h_after >= 0, h_after <= rules$emesis_window_h) %>%
  distinct(USUBJID, APERIOD) %>% mutate(EMESIS = TRUE)
cmax <- adpp_avisit %>% filter(PARAMCD == "CMAX") %>% select(USUBJID, APERIOD, CMAX = AVAL)
predose <- adpc %>% filter(PARAMCD == "SIMDRUG", ATPT == "Pre-dose", !is.na(AVAL)) %>%
  select(USUBJID, APERIOD, PREDOSE = AVAL) %>%
  inner_join(cmax, by = c("USUBJID", "APERIOD")) %>%
  mutate(PREDOSE_PCT = 100 * PREDOSE / CMAX, PREDOSE_X = PREDOSE_PCT > rules$predose_pct_cmax)
auc <- adpp_avisit %>% filter(PARAMCD == "AUCLST") %>% select(USUBJID, APERIOD, TRTA, AUC = AVAL)
lowexp <- auc %>% group_by(TRTA) %>%
  mutate(GM_OTHERS = vapply(seq_along(AUC), function(i) exp(mean(log(AUC[-i]))), numeric(1))) %>%
  ungroup() %>% mutate(AUC_PCT_GM = 100 * AUC / GM_OTHERS, LOWEXP = AUC_PCT_GM < rules$low_exposure_pct)

exclusions <- auc %>%
  left_join(emesis, by = c("USUBJID", "APERIOD")) %>%
  left_join(select(predose, USUBJID, APERIOD, PREDOSE, PREDOSE_PCT, PREDOSE_X), by = c("USUBJID", "APERIOD")) %>%
  left_join(select(lowexp, USUBJID, APERIOD, AUC_PCT_GM, LOWEXP), by = c("USUBJID", "APERIOD")) %>%
  mutate(EMESIS = coalesce(EMESIS, FALSE), PREDOSE_X = coalesce(PREDOSE_X, FALSE),
         PKEXRSN = case_when(EMESIS ~ "EMESIS WITHIN 2 H OF DOSING",
                             PREDOSE_X ~ "PRE-DOSE CONCENTRATION ABOVE 5% OF CMAX",
                             LOWEXP ~ "AUC BELOW 5% OF GEOMETRIC MEAN AUC",
                             TRUE ~ NA_character_)) %>%
  arrange(USUBJID, APERIOD)

## a profile is evaluable when both primary parameters exist and no rule applies
prim <- adpp_avisit %>% filter(PARAMCD %in% SAP$primary_params) %>%
  group_by(USUBJID, APERIOD) %>% summarise(PRIM_OK = sum(!is.na(AVAL)) == length(SAP$primary_params), .groups = "drop")
prof <- exclusions %>% select(USUBJID, APERIOD, TRTA, PKEXRSN) %>%
  left_join(prim, by = c("USUBJID", "APERIOD")) %>%
  mutate(ANL01FL = ifelse(PRIM_OK & is.na(PKEXRSN), "Y", NA_character_))
be_subj <- prof %>% filter(ANL01FL == "Y") %>% group_by(USUBJID) %>%
  summarise(BOTH = all(c("Test", "Reference") %in% TRTA), .groups = "drop") %>% filter(BOTH) %>% pull(USUBJID)
prof <- prof %>% mutate(ANL02FL = ifelse(ANL01FL %in% "Y" & USUBJID %in% be_subj, "Y", NA_character_))

## --- ADPP ----------------------------------------------------------------------------------
adpp <- adpp_avisit %>%
  left_join(select(prof, USUBJID, APERIOD, PKEXRSN, ANL01FL, ANL02FL), by = c("USUBJID", "APERIOD")) %>%
  derive_vars_merged(dataset_add = select(adsl_core, STUDYID, USUBJID, SUBJID, SITEID, AGE, SEX, RACE, TRTSEQP, SAFFL),
                     by_vars = exprs(STUDYID, USUBJID)) %>%
  derive_var_obs_number(new_var = ASEQ, by_vars = exprs(STUDYID, USUBJID), order = exprs(APERIOD, PARAMN), check_type = "error") %>%
  select(STUDYID, USUBJID, SUBJID, SITEID, AGE, SEX, RACE, TRTSEQP, SAFFL, APERIOD, APERIODC, TRTP, TRTA, TRTAN,
         PARAMCD, PARAM, PARAMN, PARCAT1, AVAL, AVALU, PPSTAT, PPREASND, ANL01FL, ANL02FL, PKEXRSN,
         ADT, ADY, AVISIT, AVISITN, SRCDOM, SRCVAR, SRCSEQ, ASEQ) %>%
  arrange(USUBJID, ASEQ) %>%
  num_round()

## --- ADPC.ANL02FL: concentration records used in summaries and mean plots ----------------
adpc <- adpc %>%
  left_join(select(prof, USUBJID, APERIOD, PKEXRSN), by = c("USUBJID", "APERIOD")) %>%
  mutate(ANL02FL = ifelse(ANL01FL %in% "Y" & is.na(PKEXRSN), "Y", NA_character_)) %>%
  select(-PKEXRSN) %>%
  relocate(ANL02FL, .after = ANL01FL)

## --- final ADSL: PK and bioequivalence population flags ------------------------------------
pkc <- adpc %>% filter(PARAMCD == "SIMDRUG", ANL01FL == "Y", AVAL > 0, ARRLT > 0) %>% distinct(USUBJID) %>% pull()
pkp <- prof %>% filter(ANL01FL == "Y") %>% distinct(USUBJID) %>% pull()
adsl <- adsl_core %>%
  mutate(PKCFL = ifelse(SAFFL == "Y" & USUBJID %in% pkc, "Y", "N"),
         PKPFL = ifelse(PKCFL == "Y" & USUBJID %in% pkp, "Y", "N"),
         BEFL  = ifelse(PKPFL == "Y" & USUBJID %in% be_subj, "Y", "N"))

n_be <- sum(adsl$BEFL == "Y")
stopifnot(n_be >= rules$min_evaluable)
write_csv_det(exclusions, sp("03_adam", "data", "exclusion_rules_evaluated.csv"))
cat(sprintf("[03_adam/adpp] %d records; periods excluded: %d (%s); BE set %d of %d (M13A minimum %d)\n",
            nrow(adpp), sum(!is.na(prof$PKEXRSN)), paste(unique(na.omit(prof$PKEXRSN)), collapse = "; "),
            n_be, nrow(adsl), rules$min_evaluable))
