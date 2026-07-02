/******************************************************************************
* TABLE     : t_pk_param_summary  (Single-/fixed-sequence - e.g. DDI)
* TITLE     : Summary of Plasma PK Parameters by Treatment Period
* POPULATION: PK Parameter Population (PKFL='Y' / APPARMFL)
* INPUT     : ADPP (PARAMCD = CMAX, TMAX, AUCLST, AUCIFO, T12, CL, VZ, ...)
* NOTE      : PSEUDOCODE. Single-/fixed-sequence design (e.g. DDI) -> summarize
*             by the dosing PERIOD (Reference = victim alone; Test = victim+
*             perpetrator), captured by APERIODC. There is NO randomized
*             sequence, so the column is the period (not a randomized arm). The
*             Test-vs-Reference statistical comparison itself lives in
*             t_be_anova.sas (ratio + 90% CI, mixed model WITHOUT a sequence
*             term); this table is its descriptive companion. Report arithmetic
*             n, Mean, SD, CV%, Geo Mean, Geo CV%, Median, Min, Max. Tmax =
*             Median (Min, Max) ONLY. Geometric stats undefined if AVAL<=0
*             (exclude / footnote).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);                /* column = APERIODC (period)    */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=PKFL, out=_bign);

data pp;
  set adam.adpp(where=(PKFL='Y'));
  trt   = &TRTVAR;                            /* treatment given this period   */
  trtn  = &TRTNVAR;
  /* &BYPERIOD = APERIOD APERIODC -> column is the period (Reference / Test)    */
  /* PARAMCD order/labels via format; flag Tmax/Tmax,ss for median-only handling */
  tmaxfl = (PARAMCD in ('TMAX','TMAXSS'));   /* excluded from the geometric block */
  if AVAL>0 then logv = log(AVAL);            /* log value for geometric stats */
run;

/*--- arithmetic + geometric summary per period x parameter --------------*/
proc means data=pp(where=(tmaxfl=0)) noprint;
  class &BYPERIOD PARAMCD PARAM;
  var AVAL;
  output out=_arith n=n mean=mean std=std min=min max=max median=med cv=cv;
run;
/* geometric: run PROC MEANS on log(AVAL) (AVAL>0), back-transform:
   GeoMean=exp(mean_log); GeoCV%=100*sqrt(exp(var_log)-1)                     */
proc means data=pp(where=(tmaxfl=0 and AVAL>0)) noprint;
  class &BYPERIOD PARAMCD; var logv;                       /* log(AVAL)       */
  output out=_geo mean=gmean_log std=gsd_log;              /* on logVAL       */
run;

data _cont; merge _arith _geo; by &BYPERIOD PARAMCD; length stat $14 value $30;
  /* round to ADaM decimal hints per parameter; build display strings:        */
  /* n / Mean / SD / CV% / Geo Mean / Geo CV% / Median / Min / Max            */
run;

/*--- Tmax / Tmax,ss: Median (Min, Max) only -----------------------------*/
proc means data=pp(where=(tmaxfl=1)) noprint;
  class &BYPERIOD PARAMCD PARAM; var AVAL;
  output out=_tmax n=n median=med min=min max=max;
run;
data _tmaxd; set _tmax; length stat $14 value $30;
  stat='Median (Min, Max)';
  value=catx(' ', put(med,8.2), cats('(',put(min,8.2),', ',put(max,8.2),')'));
run;

/*--- stack params (rows) x period (cols) --------------------------------*/
data _all; set _cont _tmaxd; run;
proc transpose data=_all out=_wide; by PARAM PARAMCD stat; id APERIOD; var value; run;

%tfltitle(num=14.4.4.1, type=Table,
   text=%str(Summary of Plasma Pharmacokinetic Parameters by Treatment Period),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(Single-/fixed-sequence: summarized by dosing period (Reference vs Test); no randomized sequence. CV% arithmetic; Geo CV% = 100*sqrt(exp(s^2_log)-1). Tmax and Tmax,ss: Median (Min, Max) only (excluded from the geometric block). N excludes BLQ-driven non-estimable parameters. Test-vs-Reference comparison: see t_be_anova.));
proc report data=_wide nowd split='|';
  columns PARAM PARAMCD stat ("Treatment Period" /* APERIODC cols: Reference / Test */);
  define PARAM  / order 'Parameter (units)' width=26;
  define PARAMCD/ order noprint;
  define stat   / display 'Statistic' width=16;
run;
