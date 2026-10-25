################################################################################
# 03_adam/spec/build_spec.R: the ADaM specification for ADSL, ADPC, ADPP and ADAE,
# authored here once and written two ways:
#   * adam_spec.xlsx: Pinnacle 21 specification layout (Study, Datasets, Variables,
#     ValueLevel, WhereClauses, Codelists, Dictionaries, Methods, Comments, Documents),
#     the "by_type" layout that metacore::spec_to_metacore() reads;
#   * adam_spec.json: the same tables as JSON, for scripts and diffs.
# SYNTHETIC STUDY. This is an analysis specification, not define.xml (define.xml and the
# ADRG are not authored in this example).
################################################################################
spec_dir <- sp("03_adam", "spec")
SAP <- jsonlite::read_json(sp("02_sap", "analysis_parameters.json"), simplifyVector = TRUE)

v <- function(var, label, type = "text", length = 8, codelist = NA, origin = "Derived", method = NA,
              predecessor = NA, format = NA, mandatory = "Yes", role = NA) {
  tibble::tibble(Variable = var, Label = label, `Data Type` = type, Length = length, Format = format,
                 Mandatory = mandatory, Codelist = codelist, Origin = origin, Method = method,
                 Predecessor = predecessor, Role = role)
}
dt  <- function(var, label, method) v(var, label, "integer", 8, format = "DATETIME20.", method = method)
dd  <- function(var, label, method) v(var, label, "integer", 8, format = "DATE9.", method = method)
pre <- function(var, label, type = "text", length = 8, codelist = NA, src, mandatory = "Yes")
  v(var, label, type, length, codelist, origin = "Predecessor", predecessor = src, mandatory = mandatory)

id_vars <- dplyr::bind_rows(
  pre("STUDYID", "Study Identifier", length = 7, src = "DM.STUDYID"),
  pre("USUBJID", "Unique Subject Identifier", length = 15, src = "DM.USUBJID"))
adsl_carry <- dplyr::bind_rows(
  pre("SUBJID", "Subject Identifier for the Study", length = 3, src = "DM.SUBJID"),
  pre("SITEID", "Study Site Identifier", length = 3, src = "DM.SITEID"),
  pre("AGE", "Age", "integer", src = "DM.AGE"),
  pre("SEX", "Sex", length = 1, codelist = "SEX", src = "DM.SEX"),
  pre("RACE", "Race", length = 25, codelist = "RACE", src = "DM.RACE"),
  pre("TRTSEQP", "Planned Sequence of Treatments", length = 2, codelist = "SEQ", src = "ADSL.TRTSEQP"),
  pre("SAFFL", "Safety Population Flag", length = 1, codelist = "NY", src = "ADSL.SAFFL"))

