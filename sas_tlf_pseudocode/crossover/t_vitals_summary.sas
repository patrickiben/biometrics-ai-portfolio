/******************************************************************************
* TABLE     : t_vitals_summary  (Crossover - 2x2 or Williams)
* TITLE     : Summary of Vital Signs and Change from Baseline by Visit
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADVS (PARAMCD in SYSBP, DIABP, PULSE, TEMP, RESP)
* NOTE      : PSEUDOCODE. Within-participant crossover -> summarize by analysis
*             treatment TRTA within each treatment PERIOD (APERIODC). Each
*             participant contributes to every treatment they received. AVAL and
*             CHG (change from period baseline) summarized by visit:
*             n, Mean (SD), Median, Min, Max. Columns = treatments (+ Total).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTVAR=TRTA TRTNVAR=TRTAN BYPERIOD=APERIOD APERIODC SEQVAR=TRTSEQP */

/* column denominators (N=) per treatment + Total, Safety Population */
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

data vs;
  set adam.advs(where=(SAFFL='Y' and ANL01FL='Y'
                       and PARAMCD in ('SYSBP','DIABP','PULSE','TEMP','RESP')));
  /* treatment / period / sequence come straight from ADaM - no re-derivation */
run;

/*--- per parameter: AVAL and CHG by treatment x visit -------------------*
* CHG is the change from the within-period baseline carried on ADVS.       *
* Crossover key change: class includes &TRTVAR (=TRTA) so each treatment   *
* the participant received forms its own column; APERIODC available if a       *
* by-period breakout is requested by the SAP.                             */
%macro vsblk(param=, label=, dp=1, ord=);
  /* AVAL */
  %descstat(ds=vs, var=AVAL,
            class=&TRTVAR &TRTNVAR AVISITN AVISIT,
            where=%str(PARAMCD="&param"), dp=&dp, out=_a);
  data _a; set _a; length param $40 type $20; param="&label"; type='Value'; ord=&ord; run;
  /* CHG (skip the baseline visit, which has no meaningful change) */
  %descstat(ds=vs, var=CHG,
            class=&TRTVAR &TRTNVAR AVISITN AVISIT,
            where=%str(PARAMCD="&param" and AVISITN>0), dp=&dp, out=_c);
  data _c; set _c; length param $40 type $20; param="&label"; type='Change'; ord=&ord; run;
  data _vs_&param; set _a _c; run;
%mend vsblk;
%vsblk(param=SYSBP, label=Systolic Blood Pressure (mmHg),  dp=1, ord=1);
%vsblk(param=DIABP, label=Diastolic Blood Pressure (mmHg), dp=1, ord=2);
%vsblk(param=PULSE, label=Pulse Rate (beats/min),          dp=1, ord=3);
%vsblk(param=TEMP,  label=Temperature (C),                 dp=1, ord=4);
%vsblk(param=RESP,  label=Respiratory Rate (breaths/min),  dp=1, ord=5);

/*--- stack, build statistic rows, transpose to one column per treatment --*/
data _all; set _vs_:;
  length stat $20 value $40;
  /* skip the automatic _TYPE_ marginal rows from PROC MEANS */
  if missing(AVISITN) then delete;
  stat='n';          value=put(n,5.);              output;
  stat='Mean (SD)';  value=catx(' ',cmean,csd);    output;
  stat='Median';     value=cmed;                   output;
  stat='Min, Max';   value=cminmax;                output;
  keep ord param type AVISITN AVISIT &TRTVAR &TRTNVAR stat value;
run;
proc sort data=_all; by ord param type AVISITN AVISIT stat; run;
proc transpose data=_all out=_wide;
  by ord param type AVISITN AVISIT stat;  id &TRTNVAR;  var value;  /* one col / trt + Total */
run;

%tfltitle(num=14.3.7.1, type=Table,
   text=%str(Summary of Vital Signs and Change from Baseline by Visit),
   pop=Safety Population,
   foot=%str(Change = post-baseline value minus within-period baseline (ADVS CHG). Participants contribute to each treatment received (crossover). N per treatment from the Safety Population.));
proc report data=_wide nowd split='|';
  columns ord param type AVISIT stat ("Treatment" _NAME_ /* trt cols + Total */);
  define ord    / order noprint;
  define param  / order  'Parameter'  width=28;
  define type   / order  'Type'       width=10;
  define AVISIT / order  'Visit'      width=16;
  define stat   / display 'Statistic' width=12;
  /* define <each treatment var> / display center "&header (N=&n)"; */
run;
