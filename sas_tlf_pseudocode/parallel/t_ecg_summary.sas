/******************************************************************************
* TABLE     : t_ecg_summary  (Parallel-group)
* TITLE     : Summary of ECG Parameters and Change from Baseline by Visit
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADEG  (PARAMCD: HR, PR, QRS, QT, QTCF, QTCB, RR; AVAL, CHG,
*             BASE, AVISIT/AVISITN, ATPT/ATPTN)
* NOTE      : PSEUDOCODE. Parallel-group: column = treatment arm (TRT01A),
*             one treatment per participant. Descriptive only (n, Mean(SD),
*             Median, Min, Max) for AVAL and CHG at each scheduled visit.
*             QTcF (Fridericia) is the primary corrected interval.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);          /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

/* column denominators (N=) per arm + Total */
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/*--- analysis-ready ECG: safety pop, on-treatment analysis records ----------*/
data adeg;
  set adam.adeg(where=(SAFFL='Y' and ANL01FL='Y'
                       and PARAMCD in ('HR','PR','QRS','QT','QTCF','QTCB')));
run;

/*--- one block per parameter: AVAL then CHG, by treatment x visit ----------*/
%macro egblk(pcd=, label=, dp=1, ord=);
  /* observed value */
  %descstat(ds=adeg, var=AVAL, class=&TRTVAR &TRTNVAR AVISITN AVISIT,
            where=%str(PARAMCD="&pcd"), dp=&dp, out=_a);
  data _e_&pcd._a; set _a; length param $40 measure $24 stat $20 value $40;
    param="&label"; measure='Observed value'; ord=&ord;
    stat='n';         value=put(n,5.);            output;
    stat='Mean (SD)'; value=catx(' ',cmean,csd);  output;
    stat='Median';    value=cmed;                 output;
    stat='Min, Max';  value=cminmax;              output;
  run;
  /* change from baseline (BASE/CHG from ADaM) */
  %descstat(ds=adeg, var=CHG, class=&TRTVAR &TRTNVAR AVISITN AVISIT,
            where=%str(PARAMCD="&pcd" and AVISITN>0), dp=&dp, out=_c);
  data _e_&pcd._c; set _c; length param $40 measure $24 stat $20 value $40;
    param="&label"; measure='Change from baseline'; ord=&ord;
    stat='n';         value=put(n,5.);            output;
    stat='Mean (SD)'; value=catx(' ',cmean,csd);  output;
    stat='Median';    value=cmed;                 output;
    stat='Min, Max';  value=cminmax;              output;
  run;
%mend egblk;
%egblk(pcd=HR,   label=Heart Rate (beats/min),   dp=1, ord=1);
%egblk(pcd=PR,   label=PR Interval (ms),         dp=1, ord=2);
%egblk(pcd=QRS,  label=QRS Duration (ms),        dp=1, ord=3);
%egblk(pcd=QT,   label=QT Interval (ms),         dp=1, ord=4);
%egblk(pcd=QTCF, label=QTcF Interval (ms),       dp=1, ord=5);
%egblk(pcd=QTCB, label=QTcB Interval (ms),       dp=1, ord=6);

/*--- stack, transpose to one column per treatment arm + Total -------------*/
data _all; set _e_:; run;
proc sort data=_all; by ord param measure AVISITN AVISIT stat; run;
proc transpose data=_all out=_wide;
  by ord param measure AVISITN AVISIT stat;
  id &TRTNVAR;  var value;             /* one col per arm + Total (9999)     */
run;

%tfltitle(num=14.3.5.1, type=Table,
   text=%str(Summary of ECG Parameters and Change from Baseline by Visit),
   pop=Safety Population,
   foot=%str(QTcF = Fridericia-corrected QT (ADaM). Change from baseline = post-baseline value - baseline (ADaM CHG). Descriptive statistics only; one treatment per participant (parallel-group).));
proc report data=_wide nowd split='|';
  columns ord param measure AVISITN AVISIT stat
          ("Treatment Arm" _NAME_ /* arm cols + Total */);
  define ord     / order noprint;
  define param   / order 'Parameter'  width=24;
  define measure / order 'Measure'    width=18;
  define AVISITN / order noprint;
  define AVISIT  / order 'Visit'      width=14;
  define stat    / display 'Statistic' width=12;
  /* define <each arm var> / display center "&header (N=&n)"; */
run;
