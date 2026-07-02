################################################################################
# LISTING   : l_lab_abnormal  (Parallel-group)
# TITLE     : Listing of Abnormal Post-Baseline Laboratory Values
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, AVAL, A1LO, A1HI, ANRIND, BASE, BNRIND,
#             AVISIT, ADY, ONTRTFL)
# NOTE      : PSEUDOCODE. One row per ABNORMAL post-baseline result (ANRIND in
#             LOW/HIGH), ordered by participant, parameter, study day. Shows value
#             vs reference range, baseline value/category, and a marked flag.
#             Limit-comparison-derived flags GUARDED with !is.na(A1HI/A1LO).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")

mark_hi <- 1.5    # AVAL > mark_hi * A1HI -> markedly High
mark_lo <- 0.5    # AVAL < mark_lo * A1LO -> markedly Low

lab <- adam$adlb %>%
  filter(SAFFL == "Y", ONTRTFL == "Y",
         toupper(ANRIND) %in% c("LOW","HIGH")) %>%       # abnormal post-baseline only
  mutate(
    mhi  = !is.na(A1HI) & !is.na(AVAL) & AVAL > mark_hi * A1HI,   # guarded
    mlo  = !is.na(A1LO) & !is.na(AVAL) & AVAL < mark_lo * A1LO,   # guarded
    Mark = case_when(mhi | mlo ~ "Y", TRUE ~ "")) %>%
  transmute(
    Treatment   = .data[[dv$trtvar]],
    Participant     = str_extract(USUBJID, "[^-]+$"),
    Parameter   = PARAM,
    Visit       = AVISIT,
    `Study Day` = ADY,                                   # numeric sort key
    Result      = sprintf("%.3g", AVAL),
    `Ref Range` = sprintf("%.3g - %.3g", A1LO, A1HI),
    Flag        = toupper(ANRIND),                       # LOW / HIGH
    Baseline    = sprintf("%.3g", BASE),
    `Base Cat`  = toupper(BNRIND),
    Marked      = Mark,
    ADY) %>%
  arrange(Treatment, Participant, Parameter, ADY)            # sort on numeric day, not text

ttl <- tfl_titles(num = "16.2.9.1", type = "Listing",
   text = "Listing of Abnormal Post-Baseline Laboratory Values",
   pop  = "Safety Population",
   foot = paste0("Abnormal = ANRIND Low/High vs analysis reference range. ",
                 "Marked = AVAL > ", mark_hi, " x ULN or < ", mark_lo,
                 " x LLN (only where the limit is non-missing). On-treatment results."))

## render: one block per treatment (page break); columns as ordered above
## listings::create_listing(lab, ...) or gt::gt(lab %>% select(-ADY))
print(lab %>% select(-ADY))