vars <- list(
ADSL = dplyr::bind_rows(id_vars,
  pre("SUBJID", "Subject Identifier for the Study", length = 3, src = "DM.SUBJID"),
  pre("RFSTDTC", "Subject Reference Start Date/Time", "datetime", 16, src = "DM.RFSTDTC"),
  pre("RFENDTC", "Subject Reference End Date/Time", "datetime", 16, src = "DM.RFENDTC"),
  pre("RFXSTDTC", "Date/Time of First Study Treatment", "datetime", 16, src = "DM.RFXSTDTC"),
  pre("RFXENDTC", "Date/Time of Last Study Treatment", "datetime", 16, src = "DM.RFXENDTC"),
  pre("RFICDTC", "Date/Time of Informed Consent", "date", 10, src = "DM.RFICDTC"),
  pre("RFPENDTC", "Date/Time of End of Participation", "date", 10, src = "DM.RFPENDTC"),
  pre("SITEID", "Study Site Identifier", length = 3, src = "DM.SITEID"),
  pre("AGE", "Age", "integer", src = "DM.AGE"),
  pre("AGEU", "Age Units", length = 5, codelist = "AGEU", src = "DM.AGEU"),
  pre("SEX", "Sex", length = 1, codelist = "SEX", src = "DM.SEX"),
  pre("RACE", "Race", length = 25, codelist = "RACE", src = "DM.RACE"),
  pre("ETHNIC", "Ethnicity", length = 22, codelist = "ETHNIC", src = "DM.ETHNIC"),
  pre("ARMCD", "Planned Arm Code", length = 2, codelist = "SEQ", src = "DM.ARMCD"),
  pre("ARM", "Description of Planned Arm", length = 19, src = "DM.ARM"),
  pre("ACTARMCD", "Actual Arm Code", length = 2, codelist = "SEQ", src = "DM.ACTARMCD"),
  pre("ACTARM", "Description of Actual Arm", length = 19, src = "DM.ACTARM"),
  pre("COUNTRY", "Country", length = 3, codelist = "COUNTRY", src = "DM.COUNTRY"),
  pre("DMDTC", "Date/Time of Collection", "date", 10, src = "DM.DMDTC"),
  v("TRTSEQP", "Planned Sequence of Treatments", length = 2, codelist = "SEQ", method = "MT.TRTSEQP"),
  v("TRT01P", "Planned Treatment for Period 01", length = 9, codelist = "TRT", method = "MT.TRTXXP"),
  v("TRT02P", "Planned Treatment for Period 02", length = 9, codelist = "TRT", method = "MT.TRTXXP"),
  v("TRT01PN", "Planned Treatment for Period 01 (N)", "integer", codelist = "TRTN", method = "MT.TRTXXP"),
  v("TRT02PN", "Planned Treatment for Period 02 (N)", "integer", codelist = "TRTN", method = "MT.TRTXXP"),
  dt("TRTSDTM", "Datetime of First Exposure to Treatment", "MT.TRTSDTM"),
  dt("TRTEDTM", "Datetime of Last Exposure to Treatment", "MT.TRTEDTM"),
  dd("TRTSDT", "Date of First Exposure to Treatment", "MT.TRTSDTM"),
  dd("TRTEDT", "Date of Last Exposure to Treatment", "MT.TRTEDTM"),
  dt("AP01SDTM", "Period 01 Start Datetime", "MT.APXX"),
  dt("AP02SDTM", "Period 02 Start Datetime", "MT.APXX") %>% dplyr::mutate(Mandatory = "No"),
  dt("AP01EDTM", "Period 01 End Datetime", "MT.APXX"),
  dt("AP02EDTM", "Period 02 End Datetime", "MT.APXX") %>% dplyr::mutate(Mandatory = "No"),
  v("TRT01A", "Actual Treatment for Period 01", length = 9, codelist = "TRT", method = "MT.APXX"),
  v("TRT02A", "Actual Treatment for Period 02", length = 9, codelist = "TRT", method = "MT.APXX", mandatory = "No"),
  v("TRT01AN", "Actual Treatment for Period 01 (N)", "integer", codelist = "TRTN", method = "MT.APXX"),
  v("TRT02AN", "Actual Treatment for Period 02 (N)", "integer", codelist = "TRTN", method = "MT.APXX", mandatory = "No"),
  dt("TR01SDTM", "Datetime of First Exposure in Period 01", "MT.APXX"),
  dt("TR02SDTM", "Datetime of First Exposure in Period 02", "MT.APXX") %>% dplyr::mutate(Mandatory = "No"),
  v("TRTSEQA", "Actual Sequence of Treatments", length = 2, codelist = "SEQA", method = "MT.TRTSEQA"),
  v("EOSSTT", "End of Study Status", length = 12, codelist = "EOSSTT", method = "MT.EOSSTT"),
  v("DCSREAS", "Reason for Discontinuation from Study", length = 21, codelist = "DCSREAS", method = "MT.EOSSTT", mandatory = "No"),
  dd("EOSDT", "End of Study Date", "MT.EOSSTT"),
  v("HEIGHTBL", "Baseline Height (cm)", "float", method = "MT.VSBL"),
  v("WEIGHTBL", "Baseline Weight (kg)", "float", method = "MT.VSBL"),
  v("BMIBL", "Baseline BMI (kg/m^2)", "float", method = "MT.BMIBL"),
  v("AGEGR1", "Pooled Age Group 1", length = 5, codelist = "AGEGR1", method = "MT.AGEGR1"),
  v("AGEGR1N", "Pooled Age Group 1 (N)", "integer", method = "MT.AGEGR1"),
  v("RANDFL", "Randomized Population Flag", length = 1, codelist = "NY", method = "MT.RANDFL"),
  v("SAFFL", "Safety Population Flag", length = 1, codelist = "NY", method = "MT.SAFFL"),
  v("PKCFL", "PK Concentration Population Flag", length = 1, codelist = "NY", method = "MT.PKCFL"),
  v("PKPFL", "PK Parameter Population Flag", length = 1, codelist = "NY", method = "MT.PKPFL"),
  v("BEFL", "Bioequivalence Population Flag", length = 1, codelist = "NY", method = "MT.BEFL")),
ADPC = dplyr::bind_rows(id_vars, adsl_carry,
  v("APERIOD", "Period", "integer", method = "MT.APERIOD.PC"),
  v("APERIODC", "Period (C)", length = 8, codelist = "APERIODC", method = "MT.APERIOD.PC"),
  v("TRTA", "Actual Treatment", length = 9, codelist = "TRT", method = "MT.TRTA.PC"),
  v("TRTAN", "Actual Treatment (N)", "integer", codelist = "TRTN", method = "MT.TRTA.PC"),
  v("PARAMCD", "Parameter Code", length = 7, codelist = "PARAMCD.PC", method = "MT.PARAMCD.PC"),
  v("PARAM", "Parameter", length = 31, method = "MT.PARAMCD.PC"),
  v("PARAMN", "Parameter (N)", "integer", method = "MT.PARAMCD.PC"),
  v("PARCAT1", "Parameter Category 1", length = 6, origin = "Predecessor", predecessor = "PC.PCSPEC", mandatory = "No"),
  v("AVAL", "Analysis Value", "float", method = "MT.AVAL.PC", mandatory = "No"),
  v("AVALU", "Analysis Value Unit", length = 5, method = "MT.AVAL.PC"),
  v("AVALCAT1", "Analysis Value Category 1", length = 5, method = "MT.AVALCAT1.PC", mandatory = "No"),
  v("BLQFL", "Below Lower Limit of Quantitation Flag", length = 1, codelist = "Y", method = "MT.AVAL.PC", mandatory = "No"),
  v("ALLOQ", "Analysis Lower Limit of Quantitation", "float", origin = "Predecessor", predecessor = "PC.PCLLOQ", mandatory = "No"),
  v("ABLFL", "Baseline Record Flag", length = 1, codelist = "Y", method = "MT.ABLFL.PC", mandatory = "No"),
  v("ANL01FL", "Analysis Flag 01", length = 1, codelist = "Y", method = "MT.ANL01FL.PC", mandatory = "No"),
  v("ANL02FL", "Analysis Flag 02", length = 1, codelist = "Y", method = "MT.ANL02FL.PC", mandatory = "No"),
  dt("ADTM", "Analysis Datetime", "MT.ADTM.PC") %>% dplyr::mutate(Mandatory = "No"),
  dd("ADT", "Analysis Date", "MT.ADTM.PC") %>% dplyr::mutate(Mandatory = "No"),
  v("ATM", "Analysis Time", "integer", format = "TIME8.", method = "MT.ADTM.PC", mandatory = "No"),
  v("ADY", "Analysis Relative Day", "integer", method = "MT.ADY", mandatory = "No"),
  dt("FANLDTM", "First Datetime of Dose for Analyte", "MT.FANLDTM"),
  dt("PCRFTDTM", "Date/Time of Reference Dose", "MT.PCRFTDTM") %>% dplyr::mutate(Mandatory = "No"),
  v("AFRLT", "Actual Rel Time from Analyte First Dose", "float", method = "MT.AFRLT", mandatory = "No"),
  v("NFRLT", "Nominal Rel Time from Analyte First Dose", "float", method = "MT.NFRLT"),
  v("FRLTU", "Rel Time from First Dose Unit", length = 5, codelist = "HOURS", method = "MT.NFRLT"),
  v("ARRLT", "Actual Relative Time from Ref Dose", "float", method = "MT.ARRLT", mandatory = "No"),
  v("NRRLT", "Nominal Relative Time from Ref Dose", "float", method = "MT.NRRLT"),
  v("RRLTU", "Relative Time from Ref Dose Unit", length = 5, codelist = "HOURS", method = "MT.ARRLT"),
  v("ATPT", "Analysis Timepoint", length = 16, method = "MT.ATPT.PC"),
  v("ATPTN", "Analysis Timepoint (N)", "float", method = "MT.ATPT.PC"),
  v("ATPTREF", "Analysis Timepoint Reference", length = 13, method = "MT.ATPT.PC"),
  v("BASETYPE", "Baseline Type", length = 22, method = "MT.ATPT.PC"),
  v("DOSEA", "Actual Treatment Dose", "float", method = "MT.DOSEA"),
  v("DOSEP", "Planned Treatment Dose", "float", origin = "Assigned"),
  v("DOSEU", "Treatment Dose Units", length = 2, origin = "Assigned"),
  v("AVISIT", "Analysis Visit", length = 6, method = "MT.AVISIT.PC"),
  v("AVISITN", "Analysis Visit (N)", "integer", method = "MT.AVISIT.PC"),
  pre("PCSTAT", "Completion Status", length = 8, src = "PC.PCSTAT", mandatory = "No"),
  pre("PCREASND", "Reason Test Not Done", length = 20, src = "PC.PCREASND", mandatory = "No"),
  v("SRCDOM", "Source Data", length = 2, origin = "Assigned"),
  v("SRCVAR", "Source Variable", length = 3, origin = "Assigned"),
  v("SRCSEQ", "Source Sequence Number", "integer", origin = "Predecessor", predecessor = "PC.PCSEQ / EX.EXSEQ"),
  v("ASEQ", "Analysis Sequence Number", "integer", method = "MT.ASEQ")),
ADPP = dplyr::bind_rows(id_vars, adsl_carry,
  v("APERIOD", "Period", "integer", method = "MT.APERIOD.PP"),
  v("APERIODC", "Period (C)", length = 8, codelist = "APERIODC", method = "MT.APERIOD.PP"),
  v("TRTP", "Planned Treatment", length = 9, codelist = "TRT", method = "MT.TRTA.PP"),
  v("TRTA", "Actual Treatment", length = 9, codelist = "TRT", method = "MT.TRTA.PP"),
  v("TRTAN", "Actual Treatment (N)", "integer", codelist = "TRTN", method = "MT.TRTA.PP"),
  v("PARAMCD", "Parameter Code", length = 7, codelist = "PARAMCD.PP", method = "MT.PARAMCD.PP"),
  v("PARAM", "Parameter", length = 51, method = "MT.PARAMCD.PP"),
  v("PARAMN", "Parameter (N)", "integer", method = "MT.PARAMCD.PP"),
  v("PARCAT1", "Parameter Category 1", length = 7, origin = "Predecessor", predecessor = "PP.PPCAT"),
  v("AVAL", "Analysis Value", "float", origin = "Predecessor", predecessor = "PP.PPSTRESN", mandatory = "No"),
  v("AVALU", "Analysis Value Unit", length = 7, origin = "Predecessor", predecessor = "PP.PPSTRESU", mandatory = "No"),
  pre("PPSTAT", "Completion Status", length = 8, src = "PP.PPSTAT", mandatory = "No"),
  pre("PPREASND", "Reason Parameter Not Calculated", length = 40, src = "PP.PPREASND", mandatory = "No"),
  v("ANL01FL", "Analysis Flag 01", length = 1, codelist = "Y", method = "MT.ANL01FL.PP", mandatory = "No"),
  v("ANL02FL", "Analysis Flag 02", length = 1, codelist = "Y", method = "MT.ANL02FL.PP", mandatory = "No"),
  v("PKEXRSN", "Reason Excluded from PK Analyses", length = 40, codelist = "PKEXRSN", method = "MT.PKEXRSN", mandatory = "No"),
  v("NCAEXRSN", "Reason Value Excluded by NCA Rule", length = 40, codelist = "NCAEXRSN", method = "MT.NCAEXRSN", mandatory = "No"),
  dd("ADT", "Analysis Date", "MT.ADT.PP"),
  v("ADY", "Analysis Relative Day", "integer", method = "MT.ADY"),
  v("AVISIT", "Analysis Visit", length = 6, method = "MT.AVISIT.PP"),
  v("AVISITN", "Analysis Visit (N)", "integer", method = "MT.AVISIT.PP"),
  v("SRCDOM", "Source Data", length = 2, origin = "Assigned"),
  v("SRCVAR", "Source Variable", length = 3, origin = "Assigned"),
  v("SRCSEQ", "Source Sequence Number", "integer", origin = "Predecessor", predecessor = "PP.PPSEQ"),
  v("ASEQ", "Analysis Sequence Number", "integer", method = "MT.ASEQ")),
ADAE = dplyr::bind_rows(id_vars,
  pre("TRTSEQP", "Planned Sequence of Treatments", length = 2, codelist = "SEQ", src = "ADSL.TRTSEQP"),
  pre("SAFFL", "Safety Population Flag", length = 1, codelist = "NY", src = "ADSL.SAFFL"),
  v("APERIOD", "Period", "integer", method = "MT.APERIOD.AE"),
  v("APERIODC", "Period (C)", length = 8, codelist = "APERIODC", method = "MT.APERIOD.AE"),
  v("TRTA", "Actual Treatment", length = 9, codelist = "TRT", method = "MT.APERIOD.AE"),
  v("TRTAN", "Actual Treatment (N)", "integer", codelist = "TRTN", method = "MT.APERIOD.AE"),
  v("ASEQ", "Analysis Sequence Number", "integer", method = "MT.ASEQ"),
  pre("AESEQ", "Sequence Number", "integer", src = "AE.AESEQ"),
  pre("AETERM", "Reported Term for the Adverse Event", length = 20, src = "AE.AETERM"),
  pre("AEDECOD", "Dictionary-Derived Term", length = 20, src = "AE.AEDECOD"),
  pre("AEBODSYS", "Body System or Organ Class", length = 52, src = "AE.AEBODSYS"),
  pre("AESOC", "Primary System Organ Class", length = 52, src = "AE.AESOC"),
  pre("AESEV", "Severity/Intensity", length = 8, codelist = "SEV", src = "AE.AESEV"),
  v("ASEV", "Analysis Severity/Intensity", length = 8, codelist = "SEV", origin = "Predecessor", predecessor = "AE.AESEV"),
  v("ASEVN", "Analysis Severity/Intensity (N)", "integer", method = "MT.ASEVN"),
  pre("AESER", "Serious Event", length = 1, codelist = "NY", src = "AE.AESER"),
  pre("AEREL", "Causality", length = 11, codelist = "REL", src = "AE.AEREL"),
  v("AREL", "Analysis Causality", length = 11, codelist = "REL", origin = "Predecessor", predecessor = "AE.AEREL"),
  pre("AEACN", "Action Taken with Study Treatment", length = 14, src = "AE.AEACN"),
  pre("AEOUT", "Outcome of Adverse Event", length = 18, src = "AE.AEOUT"),
  pre("AESTDTC", "Start Date/Time of Adverse Event", "datetime", 16, src = "AE.AESTDTC"),
  pre("AEENDTC", "End Date/Time of Adverse Event", "datetime", 16, src = "AE.AEENDTC"),
  dt("ASTDTM", "Analysis Start Datetime", "MT.ASTDTM"),
  dd("ASTDT", "Analysis Start Date", "MT.ASTDTM"),
  v("ASTDY", "Analysis Start Relative Day", "integer", method = "MT.ADY"),
  dt("AENDTM", "Analysis End Datetime", "MT.AENDTM"),
  dd("AENDT", "Analysis End Date", "MT.AENDTM"),
  v("AENDY", "Analysis End Relative Day", "integer", method = "MT.ADY"),
  v("TRTEMFL", "Treatment Emergent Analysis Flag", length = 1, codelist = "Y", method = "MT.TRTEMFL", mandatory = "No"))
)
variables <- dplyr::bind_rows(lapply(names(vars), function(d)
  dplyr::mutate(vars[[d]], Dataset = d, Order = seq_len(nrow(vars[[d]]))))) %>%
  dplyr::mutate(`Significant Digits` = NA, Pages = NA, Comment = NA) %>%
  dplyr::select(Order, Dataset, Variable, Label, `Data Type`, Length, `Significant Digits`, Format, Mandatory,
                Codelist, Origin, Pages, Method, Predecessor, Role, Comment)
