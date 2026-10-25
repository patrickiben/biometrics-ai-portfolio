################################################################################
# 04_analysis/01_nca.R: non-compartmental analysis with PKNCA 0.12.1, configured per the
# SAP (02_sap/analysis_parameters.json) and ICH M13A. SYNTHETIC DATA ONLY.
#   * actual times: ADPC.ARRLT (pre-dose samples set to time 0);
#   * BLQ kept as 0 in every position: conc.blq = list(first, middle, last = "keep")
#     (PKNCA default drops a BLQ value in the middle of a profile); PKNCA excludes zeros
#     from the lambda z fit;
#   * AUC: "lin up/log down"; lambda z: at least 3 points after tmax, adjusted R-squared.
# The parameters are written as an SDTM-like PP domain (03_adam/sdtm/pp.csv), which
# 03_adam/05_adpp.R turns into ADPP.
#
# Inputs : object adpc, 02_sap/analysis_parameters.json
# Outputs: 03_adam/sdtm/pp.csv, 04_analysis/nca_parameters.csv, 04_analysis/nca_settings.json
################################################################################
suppressPackageStartupMessages(library(PKNCA))
SAP <- jsonlite::read_json(sp("02_sap", "analysis_parameters.json"), simplifyVector = TRUE)

conc_in <- adpc %>%
  filter(PARAMCD == "SIMDRUG", ANL01FL == "Y") %>%
  mutate(TIME = pmax(ARRLT, 0)) %>%                       # pre-dose sample at time 0 (SAP)
  select(STUDYID, USUBJID, APERIOD, TRTA, TIME, AVAL, PCRFTDTM) %>%
  as.data.frame()
dose_in <- adpc %>% filter(PARAMCD == "DOSE") %>%
  transmute(STUDYID, USUBJID, APERIOD, TRTA, TIME = 0, DOSE = AVAL) %>% as.data.frame()

PKNCA.options(default = TRUE)
nca_opts <- list(auc.method = SAP$nca$auc_method,
                 conc.blq = SAP$nca$conc_blq,
                 min.hl.points = SAP$nca$min_hl_points,
                 allow.tmax.in.half.life = SAP$nca$allow_tmax_in_half_life,
                 min.hl.r.squared = SAP$nca$min_hl_r_squared,
                 max.aucinf.pext = SAP$nca$max_aucinf_pext_pct)
o_conc <- PKNCAconc(conc_in, AVAL ~ TIME | APERIOD + TRTA + USUBJID)
o_dose <- PKNCAdose(dose_in, DOSE ~ TIME | APERIOD + TRTA + USUBJID)
intervals <- data.frame(start = 0, end = Inf, cmax = TRUE, tmax = TRUE, tlast = TRUE, clast.obs = TRUE,
                        auclast = TRUE, aucinf.obs = TRUE, aucpext.obs = TRUE, half.life = TRUE,
                        lambda.z = TRUE, lambda.z.n.points = TRUE, adj.r.squared = TRUE,
                        lambda.z.time.first = TRUE, lambda.z.time.last = TRUE)
o_data <- PKNCAdata(o_conc, o_dose, intervals = intervals, options = nca_opts)
o_res  <- pk.nca(o_data)
res <- as.data.frame(o_res)

## PKNCA parameter name -> CDISC PPTESTCD / PPTEST / unit
pmap <- tibble::tribble(
  ~PPTESTCD_PKNCA,        ~PPTESTCD, ~PPTEST,                                  ~PPSTRESU,
  "cmax",                 "CMAX",    "Max Conc",                               "ng/mL",
  "tmax",                 "TMAX",    "Time of CMAX",                           "h",
  "tlast",                "TLST",    "Time of Last Nonzero Conc",              "h",
  "clast.obs",            "CLST",    "Last Nonzero Conc",                      "ng/mL",
  "auclast",              "AUCLST",  "AUC to Last Nonzero Conc",               "h*ng/mL",
  "aucinf.obs",           "AUCIFO",  "AUC Infinity Obs",                       "h*ng/mL",
  "aucpext.obs",          "AUCPEO",  "AUC %Extrapolation Obs",                 "%",
  "half.life",            "LAMZHL",  "Half-Life Lambda z",                     "h",
  "lambda.z",             "LAMZ",    "Lambda z",                               "1/h",
  "lambda.z.n.points",    "LAMZNPT", "Number of Points for Lambda z",          "",
  "adj.r.squared",        "R2ADJ",   "R Squared Adjusted",                     "",
  "lambda.z.time.first",  "LAMZLL",  "Lambda z Lower Limit",                   "h",
  "lambda.z.time.last",   "LAMZUL",  "Lambda z Upper Limit",                   "h")

ref_dt <- conc_in %>% distinct(USUBJID, APERIOD, PCRFTDTM)
pp <- res %>%
  inner_join(pmap, by = c("PPTESTCD" = "PPTESTCD_PKNCA")) %>%
  left_join(ref_dt, by = c("USUBJID", "APERIOD")) %>%
  transmute(STUDYID = STUDY$studyid, DOMAIN = "PP", USUBJID, PPTESTCD = PPTESTCD.y, PPTEST,
            PPCAT = "SIMDRUG", PPSPEC = "PLASMA",
            PPSTRESN = PPORRES,                                   # numeric result, before PPORRES becomes text
            PPORRES = ifelse(is.na(PPSTRESN), NA_character_, formatC(signif(PPSTRESN, 6), format = "fg", digits = 6)),
            PPORRESU = PPSTRESU, PPSTRESC = PPORRES, PPSTRESU,
            PPSTAT = ifelse(is.na(PPSTRESN), "NOT DONE", NA_character_),
            PPREASND = ifelse(is.na(PPSTRESN), ifelse(is.na(exclude), "NOT CALCULABLE", toupper(exclude)), NA_character_),
            PPEXCL = exclude,
            PPRFTDTC = format(PCRFTDTM, "%Y-%m-%dT%H:%M", tz = "UTC"),
            VISITNUM = APERIOD, APERIOD, TRTA) %>%
  arrange(USUBJID, APERIOD, match(PPTESTCD, pmap$PPTESTCD)) %>%
  group_by(USUBJID) %>% mutate(PPSEQ = row_number()) %>% ungroup()

nca_wide <- pp %>% select(USUBJID, APERIOD, TRTA, PPTESTCD, PPSTRESN) %>%
  pivot_wider(names_from = PPTESTCD, values_from = PPSTRESN) %>% arrange(USUBJID, APERIOD)

write_csv_det(pp %>% select(-APERIOD, -TRTA), sp("03_adam", "sdtm", "pp.csv"))
write_csv_det(nca_wide, sp("04_analysis", "nca_parameters.csv"))
write_json_det(list(engine = paste("PKNCA", pkg_version("PKNCA")), options = nca_opts,
                    time = SAP$nca$time_variable, profiles = nrow(nca_wide),
                    intervals = "0 to Inf, one interval per participant and period",
                    excluded_values = sort(unique(na.omit(res$exclude)))),
               sp("04_analysis", "nca_settings.json"))
cat(sprintf("[04_analysis/nca] PKNCA %s: %d profiles, %d parameters; lambda z not estimable in %d profiles\n",
            pkg_version("PKNCA"), nrow(nca_wide), nrow(pp), sum(is.na(nca_wide$LAMZ))))
