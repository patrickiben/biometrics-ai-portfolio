/******************************************************************************
* TABLE     : t_exposure  (Parallel-group)
* TITLE     : Extent of Study Drug Exposure
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADEX  (one or more exposure records per participant)
* NOTE      : PSEUDOCODE. Parallel: one treatment per participant; column var =
*             TRT01A = assigned dose level for ascending-dose layouts.
*             Continuous exposure metrics: n, Mean(SD), Median, Min-Max per arm.
*             Cumulative dose / duration / dose-intensity summarized by arm.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);                 /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/*--- derive one exposure record per participant from ADEX ---------------------*
* Use ADEX analysis exposure params (PARAMCD) where available, else collapse
* dosing records. Pull treatment from ADEX (TRT01A) — no re-derivation.
*   AVAL by PARAMCD: TDOSE=total cumulative dose; DURD=duration of exposure
*   (days); NDOSE=number of doses; DOSINT=dose intensity (%).               */
data adex;
  set adam.adex(where=(SAFFL='Y'));
run;

/*--- continuous exposure metric block, summarized per arm + Total ---------*/
%macro expblk(pcd=, label=, unit=, dp=1, ord=);
  %descstat(ds=adex, var=AVAL, class=&TRTVAR &TRTNVAR,
            where=%str(PARAMCD="&pcd"), dp=&dp, out=_d);
  data _e_&ord; set _d; length charlbl $48 stat $20 value $40;
    charlbl="&label";  ord=&ord;
    stat='n';         value=put(n,5.);            output;
    stat='Mean (SD)'; value=catx(' ',cmean,csd);  output;
    stat='Median';    value=cmed;                 output;
    stat='Min, Max';  value=cminmax;              output;
  run;
%mend;
%expblk(pcd=DURD,   label=Duration of exposure (days),     dp=1, ord=1);
%expblk(pcd=TDOSE,  label=Cumulative dose (mg),            dp=1, ord=2);
%expblk(pcd=NDOSE,  label=Number of doses received,        dp=0, ord=3);
%expblk(pcd=DOSINT, label=Dose intensity (%),              dp=1, ord=4);

/*--- exposure duration categories (n %) : e.g. >=1 dose, >=7 days, etc. ---*/
%macro expcat(flagexpr=, label=, ord=);
  proc sql;
    create table _x_&ord as
      select &TRTVAR as trt length=200, &TRTNVAR as trtn,
             count(distinct USUBJID) as nsubj
      from adex where &flagexpr group by &TRTVAR, &TRTNVAR
    union all
      select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as nsubj
      from adex where &flagexpr;
  quit;
  data _ec_&ord; set _x_&ord; length charlbl $48 stat $20 value $40;
    charlbl='Exposure duration n (%)'; stat="&label"; ord=&ord;
    /* value = n (%) vs SAFFL N per column from _bign : "n (xx.x%)"          */
  run;
%mend;
%expcat(flagexpr=%str(PARAMCD='DURD' and AVAL>=1),  label=>= 1 day,   ord=5);
%expcat(flagexpr=%str(PARAMCD='DURD' and AVAL>=7),  label=>= 7 days,  ord=6);
%expcat(flagexpr=%str(PARAMCD='DURD' and AVAL>=14), label=>= 14 days, ord=7);

/*--- stack, transpose to one column per arm + Total, render --------------*/
data _all; set _e_: _ec_:; run;
proc sort data=_all; by ord charlbl stat; run;
proc transpose data=_all out=_wide; by ord charlbl stat; id trtn; var value; run;

%tfltitle(num=14.1.4, type=Table, text=Extent of Study Drug Exposure,
          pop=Safety Population,
          foot=%str(Column = assigned treatment/dose level (TRT01A). Cumulative dose, duration and intensity from ADEX. Percentages based on Safety Population N per arm.));
proc report data=_wide nowd split='|';
  columns ord charlbl stat ("Treatment" _NAME_ /* arm cols + Total */);
  define ord     / order noprint;
  define charlbl / order  'Exposure Metric' width=26 flow;
  define stat    / display 'Statistic'       width=14;
  /* define <each arm var>/display center "&header (N=&n)"; */
run;