stopifnot(all(nchar(variables$Variable) <= 8), all(nchar(variables$Label) <= 40), !anyDuplicated(variables[, c("Dataset", "Variable")]))

datasets <- tibble::tribble(
  ~Dataset, ~Description,                                      ~Class,                       ~Structure,                                                         ~`Key Variables`,
  "ADSL",   "Subject-Level Analysis Dataset",                  "SUBJECT LEVEL ANALYSIS DATASET", "One record per participant",                                  "STUDYID, USUBJID",
  "ADPC",   "PK Concentrations Analysis Dataset", "BASIC DATA STRUCTURE",       "One record per participant, period, analyte and sampling time, plus dose records", "STUDYID, USUBJID, ASEQ",
  "ADPP",   "PK Parameters Analysis Dataset", "BASIC DATA STRUCTURE",       "One record per participant, period and PK parameter",              "STUDYID, USUBJID, APERIOD, PARAMCD",
  "ADAE",   "Adverse Events Analysis Dataset",                 "OCCURRENCE DATA STRUCTURE",  "One record per adverse event",                                     "STUDYID, USUBJID, ASEQ") %>%
  dplyr::mutate(Purpose = "Analysis", Repeating = ifelse(Dataset == "ADSL", "No", "Yes"), `Reference Data` = "No", Comment = NA) %>%
  dplyr::select(Dataset, Description, Class, Structure, Purpose, `Key Variables`, Repeating, `Reference Data`, Comment)
