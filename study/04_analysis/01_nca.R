################################################################################
# 04_analysis/01_nca.R: non-compartmental analysis with PKNCA 0.12.1, configured per the
# SAP (02_sap/analysis_parameters.json) and ICH M13A. SYNTHETIC DATA ONLY.
#   * actual times: ADPC.ARRLT (pre-dose samples set to time 0);
#   * BLQ kept as 0 in every position: conc.blq = list(first, middle, last = "keep")
#     (PKNCA default drops a BLQ value in the middle of a profile); PKNCA excludes zeros
#     from the lambda z fit;
#   * AUC: "lin up/log down" (PKNCA uses the linear trapezoid when a concentration is 0);
#     lambda z: at least 3 points after tmax, adjusted R-squared.
#   * SAP parameter rules through PKNCA exclude(): adjusted R-squared below 0.90 flags every
#     lambda z-based parameter; more than 20% extrapolated flags AUC(0-inf). The values are
#     kept and the reason recorded (PP.PPEXCL, then ADPP.NCAEXRSN).
#   * the same NCA with the PKNCA default BLQ handling (middle = "drop"), to show what the
#     ICH M13A setting changes (04_analysis/blq_rule_effect.csv).
# The parameters are written as an SDTM-like PP domain (03_adam/sdtm/pp.csv), which
# 03_adam/05_adpp.R turns into ADPP.
#
# Inputs : object adpc, 02_sap/analysis_parameters.json
# Outputs: 03_adam/sdtm/pp.csv, 04_analysis/nca_parameters.csv, nca_settings.json,
#          blq_rule_effect.csv; objects nca_wide, nca_excl, blq_effect
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
                 allow.tmax.in.half.life = SAP$nca$allow_tmax_in_half_life)
o_conc <- PKNCAconc(conc_in, AVAL ~ TIME | APERIOD + TRTA + USUBJID)
o_dose <- PKNCAdose(dose_in, DOSE ~ TIME | APERIOD + TRTA + USUBJID)
intervals <- data.frame(start = 0, end = Inf, cmax = TRUE, tmax = TRUE, tlast = TRUE, clast.obs = TRUE,
                        auclast = TRUE, aucinf.obs = TRUE, aucpext.obs = TRUE, half.life = TRUE,
                        lambda.z = TRUE, lambda.z.n.points = TRUE, adj.r.squared = TRUE,
                        lambda.z.time.first = TRUE, lambda.z.time.last = TRUE)
o_data <- PKNCAdata(o_conc, o_dose, intervals = intervals, options = nca_opts)
o_res  <- pk.nca(o_data)
## SAP parameter rules. PKNCA's thresholds act only through exclude(); setting them as
## options alone changes nothing. The rule function below does what PKNCA's
## exclude_nca_by_param() does (one parameter against a threshold, flagging the parameters
## that depend on it). PKNCA 0.12.1's own version checks its threshold with
## checkmate::expect_number(), which stops unless testthat is installed, so it is not used.
nca_rule <- function(parameter, affected, min_thr = -Inf, max_thr = Inf, label) function(x, ...) {
  ret <- rep(NA_character_, nrow(x))
  i <- which(x$PPTESTCD == parameter)
  if (length(i) == 1 && !is.na(x$PPORRES[i]) && (x$PPORRES[i] < min_thr || x$PPORRES[i] > max_thr))
    ret[x$PPTESTCD %in% affected] <- label
  ret
}
o_res <- exclude(o_res, FUN = nca_rule("adj.r.squared", affected = get.parameter.deps("half.life"),
                                       min_thr = SAP$nca$min_hl_adj_r_squared,
                                       label = sprintf("adj.r.squared < %g", SAP$nca$min_hl_adj_r_squared)))
o_res <- exclude(o_res, FUN = nca_rule("aucpext.obs", affected = "aucinf.obs", max_thr = SAP$nca$max_aucinf_pext_pct,
                                       label = sprintf("aucpext.obs > %g", SAP$nca$max_aucinf_pext_pct)))
res <- as.data.frame(o_res)

## --- what the ICH M13A BLQ setting changes: the same NCA with the PKNCA default ------------
blq_default <- PKNCA.options("conc.blq")                 # first = keep, middle = drop, last = keep
nca_opts_def <- nca_opts; nca_opts_def$conc.blq <- blq_default
res_def <- as.data.frame(pk.nca(PKNCAdata(o_conc, o_dose, intervals = intervals, options = nca_opts_def)))
mid_blq <- conc_in %>% arrange(USUBJID, APERIOD, TIME) %>% group_by(USUBJID, APERIOD) %>%
  summarise(n_mid_blq = sum(AVAL == 0 & cumsum(AVAL > 0) > 0 & rev(cumsum(rev(AVAL > 0))) > 0), .groups = "drop")
