/******************************************************************************
* TABLE     : t_ecg_summary  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Summary of ECG Parameters and Change from Baseline by Period
*             and Visit
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADEG (PARAMCD in HR, PR, QRS, QT, QTCF, QTCB, RR)
* NOTE      : PSEUDOCODE. Single-/fixed-sequence design (fixed treatment order;
*             NO randomized sequence) -> summarize within treatment PERIOD
*             (APERIODC) with analysis treatment TRTA. AVAL and CHG (change from
*             within-period baseline) by visit: n, Mean (SD), Median, Min, Max.
*             QTcF is the protocol-preferred correction. Columns = treatment
*             periods (+ Total); each participant contributes to every period.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA ; BYPERIOD=APERIOD APERIODC ; no SEQVAR */

/*--- header denominators = N per PERIOD column (+ Total). APERIOD/APERIODC are
* BDS per-record vars (not on ADSL), so the per-period N is built from the
* period-bearing source ADEX (mirror t_exposure.sas): participants dosed in the
* period, plus a Total column.                                              */
proc sql noprint;
  create table _bign as
    select APERIOD as trtn, APERIODC as trt length=200,
           count(distinct USUBJID) as N
    from adam.adex where SAFFL='Y' group by APERIOD, APERIODC
  union all
    select 9999 as trtn, 'Total' as trt, count(distinct USUBJID) as N
    from adam.adex where SAFFL='Y';
quit;

data eg;
  set adam.adeg(where=(SAFFL='Y' and ANL01FL='Y'
                       and PARAMCD in ('HR','PR','QRS','QT','QTCF','QTCB','RR')));
run;

%macro egblk(param=, label=, dp=1, ord=);
  %descstat(ds=eg, var=AVAL,
            class=&BYPERIOD &TRTVAR &TRTNVAR AVISITN AVISIT,
            where=%str(PARAMCD="&param"), dp=&dp, out=_a);
  data _a; set _a; length param $40 type $20; param="&label"; type='Value'; ord=&ord; run;
  %descstat(ds=eg, var=CHG,
            class=&BYPERIOD &TRTVAR &TRTNVAR AVISITN AVISIT,
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
  keep ord param type APERIOD APERIODC AVISITN AVISIT stat value;
run;
proc sort data=_all; by ord param type AVISITN AVISIT stat APERIOD; run;
proc transpose data=_all out=_wide;
  by ord param type AVISITN AVISIT stat;  id APERIOD;  var value;  /* one col / period + Total */
run;

%tfltitle(num=14.3.8.1, type=Table,
   text=%str(Summary of ECG Parameters and Change from Baseline by Period and Visit),
   pop=Safety Population,
   foot=%str(Change = post-baseline value minus within-period baseline (ADEG CHG). QTcF = Fridericia correction. Single-/fixed-sequence: columns are treatment periods (APERIODC); each participant contributes to every period.));
proc report data=_wide nowd split='|';
  columns ord param type AVISIT stat ("Treatment Period" _NAME_ /* period cols + Total */);
  define ord    / order noprint;
  define param  / order  'Parameter'  width=24;
  define type   / order  'Type'       width=10;
  define AVISIT / order  'Visit'      width=16;
  define stat   / display 'Statistic' width=12;
  /* define <each period var> / display center "&periodlbl (N=&n)"; */
run;
