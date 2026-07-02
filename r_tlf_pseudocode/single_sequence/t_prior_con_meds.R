################################################################################
# TABLE     : t_prior_con_meds  (Single-/Fixed-Sequence DDI)
# TITLE     : Prior and Concomitant Medications by Drug Class and Preferred Term
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADCM (WHO Drug coded; PREFL / CONFL prior/concomitant flags)
# NOTE      : PSEUDOCODE. Counts = distinct PARTICIPANTS taking a medication
#             (n_distinct USUBJID), NOT medication rows. PER-PERIOD table ->
#             columns = Period 1 (Reference) | Period 2 (Test) | Total. BOTH a
#             Prior block (PREFL == "Y") and a Concomitant block (CONFL == "Y")
#             are shown. The period split exposes the perpetrator drug present
#             only in the test period (Period 2) -- the point of the DDI design.
#             ATC class sorted by overall freq desc; PT within class desc.
#             % denominator = per-PERIOD dosed N from ADEX (Total from ADSL).
#             NOTE: in a DDI study the perpetrator is study drug (ADEX), not a
#             con-med; ADCM = background/incidental medications only.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
options(tfl.study = env$study)
perC <- dv$byperiod[2]                           # character period label column

## per-PERIOD column denominators (N=) from ADEX + Total from ADSL (participant-level)
perdenom <- bind_rows(
  adam$adex %>% filter(SAFFL == "Y") %>%
    group_by(per = .data[[perC]]) %>%
    summarise(N = n_distinct(USUBJID), .groups = "drop"),
  adam$adsl %>% filter(SAFFL == "Y") %>%
    summarise(per = "Total", N = n_distinct(USUBJID)))

adcm <- adam$adcm %>% filter(SAFFL == "Y") %>%
  mutate(per = .data[[perC]])

## --- generic block builder for one medication-timing flag ------------------
## ATC text (CMCLAS) and PT (CMDECOD) from WHO Drug. flagvar = PREFL or CONFL
## (prior vs concomitant). Distinct-participant counts at every level, BY PERIOD,
## with a Total column across periods (a participant counted once per Total cell).
cm_block <- function(flagvar, block_label) {
  d <- adcm %>% filter(.data[[flagvar]] == "Y")
  ## stack per-period rows with a Total ("per" = "Total") view
  dd <- bind_rows(d, d %>% mutate(per = "Total"))

  ## any medication (distinct participants)
  any_cm <- dd %>% group_by(per) %>%
    summarise(n = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(CMCLAS = NA_character_, CMDECOD = NA_character_, level = 0L,
           term = paste0("Participants with any ", tolower(block_label)))

  ## by ATC class (distinct participants within class)
  cls <- dd %>% group_by(per, CMCLAS) %>%
    summarise(n = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(level = 1L, term = CMCLAS)

  ## by class*PT (distinct participants within class and PT)
  clspt <- dd %>% group_by(per, CMCLAS, CMDECOD) %>%
    summarise(n = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(level = 2L, term = paste0("   ", CMDECOD))   # indent PT under class

  ## ordering keys: class then PT by Total-period participant count desc
  cls_ord <- cls   %>% filter(per == "Total") %>% select(CMCLAS, clsn = n)
  pt_ord  <- clspt %>% filter(per == "Total") %>% select(CMCLAS, CMDECOD, ptn = n)

  bind_rows(any_cm, cls, clspt) %>%
    left_join(perdenom, by = "per") %>%
    mutate(value = n_pct(n, N), block = block_label) %>%
    left_join(cls_ord, by = "CMCLAS") %>%
    left_join(pt_ord,  by = c("CMCLAS","CMDECOD")) %>%
    arrange(desc(clsn), CMCLAS, level, desc(ptn))
}

rep <- bind_rows(
  cm_block("PREFL", "Prior"),
  cm_block("CONFL", "Concomitant")) %>%
  select(block, term, level, per, value) %>%
  pivot_wider(names_from = per, values_from = value)     # columns = PERIODs + Total

ttl <- tfl_titles(num = "14.1.6", type = "Table",
   text = "Prior and Concomitant Medications by Drug Class and Preferred Term",
   pop  = "Safety Population",
   foot = paste("A participant is counted once at each level per period.",
                "WHO Drug Dictionary; class = ATC level. Prior = PREFL (before",
                "first dose); concomitant = CONFL (ongoing during treatment).",
                "Period 1 = reference (victim alone); Period 2 = test (victim +",
                "perpetrator); the perpetrator appears in Period 2. Percentages",
                "within period N (ADEX); Total within Safety N."))

## rtables/gt rendering; block header, ATC class bold, PT indented
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("block", page_by = FALSE) %>%
  analyze("term", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, rep)   ## or gt::gt(rep)
print(rep)
