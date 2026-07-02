################################################################################
# TABLE     : t_prior_con_meds  (Crossover - 2x2 / Williams)
# TITLE     : Prior and Concomitant Medications by Drug Class
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADCM  (one row per medication record; WHO-DD ATC class + decode)
# NOTE      : PSEUDOCODE. Counts = PARTICIPANTS taking >=1 medication (n_distinct
#             USUBJID), NOT medication rows. Summary columns = treatment SEQUENCE
#             (dv$seqvar = TRTSEQP) + Total; % denom = SAFFL N per sequence from
#             bign(). Prior = ended before first dose (PREFL=="Y"); Concomitant =
#             ongoing/started after first dose (CMONGFL/ONTRTFL=="Y"). In a
#             crossover a "concomitant" med may overlap a SPECIFIC period; the
#             coarse summary keys on sequence, with a by-PERIOD companion using
#             dv$byperiod and per-period denominators from ADEX.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")   # seqvar = TRTSEQP (participant-level), byperiod = APERIOD/APERIODC

## SAFFL N per SEQUENCE + Total
denom <- bign(adam$adsl, trtvar = dv$seqvar, popfl = "SAFFL")

## ADCM with the participant's randomized sequence label attached
cm <- adam$adcm %>% filter(SAFFL == "Y") %>%
  left_join(adam$adsl %>% select(USUBJID, !!dv$seqvar), by = "USUBJID")

## generic participant-count builder for a med subset, by ATC class -> ingredient --
cm_block <- function(df, status_label, base_ord) {
  any_row <- df %>% group_by(trt = .data[[dv$seqvar]]) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    bind_rows(tibble(trt = "Total", nsubj = n_distinct(df$USUBJID))) %>%
    mutate(term = paste("Participants with any", status_label, "medication"), level = 0L,
           ATC = NA_character_)
  byclass <- df %>% group_by(trt = .data[[dv$seqvar]], ATC = CMCLAS) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    bind_rows(df %>% group_by(ATC = CMCLAS) %>%
                summarise(trt = "Total", nsubj = n_distinct(USUBJID), .groups = "drop")) %>%
    mutate(term = ATC, level = 1L)
  bypt <- df %>% group_by(trt = .data[[dv$seqvar]], ATC = CMCLAS, CMDECOD) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    bind_rows(df %>% group_by(ATC = CMCLAS, CMDECOD) %>%
                summarise(trt = "Total", nsubj = n_distinct(USUBJID), .groups = "drop")) %>%
    mutate(term = paste0("   ", CMDECOD), level = 2L)
  ## class ordering by overall participant count desc
  cls_ord <- byclass %>% filter(trt == "Total") %>% select(ATC, ord_n = nsubj)
  bind_rows(any_row, byclass, bypt) %>%
    left_join(denom, by = "trt") %>%
    mutate(value = n_pct(nsubj, N), block = status_label, base_ord = base_ord) %>%
    left_join(cls_ord, by = "ATC") %>%
    arrange(base_ord, level, desc(ord_n), ATC)
}

prior <- cm_block(cm %>% filter(PREFL   == "Y"), "prior",        1)
conmed<- cm_block(cm %>% filter(ONTRTFL == "Y"), "concomitant",  2)

tab <- bind_rows(prior, conmed) %>%
  select(block, term, level, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)

## --- by-PERIOD concomitant companion (period-bearing denominators) ----------
per_denom <- adam$adex %>% filter(SAFFL == "Y") %>%
  group_by(per = .data[[dv$byperiod[2]]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")
conmed_by_period <- cm %>% filter(ONTRTFL == "Y", !is.na(.data[[dv$byperiod[2]]])) %>%
  group_by(per = .data[[dv$byperiod[2]]]) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
  left_join(per_denom, by = "per") %>%
  transmute(Period = per, `Participants on concomitant meds` = n_pct(nsubj, N))

ttl <- tfl_titles(num = "14.1.6", type = "Table",
   text = "Prior and Concomitant Medications by Drug Class",
   pop  = "Safety Population",
   foot = "A participant is counted once per class/term. Participant-level columns = randomized sequence (TRTSEQP). WHO-DD coding. Per-period denominators = participants dosed per period (ADEX).")

print(tab)
print(conmed_by_period)   # companion by-period concomitant counts (dv$byperiod)
