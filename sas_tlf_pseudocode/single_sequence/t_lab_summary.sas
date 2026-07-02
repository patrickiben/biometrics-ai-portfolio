/******************************************************************************
* TABLE     : t_lab_summary  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Summary of Laboratory Values and Change from Baseline by Period
*             and Visit
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, AVAL, BASE, CHG, AVISIT/AVISITN, ANRIND,
*             TRTA/TRTAN, APERIOD/APERIODC)
* NOTE      : PSEUDOCODE. Descriptive statistics (n, Mean(SD), Median, Min-Max)
*             for observed value AND change from baseline (CHG), by parameter
*             and scheduled visit. Single-/fixed-sequence design: the regimen
*             differs across periods (reference = victim alone; test = victim +
*             perpetrator), so columns = PERIOD (APERIOD/APERIODC): Period 1
*             (Reference) | Period 2 (Test) | Total. There is NO randomized
*             sequence; every participant follows the same fixed order. CHG = change
*             from the WITHIN-PERIOD baseline (ADLB CHG). Each participant contributes
*             to every period observed.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA TRTNVAR=TRTAN BYPERIOD=APERIOD APERIODC SEQVAR=(none) */

/* analysis records: Safety pop, scheduled baseline/post-dose visits, on-study */
data lb;
  set adam.adlb(where=(SAFFL='Y' and ANL01FL='Y'
                       and not missing(AVISITN) and not missing(APERIOD)));
  /* AVAL=observed, BASE=within-period baseline, CHG=change (all from ADaM)     */
  /* Period taken straight from ADaM - no re-derivation; single fixed sequence  */
run;

/*--- observed value summary: n, Mean(SD), Median, Min-Max -----------------*
* Single-sequence key change: CLASS carries the PERIOD (&BYPERIOD = APERIOD    *
* APERIODC) instead of a randomized treatment column, so each period forms its *
* own column. Decimal hints by parameter via a DP lookup.                      */
%descstat(ds=lb, var=AVAL, class=PARAMCD PARAM AVISITN AVISIT &BYPERIOD,
          dp=1, out=_aval);
data _aval; set _aval; length stattype $8; stattype='AVAL'; run;

/*--- change-from-baseline summary (CHG): same structure -------------------*/
%descstat(ds=lb(where=(not missing(CHG))), var=CHG,
          class=PARAMCD PARAM AVISITN AVISIT &BYPERIOD, dp=1, out=_chg);
data _chg; set _chg; length stattype $8; stattype='CHG'; run;

/*--- stack observed + change; build the statistic rows --------------------*/
data _stat;
  set _aval _chg;
  if missing(AVISITN) or missing(APERIOD) then delete;  /* drop MEANS marginals */
  length stat $20 value $40;
  stat='n';         value=put(n,5.);              output;
  stat='Mean (SD)'; value=catx(' ',cmean,csd);    output;
  stat='Median';    value=cmed;                   output;
  stat='Min, Max';  value=cminmax;                output;
run;
/* stattype label: "Observed Value" vs "Change from Baseline" measure block  */

proc sort data=_stat; by PARAMCD PARAM AVISITN AVISIT stattype stat APERIOD; run;
proc transpose data=_stat out=_wide;
  by PARAMCD PARAM AVISITN AVISIT stattype stat;   /* one col per period      */
  id APERIOD; var value;             /* Period 1 (Ref) | Period 2 (Test)      */
run;

%tfltitle(num=14.3.4.1, type=Table,
   text=%str(Summary of Laboratory Values and Change from Baseline by Period and Visit),
   pop=Safety Population,
   foot=%str(Statistics are descriptive only. Columns = study period: Period 1 = reference (victim alone), Period 2 = test (victim + perpetrator). Change from Baseline = post-baseline value minus within-period baseline (ADaM CHG). SI units. Scheduled visits only.));
proc report data=_wide nowd split='|';
  columns PARAM AVISITN AVISIT stattype stat ("Study Period" /* Period1 | Period2 | Total */);
  define PARAM    / order 'Laboratory|Parameter' width=24 flow;
  define AVISITN  / order noprint;
  define AVISIT   / order 'Visit'      width=14;
  define stattype / order 'Measure'    width=18;   /* Observed / Change       */
  define stat     / display 'Statistic' width=12;
  /* define <each period var> / display center "&header (N=&n)";              */
  break after PARAM / skip;
run;
