/******************************************************************************
* TABLE     : t_pd_summary  (Parallel-group / per-dose)
* TITLE     : Summary of Pharmacodynamic Biomarker Results and Change from
*             Baseline by Treatment and Visit
* POPULATION: PD / Pharmacodynamic Analysis Population (PDFL='Y')
* INPUT     : ADPD (PARAM/PARAMCD = PD biomarkers; AVAL, BASE, CHG, PCHG;
*             AVISIT/AVISITN, ATPT/ATPTN as applicable)
* NOTE      : PSEUDOCODE. Parallel-group: one treatment per participant; column
*             variable = TRT01A/TRT01AN (= dose level). PD compared
*             DESCRIPTIVELY by treatment (no within-participant/period contrast).
*             Report n, Mean (SD), Median, Min, Max for AVAL, CHG and PCHG
*             at each post-baseline visit/timepoint.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);                 /* column = TRT01A (= dose)     */

/*--- header denominators: N per dose column (PD population) --------------*/
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=PDFL, out=_bign);

data pd;
  set adam.adpd(where=(PDFL='Y'));
  /* PARAM/PARAMCD order + decimal hints via study format catalog;
     keep baseline + post-baseline analysis visits/timepoints from ADaM     */
run;

/*--- descriptive stats: AVAL, CHG, PCHG by dose x parameter x visit ------
* Reuse %descstat for each measure; class drives the row/column structure   */
%descstat(ds=pd, var=AVAL,  class=&TRTVAR &TRTNVAR PARAM PARAMCD AVISIT AVISITN,
          where=%str(not missing(AVAL)),  dp=2, out=_aval);
%descstat(ds=pd, var=CHG,   class=&TRTVAR &TRTNVAR PARAM PARAMCD AVISIT AVISITN,
          where=%str(not missing(CHG) and AVISITN>0), dp=2, out=_chg);
%descstat(ds=pd, var=PCHG,  class=&TRTVAR &TRTNVAR PARAM PARAMCD AVISIT AVISITN,
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

/*--- transpose dose to columns; rows = param x visit x measure x stat ----*/
proc sort data=_stat; by PARAM PARAMCD AVISITN AVISIT measure stat &TRTNVAR; run;
proc transpose data=_stat out=_wide; by PARAM PARAMCD AVISITN AVISIT measure stat;
  id &TRTNVAR; var value;
run;

%tfltitle(num=14.4.6.1, type=Table,
   text=%str(Summary of Pharmacodynamic Biomarker Results and Change from Baseline by Treatment and Visit),
   pop=Pharmacodynamic Analysis Population,
   foot=%str(Descriptive summary by treatment (dose). Parallel-group: PD compared descriptively across treatments. Change and % change relative to baseline (BASE). N (per dose) from header.));
proc report data=_wide nowd split='|';
  columns PARAM PARAMCD AVISIT AVISITN measure stat ("Treatment (Dose)" /* dose cols */);
  define PARAM   / order 'PD Parameter (units)' width=26 flow;
  define PARAMCD / order noprint;
  define AVISITN / order noprint;
  define AVISIT  / order 'Visit' width=14;
  define measure / order 'Measure' width=18;
  define stat    / display 'Statistic' width=12;
  break after PARAM / skip;
run;
