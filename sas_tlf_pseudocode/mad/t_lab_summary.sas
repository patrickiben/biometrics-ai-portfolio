/******************************************************************************
* TABLE     : t_lab_summary  (MAD - Multiple Ascending Dose)
* TITLE     : Summary of Laboratory Values and Change from Baseline by Visit
*             and Dose Level
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, AVAL, BASE, CHG, AVISIT/AVISITN, ANRIND,
*             TRT01A/TRT01AN)
* NOTE      : PSEUDOCODE. Descriptive statistics (n, Mean(SD), Median, Min-Max)
*             for observed value AND change from baseline (CHG), by parameter
*             and scheduled visit. MAD: parallel cohorts, one (dose) treatment
*             per participant -> columns = TRT01A/TRT01AN (= dose level; placebo
*             typically pooled). Repeated dosing -> AVISIT spans multiple on-
*             treatment dosing days (e.g. Day 1, Day 7, Day 14 ...), so the by-
*             visit rows let reviewers track lab values ACROSS the multiple-dose
*             period and detect any time-dependent (cumulative) shift. BASE =
*             Day 1 pre-first-dose baseline; CHG from ADaM (no re-derivation).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);          /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN (= dose) */

/* column denominators (N=) per dose level + Total (Safety Population) */
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/* analysis records: Safety pop, scheduled baseline/post-dose visits, on-study */
data lb;
  set adam.adlb(where=(SAFFL='Y' and ANL01FL='Y' and not missing(AVISITN)));
  /* AVAL=observed, BASE=Day 1 pre-dose baseline, CHG=change (all from ADaM)    */
  /* Treatment (= dose level) taken straight from ADaM - no re-derivation       */
run;

/*--- observed value summary: n, Mean(SD), Median, Min-Max -----------------*
* MAD key change: CLASS carries &TRTVAR (=TRT01A) so each dose-level cohort   *
* forms its own column. AVISIT spans the repeated-dosing schedule. Decimal    *
* hints by parameter via a DP lookup.                                        */
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
  by PARAMCD PARAM AVISITN AVISIT stattype stat;   /* one col per dose + Total */
  id &TRTNVAR; var value;
run;

%tfltitle(num=14.3.4.1, type=Table,
   text=%str(Summary of Laboratory Values and Change from Baseline by Visit and Dose Level),
   pop=Safety Population,
   foot=%str(Statistics are descriptive only. Change from Baseline = post-baseline value minus the Day 1 pre-first-dose baseline (ADaM CHG). Columns = dose-level cohort (MAD; one dose per participant). Visits span the multiple-dose period. SI units. Scheduled visits only.));
proc report data=_wide nowd split='|';
  columns PARAM AVISITN AVISIT stattype stat ("Dose Level" /* dose cols + Total */);
  define PARAM    / order 'Laboratory|Parameter' width=24 flow;
  define AVISITN  / order noprint;
  define AVISIT   / order 'Visit'      width=14;
  define stattype / order 'Measure'    width=18;   /* Observed / Change       */
  define stat     / display 'Statistic' width=12;
  /* define <each dose-level var> / display center "&header (N=&n)";          */
  break after PARAM / skip;
run;