stopifnot(all(nchar(datasets$Description) <= 40))   # XPT v5 dataset label limit

cl <- function(id, terms, decodes = terms, type = "text") tibble::tibble(ID = id, Name = id, `NCI Codelist Code` = NA, `Data Type` = type,
                                                                         Order = seq_along(terms), Term = as.character(terms), `NCI Term Code` = NA, `Decoded Value` = decodes)
codelists <- dplyr::bind_rows(
  cl("NY", c("Y", "N"), c("Yes", "No")), cl("Y", "Y", "Yes"), cl("SEX", c("F", "M"), c("Female", "Male")),
  cl("RACE", c("ASIAN", "BLACK OR AFRICAN AMERICAN", "MULTIPLE", "WHITE")),
  cl("ETHNIC", c("HISPANIC OR LATINO", "NOT HISPANIC OR LATINO", "NOT REPORTED")),
  cl("AGEU", "YEARS"), cl("COUNTRY", "USA", "United States"),
  cl("SEQ", c("TR", "RT"), c("Test then Reference", "Reference then Test")),
  cl("SEQA", c("TR", "RT", "T", "R"), c("Test then Reference", "Reference then Test", "Test only", "Reference only")),
  cl("TRT", c("Test", "Reference")), cl("TRTN", c(1, 2), c("Test", "Reference"), "integer"),
  cl("AGEGR1", c("18-29", "30-44", "45-65")), cl("EOSSTT", c("COMPLETED", "DISCONTINUED")),
  cl("DCSREAS", "WITHDRAWAL BY SUBJECT", "Withdrawal by participant"),
  cl("APERIODC", c("Period 1", "Period 2")), cl("HOURS", "HOURS"),
  cl("PARAMCD.PC", c("SIMDRUG", "DOSE"), c("SIMDRUG Concentration in Plasma", "SIMDRUG Dose")),
  cl("PARAMCD.PP", c("CMAX", "AUCLST", "AUCIFO", "AUCPEO", "TMAX", "LAMZHL", "LAMZ", "LAMZNPT", "R2ADJ", "LAMZLL", "LAMZUL", "TLST", "CLST")),
  cl("PKEXRSN", c("EMESIS WITHIN 2 H OF DOSING", "PRE-DOSE CONCENTRATION ABOVE 5% OF CMAX", "AUC BELOW 5% OF GEOMETRIC MEAN AUC")),
  cl("NCAEXRSN", unname(nca_rule_terms(SAP))),
  cl("SEV", c("MILD", "MODERATE", "SEVERE")), cl("REL", c("RELATED", "NOT RELATED")))

