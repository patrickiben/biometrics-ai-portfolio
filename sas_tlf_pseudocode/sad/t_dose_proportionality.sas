/******************************************************************************
* TABLE     : t_dose_proportionality  (SAD - Single Ascending Dose)
* TITLE     : Assessment of Dose Proportionality of PK Exposure
*             (Power Model: Slope Estimate and 90% Confidence Interval)
* POPULATION: PK Parameter Population (PKFL='Y')
* INPUT     : ADPP (PARAMCD = CMAX, AUCLST, AUCIFO); dose from ADEX/ADSL
* NOTE      : PSEUDOCODE. THIS is the file that differs by design for SAD.
*             Across the ascending dose cohorts (parallel groups), assess
*             whether single-dose exposure rises proportionally with dose using
*             the POWER MODEL on the log scale:
*                 ln(parameter) = a + beta * ln(dose)
*             Fit by linear regression (slope beta). Report the beta estimate
*             with its 90% CI per parameter. Dose proportionality is supported
*             when the 90% CI for beta lies within the pre-specified critical
*             region (commonly [1 + ln(theta_L)/ln(r), 1 + ln(theta_H)/ln(r)]
*             with theta = 0.80/1.25 and r = highest/lowest dose ratio); a
*             reference point of beta = 1 = exact proportionality.
*             Active doses only (placebo excluded). Single dose => no
*             accumulation; exposures are single-dose NCA parameters.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                       /* TRT01A = dose level         */

/*--- one record per participant x parameter, with the administered dose ------
   Dose carried in ADPP (e.g. EXDOSE-derived) or merged from ADEX/ADSL.
   Placebo (dose=0) excluded - ln(dose) undefined and not on the dose axis.  */
data pp;
  merge adam.adpp(in=a where=(PKFL='Y'
                              and PARAMCD in ('CMAX','AUCLST','AUCIFO')
                              and AVAL>0))
        adam.adsl(keep=USUBJID &TRTVAR &TRTNVAR);
  by USUBJID;
  if a;
  dose = &TRTNVAR;                 /* numeric planned dose (mg) = dose level   */
  if dose>0;                       /* active doses only                        */
  lnval  = log(AVAL);             /* ln(exposure parameter)                    */
  lndose = log(dose);             /* ln(dose)                                  */
run;

/*--- highest/lowest dose ratio r -> critical region for beta -------------*/
proc sql noprint;
  select max(dose)/min(dose) into :rdose trimmed from pp where dose>0;
quit;
/* critical region (theta=0.80/1.25): betaL=1+log(0.80)/log(&rdose);
                                      betaH=1+log(1.25)/log(&rdose)          */

/*--- power model per parameter: ln(param) = a + beta*ln(dose) ------------*
* This is a FIXED-EFFECTS-ONLY model (no RANDOM/REPEATED statement), so PROC
* MIXED here is algebraically identical to ordinary least squares (PROC REG/GLM)
* -- the R twin fits the same model via lm(). REML vs OLS makes no difference
* with no random effects; reviewers should NOT expect a mixed-model result.   */
%macro dprop(param=);
  proc mixed data=pp(where=(PARAMCD="&param")) method=reml;
    model lnval = lndose / solution cl alpha=0.10 ddfm=kr;
    /* slope (lndose) = beta = power-model exponent; 90% CI from SOLUTION    */
    ods output SolutionF=_sol_&param;
  run;
  data _dp_&param; set _sol_&param;
    where Effect='lndose';                       /* the slope row            */
    length param $20 beta ci $24 concl $24;
    param = "&param";
    beta  = put(Estimate, 6.3);                  /* beta estimate            */
    ci    = catx(' - ', put(Lower,6.3), put(Upper,6.3));   /* 90% CI         */
    /* proportional if 90% CI within [betaL, betaH] critical region;
       informally, contains 1.0 -> consistent with proportionality          */
    betaL = 1 + log(0.80)/log(&rdose);
    betaH = 1 + log(1.25)/log(&rdose);
    concl = ifc(Lower>=betaL and Upper<=betaH,
                'Proportional','Not concluded');
  run;
%mend;
%dprop(param=CMAX);  %dprop(param=AUCLST);  %dprop(param=AUCIFO);

data _dp; set _dp_:; run;

%tfltitle(num=14.4.4.1, type=Table,
   text=%str(Assessment of Dose Proportionality of Pharmacokinetic Exposure (Power Model)),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(Power model: ln(parameter) = a + beta*ln(dose), active doses only, single dose. beta = slope (exponent); 90% CI back-transformed from the model. Dose proportionality supported when the 90% CI for beta lies within the pre-specified critical region (theta = 0.80-1.25 over the studied dose range); beta = 1 = exact proportionality.));
proc report data=_dp nowd split='|';
  columns param beta ('90% CI for beta' ci) ('Critical|region' betaL betaH) concl;
  define param / display 'PK Parameter' width=20;
  define beta  / display 'Slope (beta)' center width=12;
  define ci    / display center width=18;
  define betaL / display 'Lower' center width=8 format=6.3;
  define betaH / display 'Upper' center width=8 format=6.3;
  define concl / display 'Conclusion' center width=14;
run;