blq_effect <- res %>% select(USUBJID, APERIOD, TRTA, PPTESTCD, M13A = PPORRES) %>%
  inner_join(select(res_def, USUBJID, APERIOD, PPTESTCD, PKNCA_default = PPORRES), by = c("USUBJID", "APERIOD", "PPTESTCD")) %>%
  filter(PPTESTCD %in% c("cmax", "auclast", "aucinf.obs", "half.life"), abs(M13A - PKNCA_default) > 1e-9 * pmax(1, abs(M13A))) %>%
  left_join(mid_blq, by = c("USUBJID", "APERIOD")) %>%
  mutate(difference = M13A - PKNCA_default, pct_difference = 100 * difference / PKNCA_default) %>%
  arrange(USUBJID, APERIOD, PPTESTCD) %>% as.data.frame()

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

## values flagged by the parameter rules (kept in PP and ADPP; not summarized or analyzed)
nca_excl <- pp %>% filter(!is.na(PPEXCL)) %>% select(USUBJID, APERIOD, TRTA, PPTESTCD, PPSTRESN, PPEXCL) %>% as.data.frame()
excl_summary <- nca_excl %>% group_by(rule = PPEXCL) %>%
  summarise(profiles = n_distinct(paste(USUBJID, APERIOD)), parameters = paste(unique(PPTESTCD), collapse = ", "),
            which = paste(unique(paste(USUBJID, "Period", APERIOD)), collapse = "; "), .groups = "drop")
nca_wide <- nca_wide %>%
  left_join(nca_excl %>% group_by(USUBJID, APERIOD) %>%
              summarise(AUCIFO_EXCL = ifelse(any(PPTESTCD == "AUCIFO"), "Y", "N"),
                        LAMZ_EXCL = ifelse(any(PPTESTCD == "LAMZ"), "Y", "N"), .groups = "drop"),
            by = c("USUBJID", "APERIOD")) %>%
  mutate(AUCIFO_EXCL = coalesce(AUCIFO_EXCL, "N"), LAMZ_EXCL = coalesce(LAMZ_EXCL, "N"))

write_csv_det(pp %>% select(-APERIOD, -TRTA), sp("03_adam", "sdtm", "pp.csv"))
write_csv_det(nca_wide, sp("04_analysis", "nca_parameters.csv"))
blq_effect <- blq_effect %>% left_join(select(pmap, PPTESTCD_PKNCA, PARAMCD = PPTESTCD), by = c("PPTESTCD" = "PPTESTCD_PKNCA")) %>%
  select(USUBJID, APERIOD, TRTA, PARAMCD, n_mid_blq, M13A, PKNCA_default, difference, pct_difference)
write_csv_det(blq_effect, sp("04_analysis", "blq_rule_effect.csv"))
write_json_det(list(engine = paste("PKNCA", pkg_version("PKNCA")), options = nca_opts,
                    parameter_rules = list(
                      min_hl_adj_r_squared = SAP$nca$min_hl_adj_r_squared, max_aucinf_pext_pct = SAP$nca$max_aucinf_pext_pct,
                      implementation = c(sprintf("PKNCA exclude(): adj.r.squared below %g flags get.parameter.deps(\"half.life\")", SAP$nca$min_hl_adj_r_squared),
                                         sprintf("PKNCA exclude(): aucpext.obs above %g flags aucinf.obs", SAP$nca$max_aucinf_pext_pct)),
                      excluded_values = excl_summary),
                    time = SAP$nca$time_variable, profiles = nrow(nca_wide),
                    intervals = "0 to Inf, one interval per participant and period",
                    blq = list(setting = nca_opts$conc.blq, pknca_default = blq_default,
                               profiles_with_blq_between_quantifiable = sum(mid_blq$n_mid_blq > 0),
                               profiles_changed_vs_pknca_default = length(unique(paste(blq_effect$USUBJID, blq_effect$APERIOD))))),
               sp("04_analysis", "nca_settings.json"))
cat(sprintf("[04_analysis/nca] PKNCA %s: %d profiles, %d parameters; lambda z not estimable in %d; rule-flagged profiles: %s; BLQ between quantifiable values in %d profile(s)\n",
            pkg_version("PKNCA"), nrow(nca_wide), nrow(pp), sum(is.na(nca_wide$LAMZ)),
            if (nrow(excl_summary)) paste(sprintf("%s (%d)", excl_summary$rule, excl_summary$profiles), collapse = ", ") else "none",
            sum(mid_blq$n_mid_blq > 0)))
