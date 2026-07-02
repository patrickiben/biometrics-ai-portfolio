################################################################################
# TABLE     : t_demographics  (Multiple Ascending Dose)
# TITLE     : Demographic and Baseline Characteristics by Dose Cohort
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADSL
# NOTE      : PSEUDOCODE. Continuous: n, Mean (SD), Median, Min-Max.
#             Categorical: n (%). MAD = parallel dose cohorts; columns = DOSE
#             LEVEL (TRT01A) with placebo pooled into one column + Total. One
#             treatment per participant -> participant-level table, no period/sequence.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # -> trtvar = TRT01A (dose level), trtnvar = TRT01AN

## one row per participant; pool placebo across ascending cohorts into one column
adsl <- adam$adsl %>%
  filter(SAFFL == "Y") %>%
  mutate(
    dose_col = if_else(toupper(TRT01A) == "PLACEBO" | TRT01AN == 0,
                       "Placebo", .data[[dv$trtvar]]),
    dose_ord = if_else(toupper(TRT01A) == "PLACEBO" | TRT01AN == 0,
                       0, .data[[dv$trtnvar]]))

## column denominators (N=) per dose cohort + Total (key on dose_col)
denom <- bign(adsl %>% mutate(.dc = dose_col), trtvar = ".dc", popfl = "SAFFL")

## --- continuous block: AGE, WEIGHTBL, HEIGHTBL, BMIBL ----------------------
cont_block <- function(var, label, dp = 1L, ord) {
  descstat(adsl, var = var, by = "dose_col", dp = dp) %>%
    transmute(trt = dose_col, characteristic = label, ord = ord,
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
  catfreq(adsl %>% mutate(.dc = dose_col), var = var, by = ".dc", denom = denom) %>%
    transmute(trt = .dc, characteristic = label, ord, stat = cat, value = disp)
}
catg <- bind_rows(
  cat_block("SEX",    "Sex n (%)",       5),
  cat_block("RACE",   "Race n (%)",      6),
  cat_block("ETHNIC", "Ethnicity n (%)", 7))

## --- stack, one column per dose cohort, render ----------------------------
tab <- bind_rows(cont, catg) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(ord)

ttl <- tfl_titles(num = "14.1.2", type = "Table",
                  text = "Demographic and Baseline Characteristics by Dose Cohort",
                  pop  = "Safety Population",
                  foot = "MAD: columns = ascending dose cohorts (TRT01A) with placebo pooled. Percentages based on Safety Population N per cohort.")

## rtables layout (regulatory): characteristic -> statistic rows x cohort columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab) for an HTML/Quarto rendering
print(tab)