methods <- tibble::tribble(
  ~ID, ~Description,
  "MT.TRTSEQP", "ADSL.TRTSEQP = DM.ARMCD (TR or RT, from the randomization schedule).",
  "MT.TRTXXP", "TRT01P/TRT02P = first/second letter of TRTSEQP decoded (T = Test, R = Reference); TRTxxPN 1 = Test, 2 = Reference.",
  "MT.TRTSDTM", "First (last) EX record with EXDOSE > 0: EXSTDTC (EXENDTC) converted with admiral::derive_vars_dtm(); date part by derive_vars_dtm_to_dt().",
  "MT.TRTEDTM", "Last EX record with EXDOSE > 0, EXENDTC converted with admiral::derive_vars_dtm().",
  "MT.APXX", "admiral::derive_vars_period() from a period reference dataset built from EX: period xx starts at its dose (EXSTDTM) and ends one minute before the next dose, or at 23:59:59 on the end-of-study date; TRTxxA from EXTRT.",
  "MT.TRTSEQA", "First letters of TRT01A and TRT02A (T or R); one letter when only one period was dosed.",
  "MT.EOSSTT", "From DS where DSCAT = DISPOSITION EVENT: COMPLETED if DSDECOD = COMPLETED, else DISCONTINUED; DCSREAS = DSDECOD when discontinued; EOSDT = DSSTDTC.",
  "MT.VSBL", "VS.VSSTRESN at screening for VSTESTCD = HEIGHT (HEIGHTBL) and VSTESTCD = WEIGHT with VSBLFL = Y (WEIGHTBL).",
  "MT.BMIBL", "admiral::compute_bmi(HEIGHTBL, WEIGHTBL), rounded to 1 decimal.",
  "MT.AGEGR1", "AGE < 30: 18-29 (1); AGE < 45: 30-44 (2); else 45-65 (3).",
  "MT.RANDFL", "Y if DS has DSDECOD = RANDOMIZED, else N (admiral::derive_var_merged_exist_flag()).",
  "MT.SAFFL", "Y if EX has a record with EXDOSE > 0, else N.",
  "MT.PKCFL", "Y if SAFFL = Y and ADPC has a quantifiable post-dose concentration (ANL01FL = Y, AVAL > 0, ARRLT > 0).",
  "MT.PKPFL", "Y if PKCFL = Y and ADPP has at least one period with ANL01FL = Y.",
  "MT.BEFL", "Y if PKPFL = Y and ADPP has ANL01FL = Y periods for both Test and Reference (ICH M13A: evaluable data for both products).",
  "MT.APERIOD.PC", "Period of the reference dose (PCRFTDTM); a pre-dose sample belongs to the dose that follows it.",
  "MT.TRTA.PC", "TRT01A or TRT02A for the record's APERIOD.",
  "MT.PARAMCD.PC", "PC.PCTESTCD for concentration records; DOSE for the dose records kept from EX (admiral ad_adpc.R).",
  "MT.AVAL.PC", "PC.PCSTRESN; BLQ results (PCSTRESC = <BLQ) set to 0 with BLQFL = Y (SAP, ICH M13A); EX.EXDOSE for dose records.",
  "MT.AVALCAT1.PC", "BLQ for BLQ results, else AVAL to 3 significant digits.",
  "MT.ABLFL.PC", "Y for the pre-dose record of each period when AVAL is not missing.",
  "MT.ANL01FL.PC", "Y for concentration records with AVAL and ARRLT not missing (all collected samples; NCA input).",
  "MT.ANL02FL.PC", "Y when ANL01FL = Y and the period is not excluded (ADPP.PKEXRSN missing): concentration summaries and mean plots.",
  "MT.ADTM.PC", "admiral::derive_vars_dtm() of PCDTC (dose records: EXSTDTC); ADT and ATM from ADTM.",
  "MT.ADY", "admiral::derive_vars_dy() with reference date TRTSDT.",
  "MT.FANLDTM", "First dose datetime for the analyte (admiral ad_adpc.R).",
  "MT.PCRFTDTM", "Datetime of the reference dose: the previous dose, or the next dose for a pre-dose sample.",
  "MT.AFRLT", "admiral::derive_vars_duration() from FANLDTM to ADTM, hours.",
  "MT.NFRLT", "admiral::derive_var_nfrlt() (EXPERIMENTAL in admiral 1.5.0): (VISITDY - 1) x 24 + PCTPT in hours.",
  "MT.ARRLT", "admiral::derive_vars_duration() from the reference dose to ADTM, hours; negative for a pre-dose sample.",
  "MT.NRRLT", "NFRLT minus the nominal time of the reference dose.",
  "MT.ATPT.PC", "PC.PCTPT and PCTPTNUM; Dose for dose records; ATPTREF = Period n Dose; BASETYPE = ATPTREF + Baseline.",
  "MT.DOSEA", "EXDOSE of the reference dose.",
  "MT.AVISIT.PC", "Day (NFRLT %/% 24 + 1), as in admiral ad_adpc.R.",
  "MT.ASEQ", "admiral::derive_var_obs_number() within USUBJID.",
  "MT.APERIOD.PP", "PP.VISITNUM (the period of the NCA profile).",
  "MT.TRTA.PP", "TRTxxP/TRTxxA of APERIOD (crossover adaptation of admiral ad_adpp.R).",
  "MT.PARAMCD.PP", "PP.PPTESTCD through the parameter lookup table.",
  "MT.ANL01FL.PP", "Y when Cmax and AUC(0-t) exist for the period, PKEXRSN is missing, and NCAEXRSN is missing for the record: descriptive PK summaries.",
  "MT.ANL02FL.PP", "Y when ANL01FL = Y and the participant has evaluable periods (Cmax and AUC(0-t), PKEXRSN missing) for both products: bioequivalence analysis. The supportive AUC(0-inf) analysis uses participants with ANL02FL = Y for AUCIFO in both periods.",
  "MT.PKEXRSN", "SAP period rules in order: emesis within 2 h of dosing (ADAE; a protocol violation documented before bioanalysis, ICH M13A 2.2.1); pre-dose concentration above 5% of the period's Cmax (ICH M13A 2.2.3.3) and AUC(0-t) below 5% of the product's geometric mean AUC without the participant (ICH M13A 2.2.1.1), both applied to the bioanalytical results.",
  "MT.NCAEXRSN", "PP.PPEXCL (PKNCA exclude() in 04_analysis/01_nca.R) decoded: adjusted R-squared of the terminal fit below the SAP minimum flags lambda z and every parameter that depends on it; AUC(0-inf) more than the SAP maximum extrapolated flags AUC(0-inf). The value stays in AVAL.",
  "MT.ADT.PP", "admiral::derive_vars_dt() of PP.PPRFTDTC.",
  "MT.AVISIT.PP", "Day ADY, as in admiral ad_adpp.R.",
  "MT.APERIOD.AE", "admiral::create_period_dataset() + derive_vars_joined(): the period whose start and end datetimes contain ASTDTM; TRTA from that period.",
  "MT.ASEVN", "1 = MILD, 2 = MODERATE, 3 = SEVERE.",
  "MT.ASTDTM", "admiral::derive_vars_dtm() of AESTDTC, highest imputation month, time imputed to the first.",
  "MT.AENDTM", "admiral::derive_vars_dtm() of AEENDTC, highest imputation month, time imputed to the last.",
  "MT.TRTEMFL", "admiral::derive_var_trtemfl(): onset on or after TRTSDTM.") %>%
  dplyr::mutate(Name = paste("Algorithm for", sub("^MT\\.", "", ID)), Type = "Computation", `Expression Context` = NA,
                `Expression Code` = NA, Document = NA, Pages = NA) %>%
  dplyr::select(ID, Name, Type, Description, `Expression Context`, `Expression Code`, Document, Pages)
