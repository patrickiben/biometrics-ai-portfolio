################################################################################
# TABLE     : t_ae_sae_death_withdrawal  (Single-/fixed-sequence DDI)
# TITLE     : Serious Adverse Events, Deaths, and AEs Leading to Withdrawal
#             by System Organ Class and Preferred Term, by Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y"); ADEX for per-PERIOD dosed denominators
# NOTE      : PSEUDOCODE. Three stacked blocks (SAE / Death / Withdrawal), each
#             with a header participant-count row + SOC*PT detail (row label
#             "SOC: PT", same granularity/format as the SAS twin). Columns =
#             dv$byperiod (APERIODC): Period 1 reference (victim alone), Period 2
#             test (victim + perpetrator). Counts = distinct PARTICIPANTS, NOT
#             event rows. % denominator = participants DOSED per APERIOD (ADEX,
#             SAFFL) -- NOT ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # TRTA + APERIOD/APERIODC

period_col <- dv$byperiod[2]                    # "APERIODC"

## --- per-PERIOD denominator (period-bearing source: ADEX) ---------------------
denom <- adam$adex %>%
  filter(SAFFL == "Y") %>%
  group_by(per = .data[[period_col]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")

adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")

## --- one block: a header participant-count row + SOC*PT detail for a filter ------
## SOC*PT detail with row label "SOC: PT" (same granularity/format as SAS twin).
ae_block <- function(block_label, where) {
  d <- adae %>% filter(!!where)
  ## header: distinct participants per period meeting the condition
  hdr <- d %>% group_by(per = .data[[period_col]]) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(level = 0L, term = paste("Participants with any", block_label),
           block = block_label)
  ## SOC*PT detail: distinct participants per period x SOC x PT
  pt <- d %>% group_by(per = .data[[period_col]], AESOC, AEDECOD) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(level = 2L, term = paste0("   ", AESOC, ": ", AEDECOD), block = block_label)
  pt_ord <- pt %>% group_by(AESOC, AEDECOD) %>% summarise(ptn = sum(nsubj), .groups = "drop")
  bind_rows(hdr, pt %>% left_join(pt_ord, by = c("AESOC","AEDECOD")) %>% arrange(desc(ptn)))
}

blocks <- bind_rows(
  ae_block("serious TEAE (SAE)", quote(AESER == "Y")),
  ae_block("TEAE leading to death", quote(AESDTH == "Y")),
  ae_block("TEAE leading to withdrawal",
           quote(str_detect(toupper(AEACN), "DRUG WITHDRAWN")))
)

block_levels <- c("serious TEAE (SAE)",
                  "TEAE leading to death",
                  "TEAE leading to withdrawal")

rep <- blocks %>%
  left_join(denom, by = "per") %>%
  mutate(value = n_pct(nsubj, N),
         block = factor(block, levels = block_levels)) %>%
  arrange(block, level) %>%                       # keep within-block PT order from ae_block()
  select(block, term, level, per, value) %>%
  pivot_wider(names_from = per, values_from = value)

ttl <- tfl_titles(num = "14.3.1.5", type = "Table",
   text = "Serious Adverse Events, Deaths, and AEs Leading to Withdrawal by System Organ Class and Preferred Term, by Period",
   pop  = "Safety Population",
   foot = paste("DDI: Period 1 = victim alone (reference); Period 2 = victim + perpetrator (test).",
                "Participant counted once per block per period; SOC*PT detail counts participants once per SOC/PT. SAE per AESER; death per AESDTH; withdrawal per AEACN.",
                "% = participants / participants dosed in that period (ADEX). MedDRA v27.0."))

## rtables / gt: three stacked blocks (SAE, Death, Withdrawal), PT indented
print(rep)
