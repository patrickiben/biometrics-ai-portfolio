/******************************************************************************
* TABLE     : t_pk_param_summary  (Crossover - 2x2 or Williams)
* TITLE     : Summary of Plasma PK Parameters by Treatment
* POPULATION: PK Parameter Population (PKFL='Y' / APPARMFL)
* INPUT     : ADPP (PARAMCD = CMAX, TMAX, AUCLST, AUCIFO, T12, CL, VZ, ...)
* NOTE      : PSEUDOCODE. Crossover within-participant design -> summarize by the
*             ANALYSIS treatment received TRTA (Test / Reference), pooled across
*             period within treatment. (The Test-vs-Reference statistical
*             comparison itself lives in t_be_anova.sas; this table is the
*             descriptive companion.) Report arithmetic n, Mean, SD, CV%,
*             Geo Mean, Geo CV%, Median, Min, Max. Tmax = Median (Min, Max)
*             ONLY. Geometric stats undefined if AVAL<=0 (exclude / footnote).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);                /* column = TRTA (Test/Reference)*/

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=PKFL, out=_bign);

data pp;
  set adam.adpp(where=(PKFL='Y'));
  trt   = &TRTVAR;                            /* treatment received            */
  trtn  = &TRTNVAR;
  /* PARAMCD order/labels via format; flag Tmax for median-only handling       */
  tmaxfl = (PARAMCD='TMAX');
  if AVAL>0 then logv = log(AVAL);           /* log value for geometric stats */
run;

/*--- arithmetic + geometric summary per treatment x parameter -----------*/
proc means data=pp(where=(tmaxfl=0)) noprint;
  class &TRTVAR &TRTNVAR PARAMCD PARAM;
  var AVAL;
  output out=_arith n=n mean=mean std=std min=min max=max median=med cv=cv;
run;
/* geometric: run PROC MEANS on log(AVAL) (AVAL>0), back-transform:
   GeoMean=exp(mean_log); GeoCV%=100*sqrt(exp(var_log)-1)                     */
proc means data=pp(where=(tmaxfl=0 and AVAL>0)) noprint;
  class &TRTVAR &TRTNVAR PARAMCD; var logv;                /* log(AVAL)       */
  output out=_geo mean=gmean_log std=gsd_log;              /* on logVAL       */
run;

data _cont; merge _arith _geo; by &TRTVAR PARAMCD; length stat $14 value $30;
  /* round to ADaM decimal hints per parameter; build display strings:        */
  /* n / Mean / SD / CV% / Geo Mean / Geo CV% / Median / Min / Max            */
run;

/*--- Tmax: Median (Min, Max) only ---------------------------------------*/
proc means data=pp(where=(tmaxfl=1)) noprint;
  class &TRTVAR &TRTNVAR PARAMCD PARAM; var AVAL;
  output out=_tmax n=n median=med min=min max=max;
run;
data _tmaxd; set _tmax; length stat $14 value $30;
  stat='Median (Min, Max)';
  value=catx(' ', put(med,8.2), cats('(',put(min,8.2),', ',put(max,8.2),')'));
run;

/*--- stack params (rows) x treatment (cols) -----------------------------*/
data _all; set _cont _tmaxd; run;
proc transpose data=_all out=_wide; by PARAM PARAMCD stat; id &TRTNVAR; var value; run;

%tfltitle(num=14.4.4.1, type=Table,
   text=%str(Summary of Plasma Pharmacokinetic Parameters by Treatment),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(Within-participant crossover: summarized by treatment received (TRTA), pooled across period. CV% arithmetic; Geo CV% = 100*sqrt(exp(s^2_log)-1). Tmax: Median (Min, Max). N excludes BLQ-driven non-estimable parameters. Test-vs-Reference comparison: see t_be_anova.));
proc report data=_wide nowd split='|';
  columns PARAM PARAMCD stat ("Treatment" /* TRTA cols: Test / Reference */);
  define PARAM  / order 'Parameter (units)' width=26;
  define PARAMCD/ order noprint;
  define stat   / display 'Statistic' width=16;
run;
