################################################################################
# LISTING   : l_pk_param  (MAD - Multiple Ascending Dose)
# TITLE     : Listing of Individual Plasma PK Parameters
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (one row per participant x dosing day x parameter: PARAMCD/AVAL)
# NOTE      : PSEUDOCODE. One row per participant x dosing DAY, parameters in columns.
#             Ordered by dose cohort, participant, then dosing day. Flags non-estimable
#             / excluded parameters. MAD = parallel cohorts, REPEATED dosing:
#             Day 1 carries single-dose parameters (Cmax, AUClast, AUCinf, t1/2);
#             Day N carries STEADY-STATE parameters (AUCtau, Cmax,ss, Cmin,ss,
#             Ctrough, CL/F,ss, PTF) plus the accumulation ratios (Rac). Column
#             grouping = TRT01A = dose level. No derivation here -- ADPP carries
#             the validated (Phoenix) values.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")

## --- parameters to list, in report order (label kept for header) -----------
## single-dose (Day 1) + steady-state (Day N) + accumulation ratios.
## Oral CL/F and Vz/F use CLFO/VZFO consistently (ADPP emits these); steady-state
## clearance = CLSS. Accumulation ratios = RACMAX/RACAUC (as in t_accumulation).
pcd <- c("CMAX","TMAX","AUCLST","AUCIFO","T12","CLFO","VZFO",
         "CMAXSS","TMAXSS","AUCTAU","CMINSS","CTROUGH","CAVGSS","CLSS",
         "RACMAX","RACAUC")

pp <- adam$adpp %>%
  filter(PKFL == "Y", PARAMCD %in% pcd) %>%
  mutate(disp = case_when(
            !is.na(AVAL)                              ~ sprintf("%.4g", AVAL),
            toupper(coalesce(DTYPE,"")) %in%
              c("NE","NC","EXCLUDED")                 ~ DTYPE,         # non-estimable / excluded flag
            TRUE                                      ~ "NC"))

## --- one row per participant x dosing day; parameters across columns -----------
## dose cohorts ordered low -> high via TRT01AN
ord <- pp %>% distinct(trt = .data[[dv$trtvar]], trtn = .data[[dv$trtnvar]]) %>%
  arrange(trtn) %>% pull(trt)

wide <- pp %>%
  transmute(`Dose Cohort` = factor(.data[[dv$trtvar]], levels = ord),  # = dose level
            Participant     = str_extract(USUBJID, "[^-]+$"),
            USUBJID,
            `Dosing Day`= AVISIT,                                      # Day 1 / Day N
            ADY,
            PARAMCD = factor(PARAMCD, levels = pcd),
            disp) %>%
  arrange(`Dose Cohort`, USUBJID, ADY, PARAMCD) %>%
  pivot_wider(names_from = PARAMCD, values_from = disp) %>%
  arrange(`Dose Cohort`, Participant, ADY) %>%
  select(-USUBJID, -ADY)

ttl <- tfl_titles(num = "16.2.11.2", type = "Listing",
   text = "Listing of Individual Plasma Pharmacokinetic Parameters",
   pop  = "Pharmacokinetic Parameter Population",
   foot = paste("NC = not calculated; NE = non-estimable; values from validated software (Phoenix WinNonlin).",
                "Units per analysis dataset. Participants grouped by dose cohort (TRT01A).",
                "MAD: Day 1 = single-dose parameters; Day N = steady-state parameters",
                "(AUCtau, Cmax,ss, Cmin,ss, Ctrough, CL/F,ss, PTF) + accumulation ratios (Rac).",
                "AUCinf shown only when %AUCextrap acceptable per SOP."))

## render: blocks by dose cohort -> participant (page break), rows = dosing day,
##         columns = parameters above. listings::create_listing(...) or gt::gt(wide)
print(wide)
