/******************************************************************************
* TABLE     : t_vitals_summary  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Summary of Vital Signs and Change from Baseline by Period
*             and Visit
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADVS (PARAMCD in SYSBP, DIABP, PULSE, TEMP, RESP)
* NOTE      : PSEUDOCODE. Single-/fixed-sequence design (every participant receives
*             treatments in the same fixed order, e.g. victim then victim +
*             perpetrator). There is NO randomized sequence -> columns are the
*             treatment PERIODS (APERIODC), summarized within analysis treatment
*             TRTA. AVAL and CHG (change from period baseline, ADVS CHG) by
*             visit: n, Mean (SD), Median, Min, Max. Each participant contributes to
*             every period. Columns = treatment periods. Per-period
*             denominators come from ADEX (participants dosed per APERIOD,
*             SAFFL='Y'), NEVER one-record-per-participant ADSL.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA TRTNVAR=TRTAN BYPERIOD=APERIOD APERIODC SEQVAR=(none) */

/* split the design's period columns into numeric (order) + character (label),
   mirroring the R twin's perN/perC. */
%let PERN=%scan(&BYPERIOD,1);   /* APERIOD  : numeric period (column order)  */
%let PERC=%scan(&BYPERIOD,2);   /* APERIODC : character period (header label) */

/* per-PERIOD column denominators (N=) + Total, Safety Population.
   HOUSE RULE: per-period N comes from a period-bearing source (ADEX), NOT
   ADSL (one record per participant). Count participants DOSED in each period:
   group ADEX SAFFL='Y' by period. TRTA still labels which agent(s) a period
   administered and is carried in the body CLASS, not in this denominator. */
%bign(ds=adam.adex, trtvar=&PERC, trtn=&PERN, popfl=SAFFL, out=_bign);

data vs;
  set adam.advs(where=(SAFFL='Y' and ANL01FL='Y'
                       and PARAMCD in ('SYSBP','DIABP','PULSE','TEMP','RESP')));
  /* treatment / period come straight from ADaM - no re-derivation; no sequence */
run;

/*--- per parameter: AVAL and CHG by period x treatment x visit ----------*
* Single-seq key change: CLASS keys on the fixed treatment PERIOD (APERIODC)  *
* with TRTA so the reader sees what each period administered. No SEQVAR.      *
* CHG is the change from the within-period baseline carried on ADVS.          */
%macro vsblk(param=, label=, dp=1, ord=);
  /* AVAL */
  %descstat(ds=vs, var=AVAL,
            class=&BYPERIOD &TRTVAR &TRTNVAR AVISITN AVISIT,
            where=%str(PARAMCD="&param"), dp=&dp, out=_a);
  data _a; set _a; length param $40 type $20; param="&label"; type='Value'; ord=&ord; run;
  /* CHG (skip the baseline visit, which has no meaningful change) */
  %descstat(ds=vs, var=CHG,
            class=&BYPERIOD &TRTVAR &TRTNVAR AVISITN AVISIT,
            where=%str(PARAMCD="&param" and AVISITN>0), dp=&dp, out=_c);
  data _c; set _c; length param $40 type $20; param="&label"; type='Change'; ord=&ord; run;
  data _vs_&param; set _a _c; run;
%mend vsblk;
%vsblk(param=SYSBP, label=Systolic Blood Pressure (mmHg),  dp=1, ord=1);
%vsblk(param=DIABP, label=Diastolic Blood Pressure (mmHg), dp=1, ord=2);
%vsblk(param=PULSE, label=Pulse Rate (beats/min),          dp=1, ord=3);
%vsblk(param=TEMP,  label=Temperature (C),                 dp=1, ord=4);
%vsblk(param=RESP,  label=Respiratory Rate (breaths/min),  dp=1, ord=5);

/*--- stack, build statistic rows, transpose to one column per period -----*/
data _all; set _vs_:;
  length stat $20 value $40;
  /* skip the automatic _TYPE_ marginal rows from PROC MEANS */
  if missing(AVISITN) then delete;
  stat='n';          value=put(n,5.);              output;
  stat='Mean (SD)';  value=catx(' ',cmean,csd);    output;
  stat='Median';     value=cmed;                   output;
  stat='Min, Max';   value=cminmax;                output;
  keep ord param type APERIOD APERIODC AVISITN AVISIT stat value;
run;
proc sort data=_all; by ord param type AVISITN AVISIT stat APERIOD; run;
proc transpose data=_all out=_wide;
  by ord param type AVISITN AVISIT stat;  id APERIOD;  var value;  /* one col / period */
run;

%tfltitle(num=14.3.7.1, type=Table,
   text=%str(Summary of Vital Signs and Change from Baseline by Period and Visit),
   pop=Safety Population,
   foot=%str(Change = post-baseline value minus within-period baseline (ADVS CHG). Single-/fixed-sequence: columns are treatment periods (APERIODC); every participant contributes to each period. Per-period N = participants dosed in each period (ADEX, SAFFL='Y').));
proc report data=_wide nowd split='|';
  columns ord param type AVISIT stat ("Treatment Period" _NAME_ /* period cols */);
  define ord    / order noprint;
  define param  / order  'Parameter'  width=28;
  define type   / order  'Type'       width=10;
  define AVISIT / order  'Visit'      width=16;
  define stat   / display 'Statistic' width=12;
  /* define <each period col> / display center "&periodlbl (N=&n)";    *
   * &n = the per-period denominator from _bign (ADEX participants      *
   * dosed, SAFFL='Y'), joined on the period - NOT an ADSL count.       */
run;
