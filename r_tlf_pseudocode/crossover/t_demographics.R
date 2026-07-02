################################################################################
# TABLE     : t_demographics  (Crossover - 2x2 / Williams)
# TITLE     : Demographic and Baseline Characteristics
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADSL
# NOTE      : PSEUDOCODE. PARTICIPANT-LEVEL table. In a crossover, demographics are
#             fixed within participant, so columns are the randomized treatment
#             SEQUENCE (dv$seqvar = TRTSEQP) + Total -- NOT TRTA (which varies by
#             period). Continuous: n, Mean (SD), Median, Min-Max. Categorical:
#             n (%). % denominator = SAFFL N per sequence from bign().
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")   # seqvar = TRTSEQP (participant-level sequence column)

adsl <- adam$adsl %>% filter(SAFFL == "Y")     # one row per participant

## column denominators (N=) per SEQUENCE + Total
denom <- bign(adsl, trtvar = dv$seqvar, popfl = "SAFFL")

## --- continuous block: AGE, WEIGHTBL, HEIGHTBL, BMIBL ----------------------
cont_block <- function(var, label, dp = 1L, ord) {
  descstat(adsl, var = var, by = dv$seqvar, dp = dp) %>%
    transmute(trt = .data[[dv$seqvar]], characteristic = label, ord = ord,
              `n`              = as.character(n),
              `Mean (SD)`      = paste(c_mean, c_sd),
              `Median`         = c_median,
              `Min, Max`       = c_minmax) %>%
    pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`), names_to = "stat", values_to = "value")
}
cont <- bind_rows(
  cont_block("AGE",      "Age (years)",  0L, 1),
  cont_block("WEIGHTBL", "Weight (kg)",  1L, 2),
  cont_block("HEIGHTBL", "Height (cm)",  1L, 3),
  cont_block("BMIBL",    "BMI (kg/m^2)", 1L, 4))

## --- categorical block: SEX, RACE, ETHNIC ---------------------------------
cat_block <- function(var, label, ord) {
  catfreq(adsl, var = var, by = dv$seqvar, denom = denom) %>%
    transmute(trt = .data[[dv$seqvar]], characteristic = label, ord, stat = cat, value = disp)
}
catg <- bind_rows(
  cat_block("SEX",    "Sex n (%)",       5),
  cat_block("RACE",   "Race n (%)",      6),
  cat_block("ETHNIC", "Ethnicity n (%)", 7))

## --- stack, one column per SEQUENCE, render -------------------------------
tab <- bind_rows(cont, catg) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(ord)

ttl <- tfl_titles(num = "14.1.2", type = "Table",
                  text = "Demographic and Baseline Characteristics",
                  pop  = "Safety Population",
                  foot = "Columns = randomized treatment sequence (TRTSEQP); demographics are fixed within participant. Percentages based on N in the Safety Population per sequence.")

## rtables layout (regulatory): characteristic -> statistic rows x sequence cols
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab) for an HTML/Quarto rendering
print(tab)
