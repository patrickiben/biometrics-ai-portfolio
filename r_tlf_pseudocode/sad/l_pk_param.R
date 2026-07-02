################################################################################
# LISTING   : l_pk_param  (SAD - Single Ascending Dose)
# TITLE     : Listing of Individual Plasma PK Parameters
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (PARAMCD = CMAX, TMAX, AUCLST, AUCIFO, AUCPEO, T12, CLFO,
#             VZFO, LAMZ) -- oral CL/F (CLFO) and Vz/F (VZFO)
# NOTE      : PSEUDOCODE. One row per participant (parameters across columns),
#             ordered by dose level then participant. SAD: one (single) dose per
#             participant; column var = TRT01A (= dose level). Single-dose NCA
#             parameters only (no Rac). Non-estimable parameters (BLQ-driven)
#             shown as NE/blank per AVALC. Listings present individual derived
#             NCA parameters as computed in ADPP.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")

## --- parameters to list, in report order (label kept for header) -----------
pcd <- c("CMAX","TMAX","AUCLST","AUCIFO","AUCPEO","T12","CLFO","VZFO","LAMZ")

pp <- adam$adpp %>%
  filter(PKFL == "Y", PARAMCD %in% pcd) %>%
  mutate(disp = case_when(
            !is.na(AVAL)                              ~ sprintf("%.4g", AVAL),
            toupper(coalesce(AVALC,"")) == "NE"       ~ "NE",          # non-estimable carried via AVALC
            TRUE                                      ~ AVALC))        # other non-numeric AVALC text

## --- one row per participant; parameters across columns (report order) ---------
## dose cohorts ordered low -> high via TRT01AN
ord <- pp %>% distinct(trt = .data[[dv$trtvar]], trtn = .data[[dv$trtnvar]]) %>%
  arrange(trtn) %>% pull(trt)

wide <- pp %>%
  transmute(`Dose Level`  = factor(.data[[dv$trtvar]], levels = ord),  # = dose level
            Participant   = str_extract(USUBJID, "[^-]+$"),
            USUBJID,
            PARAMCD = factor(PARAMCD, levels = pcd),
            disp) %>%
  arrange(`Dose Level`, USUBJID, PARAMCD) %>%
  pivot_wider(names_from = PARAMCD, values_from = disp) %>%
  arrange(`Dose Level`, Participant) %>%
  select(-USUBJID)

ttl <- tfl_titles(num = "16.2.11.2", type = "Listing",
   text = "Listing of Individual Plasma Pharmacokinetic Parameters",
   pop  = "Pharmacokinetic Parameter Population",
   foot = paste("NE = not estimable. Single-dose parameters as derived by non-compartmental analysis in ADPP.",
                "Tmax in hours; exposure in concentration*time units; CL/Vz in volume(/time) units."))

## render: blocks by dose cohort (page break), columns = parameters above
## listings::create_listing(...) or gt::gt(wide)
print(wide)
