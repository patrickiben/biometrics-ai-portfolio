################################################################################
# LISTING   : l_pk_param  (Parallel-group)
# TITLE     : Listing of Individual Plasma PK Parameters
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (one row per participant x parameter: PARAMCD/AVAL)
# NOTE      : PSEUDOCODE. One row per participant, parameters in columns (Cmax, Tmax,
#             AUClast, AUCinf, t1/2, CL/F, Vz/F, %AUCextrap, ...). Ordered by
#             treatment then participant. Flags non-estimable / excluded parameters.
#             Column grouping = TRT01A = dose level. No derivation of numbers
#             here -- ADPP carries the validated (Phoenix) parameter values.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")

## --- parameters to list, in report order (label kept for header) -----------
pcd <- c("CMAX","TMAX","AUCLST","AUCIFO","AUCPEO","T12","CLFO","VZFO","LAMZ")

pp <- adam$adpp %>%
  filter(PKFL == "Y", PARAMCD %in% pcd) %>%
  mutate(disp = case_when(
            !is.na(AVAL)                              ~ sprintf("%.4g", AVAL),
            toupper(coalesce(DTYPE,"")) %in%
              c("NE","NC","EXCLUDED")                 ~ DTYPE,         # non-estimable / excluded flag
            TRUE                                      ~ "NC"))

## --- one row per participant; parameters across columns (report order) ---------
wide <- pp %>%
  transmute(Treatment = .data[[dv$trtvar]],            # = dose level
            Participant   = str_extract(USUBJID, "[^-]+$"),
            USUBJID,
            PARAMCD = factor(PARAMCD, levels = pcd),
            disp) %>%
  arrange(Treatment, USUBJID, PARAMCD) %>%
  pivot_wider(names_from = PARAMCD, values_from = disp) %>%
  arrange(Treatment, Participant) %>%
  select(-USUBJID)

ttl <- tfl_titles(num = "16.2.11.2", type = "Listing",
   text = "Listing of Individual Plasma Pharmacokinetic Parameters",
   pop  = "Pharmacokinetic Parameter Population",
   foot = paste("NC = not calculated; NE = non-estimable; values from validated software (Phoenix WinNonlin).",
                "Units per analysis dataset. Participants grouped by treatment (dose level).",
                "AUCinf shown only when %AUCextrap acceptable per SOP."))

## render: blocks by treatment (page break), columns = parameters above
## listings::create_listing(...) or gt::gt(wide)
print(wide)
