################################################################################
# PROGRAM   : 00_setup_helpers.R
# PURPOSE   : Shared environment + helper functions for the early-phase
#             clin-pharm TLF library (R twin of sas_tlf_pseudocode). source()
#             this at the top of every TLF program. PSEUDOCODE — illustrative
#             structure, not validated code.
# STACK     : dplyr/tidyr (derivation) - rtables (regulatory table layout) -
#             ggplot2 (figures) - emmeans/lme4|nlme (mixed models / BE).
#             admiral/tern (pharmaverse) are the higher-level production path.
# INPUT     : ADaM data frames (ADSL, ADAE, ADLB, ADVS, ADEG, ADPC, ADPP,
#             ADPD, ADIS, ADEX), CDISC ADaM-conformant.
# CONVENTION: All population flags, treatment, period and analysis variables
#             come from ADaM (no re-derivation). Reported numbers come from
#             validated tools (Phoenix WinNonlin, Pinnacle 21, EDC) per SOP;
#             nothing here originates a reported number.
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(stringr); library(purrr); library(tibble)
  library(rtables); library(ggplot2)
  library(emmeans); library(lme4); library(broom); library(broom.mixed)
})

## --- environment ------------------------------------------------------------
setup <- function(study = "CP-101", adam = "/data/adam", out = "/data/tfl") {
  options(stringsAsFactors = FALSE)
  ## read ADaM (haven::read_xpt / read_sas) or assume already loaded as tibbles
  ## adsl <- haven::read_xpt(file.path(adam, "adsl.xpt")) ...
  list(study = study, adam = adam, out = out)
}

## --- design helper: resolve column + by-structure for a design --------------
## design = PARALLEL | CROSSOVER | SINGLESEQ | SAD | MAD
##   trtvar/trtnvar : period/actual treatment (BDS: ADAE/ADPP/...)
##   seqvar/seqvarn : PARTICIPANT-LEVEL sequence label on ADSL (crossover &
##                    single-/fixed-sequence) -> use for participant-level tables
##                    (disposition/demographics/baseline/medhx)
##   byperiod       : period columns; per-period denominators must come from a
##                    period-bearing source (ADEX/ADIS/ADPD), NOT ADSL.
design_vars <- function(design = c("PARALLEL","CROSSOVER","SINGLESEQ","SAD","MAD")) {
  design <- toupper(match.arg(design))
  switch(design,
    CROSSOVER = list(trtvar="TRTA",   trtnvar="TRTAN",   seqvar="TRTSEQP", seqvarn="TRTSEQPN",
                     byperiod=c("APERIOD","APERIODC")),
    SINGLESEQ = list(trtvar="TRTA",   trtnvar="TRTAN",   seqvar="TRTSEQP", seqvarn="TRTSEQPN",
                     byperiod=c("APERIOD","APERIODC")),
    ## PARALLEL / SAD / MAD : one treatment per participant
    list(trtvar="TRT01A", trtnvar="TRT01AN", seqvar=NA_character_, seqvarn=NA_character_,
         byperiod=character(0)))
}

## --- big N: population counts per column (+ Total) ---------------------------
## trtvar = column variable; popfl = population flag (SAFFL/PKFL/ITTFL/...)
bign <- function(df, trtvar, popfl = "SAFFL") {
  d <- df %>% filter(.data[[popfl]] == "Y")
  per <- d %>% group_by(trt = .data[[trtvar]]) %>%
    summarise(N = n_distinct(USUBJID), .groups = "drop")
  bind_rows(per, tibble(trt = "Total", N = n_distinct(d$USUBJID)))
}

## --- descriptive stats for a continuous analysis var (AVAL/CHG/PCHG) --------
descstat <- function(df, var = "AVAL", by, dp = 1L) {
  df %>% group_by(across(all_of(by))) %>%
    summarise(
      n      = sum(!is.na(.data[[var]])),
      mean   = mean(.data[[var]],   na.rm = TRUE),
      sd     = sd(.data[[var]],     na.rm = TRUE),
      median = median(.data[[var]], na.rm = TRUE),
      min    = min(.data[[var]],    na.rm = TRUE),
      max    = max(.data[[var]],    na.rm = TRUE),
      .groups = "drop") %>%
    mutate(
      c_mean   = sprintf(paste0("%.", dp+1L, "f"), mean),
      c_sd     = sprintf(paste0("(%.", dp+2L, "f)"), sd),
      c_median = sprintf(paste0("%.", dp+1L, "f"), median),
      c_minmax = sprintf(paste0("%.", dp, "f, %.", dp, "f"), min, max))
}

## --- categorical n (%) with denominator from bign() -------------------------
catfreq <- function(df, var, by, denom) {
  cnt <- df %>% group_by(across(all_of(by)), cat = .data[[var]]) %>%
    summarise(n = n_distinct(USUBJID), .groups = "drop")
  cnt %>% left_join(denom, by = setNames("trt", tail(by, 1))) %>%   # join on column var
    mutate(pct = 100 * n / N,
           disp = sprintf("%d (%.1f%%)", n, pct))
}

## --- AE counting: participants with >=1 event (NOT event rows) ------------------
## Counts distinct USUBJID per column, per requested by-levels. Treatment-
## emergent via TRTEMFL. Pass `where` as a dplyr filter expression.
aecount <- function(df, trtvar, where = quote(TRTEMFL == "Y"), byvars) {
  df %>% filter(!!where) %>%
    group_by(trt = .data[[trtvar]], across(all_of(byvars))) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop")
  ## downstream: join to bign() for n (%); order SOC by overall freq desc, PT
  ## within SOC desc; prepend an "Any TEAE" overall row (distinct participants).
}

## --- PK descriptive stats: arithmetic + GEOMETRIC ---------------------------
## Geo Mean = exp(mean(log)); Geo CV% = 100*sqrt(exp(var(log)) - 1). Computed
## across participants ON THE LOG SCALE -- never exp(arithmetic mean of raw).
## Tmax is reported as Median (Min, Max) only (handle separately).
pkstats <- function(df, var = "AVAL", by) {
  df %>% filter(.data[[var]] > 0) %>%
    group_by(across(all_of(by))) %>%
    summarise(
      n       = n(),
      mean    = mean(.data[[var]]),
      sd      = sd(.data[[var]]),
      cv      = 100 * sd(.data[[var]]) / mean(.data[[var]]),
      geomean = exp(mean(log(.data[[var]]))),
      geocv   = 100 * sqrt(exp(stats::var(log(.data[[var]]))) - 1),
      median  = median(.data[[var]]),
      min     = min(.data[[var]]),
      max     = max(.data[[var]]),
      .groups = "drop")
}

## --- titles / footnotes banner (feed to rtables / ggplot) -------------------
tfl_titles <- function(num, type = "Table", text, pop = "Safety Population",
                       foot = NULL, study = getOption("tfl.study", "CP-101")) {
  list(
    titles    = c(sprintf("%s  %s", study, format(Sys.Date())),
                  sprintf("%s %s", type, num), text, sprintf("(%s)", pop)),
    footnotes = c(foot, "Source: ADaM   Program: <program>.R"))
}

## --- small format helpers ---------------------------------------------------
n_pct <- function(n, N) sprintf("%d (%.1f%%)", n, 100 * n / N)
fmt   <- function(x, dp = 1L) formatC(x, format = "f", digits = dp)
