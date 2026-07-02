/******************************************************************************
* TABLE     : t_pd_summary  (SAD - Single Ascending Dose)
* TITLE     : Summary of Pharmacodynamic Biomarker Results and Change from
*             Baseline by Dose Level and Time
* POPULATION: PD / Pharmacodynamic Analysis Population (PDFL='Y')
* INPUT     : ADPD (PARAM/PARAMCD = PD biomarkers; AVAL, BASE, CHG, PCHG;
*             AVISIT/AVISITN, ATPT/ATPTN as applicable)
* NOTE      : PSEUDOCODE. SAD: parallel ascending cohorts, one (single) dose
*             per participant; column variable = TRT01A/TRT01AN (= dose level,
*             placebo typically pooled). Single dose => one dosing event, no
*             accumulation / no steady state; post-dose timepoints are relative
*             to the single administered dose. PD compared DESCRIPTIVELY across
*             dose levels to read the dose-related PD response (no within-
*             participant/period contrast). Report n, Mean (SD), Median, Min, Max
*             for AVAL, CHG and PCHG at each post-baseline visit/timepoint.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                       /* column = TRT01A (= dose)     */

/*--- header denominators: N per dose column (PD population) --------------*/
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=PDFL, out=_bign);

data pd;
  set adam.adpd(where=(PDFL='Y'));
  /* PARAM/PARAMCD order + decimal hints via study format catalog;
     keep baseline + post-baseline analysis visits/timepoints from ADaM     */
  reltm = coalesce(ATPTN, AVISITN);            /* nominal time after dose      */
run;

/*--- descriptive stats: AVAL, CHG, PCHG by dose x parameter x time -------
* Reuse %descstat for each measure; class drives the row/column structure   */
%descstat(ds=pd, var=AVAL,  class=&TRTVAR &TRTNVAR PARAM PARAMCD AVISIT AVISITN ATPT ATPTN,
          where=%str(not missing(AVAL)),  dp=2, out=_aval);
%descstat(ds=pd, var=CHG,   class=&TRTVAR &TRTNVAR PARAM PARAMCD AVISIT AVISITN ATPT ATPTN,
          where=%str(not missing(CHG) and AVISITN>0), dp=2, out=_chg);
%descstat(ds=pd, var=PCHG,  class=&TRTVAR &TRTNVAR PARAM PARAMCD AVISIT AVISITN ATPT ATPTN,
          where=%str(not missing(PCHG) and AVISITN>0), dp=1, out=_pchg);

/*--- stack the three measures into one statistic column ------------------*/
data _stat; length measure $24 stat $20 value $30;
  set _aval (in=a) _chg (in=c) _pchg (in=p);
  if a then measure='Observed value';
  else if c then measure='Change from baseline';
  else if p then measure='% Change from baseline';
  /* emit display rows per measure: n / Mean (SD) / Median / Min, Max:
     'n'                = put(n,3.)
     'Mean (SD)'        = catx(' ', cmean, csd)
     'Median'           = cmed
     'Min, Max'         = cminmax                                            */
run;

/*--- transpose dose to columns; rows = param x time x measure x stat -----*/
proc sort data=_stat; by PARAM PARAMCD AVISITN AVISIT ATPTN measure stat &TRTNVAR; run;
proc transpose data=_stat out=_wide; by PARAM PARAMCD AVISITN AVISIT ATPTN measure stat;
  id &TRTNVAR; var value;
run;

%tfltitle(num=14.4.6.1, type=Table,
   text=%str(Summary of Pharmacodynamic Biomarker Results and Change from Baseline by Dose Level and Time),
   pop=Pharmacodynamic Analysis Population,
   foot=%str(Descriptive summary by dose level. SAD: single dose, one cohort per dose (placebo pooled); PD compared descriptively across ascending doses. Change and % change relative to baseline (BASE). N (per dose) from header.));
proc report data=_wide nowd split='|';
  columns PARAM PARAMCD AVISIT AVISITN ATPTN measure stat ("Dose Level" /* dose cols */);
  define PARAM   / order 'PD Parameter (units)' width=26 flow;
  define PARAMCD / order noprint;
  define AVISITN / order noprint;
  define ATPTN   / order noprint;
  define AVISIT  / order 'Visit / Time' width=14;
  define measure / order 'Measure' width=18;
  define stat    / display 'Statistic' width=12;
  break after PARAM / skip;
run;