stopifnot(all(na.omit(unique(variables$Method)) %in% methods$ID), all(na.omit(unique(variables$Codelist)) %in% codelists$ID))

study_sheet <- tibble::tibble(Attribute = c("StudyName", "StudyDescription", "ProtocolName", "Note"),
                              Value = c(STUDY$studyid, STUDY$title, STUDY$studyid, SYNTHETIC_NOTE))
dictionaries <- tibble::tibble(ID = "MEDDRA", Name = "Adverse event dictionary", `Data Type` = "text", Dictionary = "MEDDRA",
                               Version = paste(STUDY$meddra_version, "(synthetic coding)"))
empty_vl <- tibble::tibble(Order = integer(), Dataset = character(), Variable = character(), `Where Clause` = character(),
                           Description = character(), `Data Type` = character(), Length = integer(), `Significant Digits` = integer(),
                           Format = character(), Mandatory = character(), Codelist = character(), Origin = character(),
                           Pages = character(), Method = character(), Predecessor = character(), Comment = character())
empty_wc <- tibble::tibble(ID = character(), Dataset = character(), Variable = character(), Comparator = character(), Value = character())
comments <- tibble::tibble(ID = "CM.SYNTHETIC", Description = SYNTHETIC_NOTE, Document = NA, Pages = NA)
documents <- tibble::tibble(ID = "SAP", Title = "SAP excerpt (synthetic)", Href = "../../02_sap/sap_excerpt.html")

