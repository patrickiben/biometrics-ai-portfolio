################################################################################
# TABLE     : t_exposure  (Single-/Fixed-Sequence DDI)
# TITLE     : Extent of Study Drug Exposure by Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADEX (one row per participant per dosing period/interval)
# NOTE      : PSEUDOCODE. PERIOD table -> split by dv$byperiod (APERIOD/APERIODC):
#             Period 1 = reference/victim alone, Period 2 = test/victim +
#             perpetrator. Per-PERIOD denominators come from ADEX (participants dosed
#             per APERIOD where SAFFL == "Y") -- NEVER from one-row-per-participant
#             ADSL. Dose/duration descriptive per period; compliance n (%).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
options(tfl.study = env$study)
perN <- dv$byperiod[1]; perC <- dv$byperiod[2]  # numeric + character period

adex <- adam$adex %>% filter(SAFFL == "Y")      # one row per participant per period

## --- per-PERIOD denominators FROM ADEX (participants dosed in each period) ------
## House rule: per-period N comes from a period-bearing source (ADEX), not ADSL.
perdenom <- adex %>%
  group_by(per = .data[[perC]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")

## --- continuous exposure metrics per period --------------------------------
## ADEX analysis vars: total dose (AVAL on a dose param), duration (TRTDURD),
## number of doses (NDOSES). One ADEX record per participant*period already.
cont_block <- function(var, label, dp, ord) {
  adex %>%
    descstat(var = var, by = perC, dp = dp) %>%
    transmute(per = .data[[perC]], characteristic = label, ord,
              `n`         = as.character(n),
              `Mean (SD)` = paste(c_mean, c_sd),
              `Median`    = c_median,
              `Min, Max`  = c_minmax) %>%
    pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`), names_to = "stat", values_to = "value")
}
cont <- bind_rows(
  cont_block("AVAL",    "Total dose administered (mg)", 1L, 1),
  cont_block("TRTDURD", "Duration of exposure (days)",  0L, 2),
  cont_block("NDOSES",  "Number of doses",              0L, 3))

## --- compliance categories per period (n %) --------------------------------
## EXCMPLFL/compliance band on ADEX; denominator = per-period dosed N.
comp <- adex %>%
  mutate(per = .data[[perC]],
         comp_cat = case_when(
           is.na(EXCMPLPC)        ~ "Missing",
           EXCMPLPC >= 80 & EXCMPLPC <= 120 ~ "Compliant (80-120%)",
           TRUE                   ~ "Non-compliant")) %>%
  group_by(per, characteristic = "Compliance n (%)", stat = comp_cat) %>%
  summarise(n = n_distinct(USUBJID), .groups = "drop") %>%
  left_join(perdenom, by = "per") %>%
  mutate(value = n_pct(n, N), ord = 4L) %>%
  select(per, characteristic, ord, stat, value)

## --- assemble: one column per PERIOD ---------------------------------------
tab <- bind_rows(cont, comp) %>%
  pivot_wider(names_from = per, values_from = value) %>%
  arrange(ord)

ttl <- tfl_titles(num = "14.1.4", type = "Table",
   text = "Extent of Study Drug Exposure by Period",
   pop  = "Safety Population",
   foot = paste("Single-fixed-sequence DDI: Period 1 = reference (victim alone),",
                "Period 2 = test (victim + perpetrator). Per-period denominators =",
                "participants dosed in each period (ADEX, SAFFL = Y). Compliance =",
                "administered / planned doses."))

## rtables layout: characteristic -> stat rows x PERIOD columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
