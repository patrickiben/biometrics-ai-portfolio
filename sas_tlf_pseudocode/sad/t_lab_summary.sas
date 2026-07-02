/******************************************************************************
* TABLE     : t_lab_summary  (Single Ascending Dose)
* TITLE     : Summary of Laboratory Values and Change from Baseline by Visit
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, AVAL, BASE, CHG, AVISIT/AVISITN, ANRIND)
* NOTE      : PSEUDOCODE. Descriptive statistics (n, Mean(SD), Median, Min-Max)
*             for observed value AND change from baseline (CHG), by parameter,
*             scheduled visit and dose level. SAD design: parallel ascending
*             cohorts, one single dose per participant -> treatment column =
*             TRT01A (the dose level). Placebo is typically POOLED across
*             cohorts into one "Placebo (pooled)" column. Single dose, no
*             accumulation: scheduled visits are post-single-dose follow-up.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN  */

/* column denominators (N=) per dose level + pooled placebo + Total           */
/* (placebo pooling is carried in ADSL TRT01A/TRT01AN; no re-derivation here)  */
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/* analysis records: Safety pop, scheduled post-dose/baseline visits, on-study */
data lb;
  set adam.adlb(where=(SAFFL='Y' and ANL01FL='Y' and not missing(AVISITN)));
  /* AVAL=observed, BASE=baseline, CHG=change from baseline (all from ADaM)    */
run;

/*--- observed value summary: n, Mean(SD), Median, Min-Max -----------------*/
/* class includes PARAMCD + scheduled visit + dose level; decimal hints       */
/* by parameter via a DP lookup (e.g. enzymes 1dp, electrolytes 1dp).         */
%descstat(ds=lb, var=AVAL, class=PARAMCD PARAM AVISITN AVISIT &TRTVAR &TRTNVAR,
          dp=1, out=_aval);
data _aval; set _aval; length stattype $8; stattype='AVAL'; run;

/*--- change-from-baseline summary (CHG): same structure -------------------*/
%descstat(ds=lb(where=(not missing(CHG))), var=CHG,
          class=PARAMCD PARAM AVISITN AVISIT &TRTVAR &TRTNVAR, dp=1, out=_chg);
data _chg; set _chg; length stattype $8; stattype='CHG'; run;

/*--- stack observed + change; build the statistic rows --------------------*/
data _stat;
  set _aval _chg;
  length stat $20 value $40;
  stat='n';         value=put(n,5.);              output;
  stat='Mean (SD)'; value=catx(' ',cmean,csd);    output;
  stat='Median';    value=cmed;                   output;
  stat='Min, Max';  value=cminmax;                output;
run;
/* stattype label: "Observed Value" vs "Change from Baseline" column block   */

proc sort data=_stat; by PARAMCD PARAM AVISITN AVISIT stattype stat; run;
proc transpose data=_stat out=_wide;
  by PARAMCD PARAM AVISITN AVISIT stattype stat;   /* one col per dose + Total */
  id &TRTNVAR; var value;
run;

%tfltitle(num=14.3.4.1, type=Table,
   text=%str(Summary of Laboratory Values and Change from Baseline by Visit),
   pop=Safety Population,
   foot=%str(Statistics are descriptive only. Columns = ascending dose levels (TRT01A) with pooled placebo. Change from Baseline = post-baseline value minus baseline (ADaM CHG). SI units. Single-dose study; scheduled post-dose visits only.));
proc report data=_wide nowd split='|';
  columns PARAM AVISITN AVISIT stattype stat ("Dose Level" /* dose cols + Total */);
  define PARAM    / order 'Laboratory|Parameter' width=24 flow;
  define AVISITN  / order noprint;
  define AVISIT   / order 'Visit'      width=14;
  define stattype / order 'Measure'    width=18;   /* Observed / Change       */
  define stat     / display 'Statistic' width=12;
  break after PARAM / skip;
run;