SPEC <- list(Study = study_sheet, Datasets = datasets, Variables = variables, ValueLevel = empty_vl, WhereClauses = empty_wc,
             Codelists = codelists, Dictionaries = dictionaries, Methods = methods, Comments = comments, Documents = documents)

## xlsx: rewrite only when the cell content changes (zip timestamps change on every write)
xlsx_writer <- function(path) {
  wb <- openxlsx::createWorkbook(creator = "study/03_adam/spec/build_spec.R", title = "ADaM specification (synthetic)")
  for (s in names(SPEC)) {
    openxlsx::addWorksheet(wb, s)
    openxlsx::writeData(wb, s, as.data.frame(SPEC[[s]], check.names = FALSE), keepNA = FALSE)
  }
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
}
xlsx_same <- function(a, b) {
  sa <- readxl::excel_sheets(a); sb <- readxl::excel_sheets(b)
  identical(sa, sb) && all(vapply(sa, function(s) identical(
    as.data.frame(readxl::read_excel(a, sheet = s, col_types = "text")),
    as.data.frame(readxl::read_excel(b, sheet = s, col_types = "text"))), logical(1)))
}
write_if_changed(file.path(spec_dir, "adam_spec.xlsx"), xlsx_writer, xlsx_same)
write_json_det(lapply(SPEC, function(x) as.data.frame(x, check.names = FALSE)), file.path(spec_dir, "adam_spec.json"))
cat(sprintf("[03_adam/spec] %d datasets, %d variables, %d codelist terms, %d methods\n",
            nrow(datasets), nrow(variables), nrow(codelists), nrow(methods)))
