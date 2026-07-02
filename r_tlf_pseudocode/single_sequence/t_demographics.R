################################################################################
# TABLE     : t_demographics  (Single-/Fixed-Sequence DDI)
# TITLE     : Demographic and Baseline Characteristics
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADSL
# NOTE      : PSEUDOCODE. Continuous: n, Mean (SD), Median, Min-Max.
#             Categorical: n (%). PARTICIPANT-LEVEL table -> columns = the ONE fixed
#             sequence (dv$seqvar = TRTSEQP) + Total. NO randomized sequence and
#             NO per-period split here (demographics are participant attributes).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # seqvar = TRTSEQP, seqvarn = TRTSEQPN
options(tfl.study = env$study)

adsl <- adam$adsl %>% filter(SAFFL == "Y")      # one row per participant

## column denominators (N=) per fixed sequence + Total (participant-level)
denom <- bign(adsl, trtvar = dv$seqvar, popfl = "SAFFL")

## --- continuous block: AGE, WEIGHTBL, HEIGHTBL, BMIBL ----------------------
cont_block <- function(var, label, dp = 1L, ord) {
  descstat(adsl, var = var, by = dv$seqvar, dp = dp) %>%
    transmute(seq = .data[[dv$seqvar]], characteristic = label, ord = ord,
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

## --- categorical block: SEX, RACE, ETHNIC, AGEGR1 -------------------------
cat_block <- function(var, label, ord) {
  catfreq(adsl, var = var, by = dv$seqvar, denom = denom) %>%
    transmute(seq = .data[[dv$seqvar]], characteristic = label, ord, stat = cat, value = disp)
}
catg <- bind_rows(
  cat_block("SEX",    "Sex n (%)",       5),
  cat_block("RACE",   "Race n (%)",      6),
  cat_block("ETHNIC", "Ethnicity n (%)", 7),
  cat_block("AGEGR1", "Age group n (%)", 8))

## --- stack, one column per fixed sequence, render -------------------------
tab <- bind_rows(cont, catg) %>%
  pivot_wider(names_from = seq, values_from = value) %>%
  arrange(ord)

ttl <- tfl_titles(num = "14.1.2", type = "Table",
                  text = "Demographic and Baseline Characteristics",
                  pop  = "Safety Population",
                  foot = paste("Single-fixed-sequence DDI design; one fixed treatment order.",
                               "Percentages based on the number of participants in the Safety",
                               "Population per sequence column."))

## rtables layout (regulatory): characteristic -> statistic rows x sequence cols
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab) for an HTML/Quarto rendering
print(tab)
