/******************************************************************************
* TABLE     : t_ecg_summary  (Crossover - 2x2 or Williams)
* TITLE     : Summary of ECG Parameters and Change from Baseline by Visit
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADEG (PARAMCD in HR, PR, QRS, QT, QTCF, QTCB, RR)
* NOTE      : PSEUDOCODE. Within-participant crossover -> summarize by analysis
*             treatment TRTA within treatment period. AVAL and CHG (change from
*             within-period baseline) by visit: n, Mean (SD), Median, Min, Max.
*             QTcF is the protocol-preferred correction. Columns = treatments
*             (+ Total). A by-period breakout (APERIODC) is available per SAP.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTVAR=TRTA ; BYPERIOD=APERIOD APERIODC */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

data eg;
  set adam.adeg(where=(SAFFL='Y' and ANL01FL='Y'
                       and PARAMCD in ('HR','PR','QRS','QT','QTCF','QTCB','RR')));
run;

%macro egblk(param=, label=, dp=1, ord=);
  %descstat(ds=eg, var=AVAL,
            class=&TRTVAR &TRTNVAR AVISITN AVISIT,
            where=%str(PARAMCD="&param"), dp=&dp, out=_a);
  data _a; set _a; length param $40 type $20; param="&label"; type='Value'; ord=&ord; run;
  %descstat(ds=eg, var=CHG,
            class=&TRTVAR &TRTNVAR AVISITN AVISIT,
            where=%str(PARAMCD="&param" and AVISITN>0), dp=&dp, out=_c);
  data _c; set _c; length param $40 type $20; param="&label"; type='Change'; ord=&ord; run;
  data _eg_&param; set _a _c; run;
%mend egblk;
%egblk(param=HR,   label=Heart Rate (beats/min),   dp=1, ord=1);
%egblk(param=PR,   label=PR Interval (msec),        dp=1, ord=2);
%egblk(param=QRS,  label=QRS Duration (msec),       dp=1, ord=3);
%egblk(param=QT,   label=QT Interval (msec),        dp=1, ord=4);
%egblk(param=QTCF, label=QTcF Interval (msec),      dp=1, ord=5);
%egblk(param=QTCB, label=QTcB Interval (msec),      dp=1, ord=6);

data _all; set _eg_:;
  length stat $20 value $40;
  if missing(AVISITN) then delete;
  stat='n';          value=put(n,5.);             output;
  stat='Mean (SD)';  value=catx(' ',cmean,csd);   output;
  stat='Median';     value=cmed;                  output;
  stat='Min, Max';   value=cminmax;               output;
  keep ord param type AVISITN AVISIT &TRTVAR &TRTNVAR stat value;
run;
proc sort data=_all; by ord param type AVISITN AVISIT stat; run;
proc transpose data=_all out=_wide;
  by ord param type AVISITN AVISIT stat;  id &TRTNVAR;  var value;  /* one col / trt + Total */
run;

%tfltitle(num=14.3.8.1, type=Table,
   text=%str(Summary of ECG Parameters and Change from Baseline by Visit),
   pop=Safety Population,
   foot=%str(Change = post-baseline value minus within-period baseline (ADEG CHG). QTcF = Fridericia correction. Participants contribute to each treatment received (crossover).));
proc report data=_wide nowd split='|';
  columns ord param type AVISIT stat ("Treatment" _NAME_ /* trt cols + Total */);
  define ord    / order noprint;
  define param  / order  'Parameter'  width=24;
  define type   / order  'Type'       width=10;
  define AVISIT / order  'Visit'      width=16;
  define stat   / display 'Statistic' width=12;
  /* define <each treatment var> / display center "&header (N=&n)"; */
run;
