/******************************************************************************
* TABLE     : t_lab_summary  (Crossover - 2x2 or Williams)
* TITLE     : Summary of Laboratory Values and Change from Baseline by Visit
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, AVAL, BASE, CHG, AVISIT/AVISITN, ANRIND,
*             TRTA/TRTAN, APERIOD/APERIODC, TRTSEQP)
* NOTE      : PSEUDOCODE. Descriptive statistics (n, Mean(SD), Median, Min-Max)
*             for observed value AND change from baseline (CHG), by parameter
*             and scheduled visit. Within-participant crossover -> columns =
*             analysis treatment TRTA; each participant contributes to every
*             treatment received. CHG = change from the WITHIN-PERIOD baseline
*             (ADLB CHG). APERIODC retained for an optional by-period breakout.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTVAR=TRTA TRTNVAR=TRTAN BYPERIOD=APERIOD APERIODC SEQVAR=TRTSEQP */

/* column denominators (N=) per treatment + Total (Safety Population) */
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/* analysis records: Safety pop, scheduled baseline/post-dose visits, on-study */
data lb;
  set adam.adlb(where=(SAFFL='Y' and ANL01FL='Y' and not missing(AVISITN)));
  /* AVAL=observed, BASE=within-period baseline, CHG=change (all from ADaM)     */
  /* Treatment/period/sequence taken straight from ADaM - no re-derivation      */
run;

/*--- observed value summary: n, Mean(SD), Median, Min-Max -----------------*
* Crossover key change: CLASS carries &TRTVAR (=TRTA) so each treatment a    *
* participant received forms its own column. Add APERIODC to CLASS for a SAP-    *
* requested by-period breakout. Decimal hints by parameter via a DP lookup.  */
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
  if missing(AVISITN) then delete;   /* drop PROC MEANS _TYPE_ marginals     */
  length stat $20 value $40;
  stat='n';         value=put(n,5.);              output;
  stat='Mean (SD)'; value=catx(' ',cmean,csd);    output;
  stat='Median';    value=cmed;                   output;
  stat='Min, Max';  value=cminmax;                output;
run;
/* stattype label: "Observed Value" vs "Change from Baseline" measure block  */

proc sort data=_stat; by PARAMCD PARAM AVISITN AVISIT stattype stat; run;
proc transpose data=_stat out=_wide;
  by PARAMCD PARAM AVISITN AVISIT stattype stat;   /* one col per trt + Total */
  id &TRTNVAR; var value;
run;

%tfltitle(num=14.3.4.1, type=Table,
   text=%str(Summary of Laboratory Values and Change from Baseline by Visit),
   pop=Safety Population,
   foot=%str(Statistics are descriptive only. Change from Baseline = post-baseline value minus within-period baseline (ADaM CHG). Participants contribute to each treatment received (crossover). SI units. Scheduled visits only.));
proc report data=_wide nowd split='|';
  columns PARAM AVISITN AVISIT stattype stat ("Treatment" /* trt cols + Total */);
  define PARAM    / order 'Laboratory|Parameter' width=24 flow;
  define AVISITN  / order noprint;
  define AVISIT   / order 'Visit'      width=14;
  define stattype / order 'Measure'    width=18;   /* Observed / Change       */
  define stat     / display 'Statistic' width=12;
  /* define <each treatment var> / display center "&header (N=&n)";           */
  break after PARAM / skip;
run;
