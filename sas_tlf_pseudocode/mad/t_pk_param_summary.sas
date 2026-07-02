/******************************************************************************
* TABLE     : t_pk_param_summary  (MAD - Multiple Ascending Dose)
* TITLE     : Summary of Plasma PK Parameters by Dose Level and Study Day
* POPULATION: PK Parameter Population (PKFL='Y' / APPARMFL)
* INPUT     : ADPP (PARAMCD = day-1 single-dose: CMAX TMAX AUCLST AUCIFO ;
*             steady-state day-N: CMAXSS TMAXSS AUCTAU CMINSS CTROUGH CAVGSS
*             FLPTAU CLSS VSSF T12 ; accumulation: RACMAX RACAUC ; PARAM/PARAMCD)
* NOTE      : PSEUDOCODE. MAD: parallel cohorts, repeated dosing; column =
*             TRT01A/TRT01AN (= dose level, placebo typically pooled). Because
*             parameters are derived per dosing day, the table is crossed by study
*             day (AVISIT/AVISITN, e.g. Day 1 first-dose NCA vs Day N steady-state
*             NCA). Day 1 yields single-dose Cmax/AUClast/AUCinf; Day N yields the
*             steady-state set (Cmax,ss, AUCtau, Cmin,ss, Ctrough, Cavg,ss, CL,ss,
*             t1/2) and the accumulation ratios Rac are reported in t_accumulation.
*             Report arithmetic n, Mean, SD, CV%, Geo Mean, Geo CV%, Median, Min,
*             Max. Tmax / Tmax,ss = Median (Min, Max) ONLY. Geometric stats
*             undefined if AVAL<=0 (exclude / footnote).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* column = TRT01A (= dose)   */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=PKFL, out=_bign);

data pp;
  set adam.adpp(where=(PKFL='Y'));
  avisitn = AVISITN;              /* study day of the derived parameter        */
  /* flag median-only Tmax parameters (single-dose and steady-state)           */
  tmaxfl = (PARAMCD in ('TMAX','TMAXSS'));
  if AVAL>0 then logv = log(AVAL);           /* log value for geometric stats */
run;

/*--- arithmetic + geometric summary per dose x study-day x parameter -----*/
proc means data=pp(where=(tmaxfl=0)) noprint;
  class &TRTVAR &TRTNVAR avisitn AVISIT PARAMCD PARAM;
  var AVAL;
  output out=_arith n=n mean=mean std=std min=min max=max median=med cv=cv;
run;
/* geometric: run PROC MEANS on log(AVAL) (AVAL>0), back-transform:
   GeoMean=exp(mean_log); GeoCV%=100*sqrt(exp(var_log)-1)                   */
proc means data=pp(where=(tmaxfl=0 and AVAL>0)) noprint;
  class &TRTVAR &TRTNVAR avisitn PARAMCD; var logv;        /* log(AVAL)      */
  output out=_geo mean=gmean_log std=gsd_log;              /* on logVAL     */
run;

data _cont; merge _arith _geo; by &TRTVAR avisitn PARAMCD;
  length stat $14 value $30;
  /* round to ADaM decimal hints per parameter; build display strings:      */
  /* n / Mean / SD / CV% / Geo Mean / Geo CV% / Median / Min / Max          */
run;

/*--- Tmax / Tmax,ss: Median (Min, Max) only -----------------------------*/
proc means data=pp(where=(tmaxfl=1)) noprint;
  class &TRTVAR &TRTNVAR avisitn AVISIT PARAMCD PARAM; var AVAL;
  output out=_tmax n=n median=med min=min max=max;
run;
data _tmaxd; set _tmax; length stat $14 value $30;
  stat='Median (Min, Max)';
  value=catx(' ', put(med,8.2), cats('(',put(min,8.2),', ',put(max,8.2),')'));
run;

/*--- stack params x day (rows) x dose level (cols) -----------------------*/
data _all; set _cont _tmaxd; run;
proc sort data=_all; by avisitn AVISIT PARAM PARAMCD stat; run;
proc transpose data=_all out=_wide; by avisitn AVISIT PARAM PARAMCD stat;
  id &TRTNVAR; var value; run;

%tfltitle(num=14.4.1.1, type=Table,
   text=%str(Summary of Plasma Pharmacokinetic Parameters by Dose Level and Study Day),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(CV% arithmetic; Geo CV% = 100*sqrt(exp(s^2_log)-1). Tmax / Tmax,ss: Median (Min, Max). Multiple ascending dose: Day 1 = single-dose NCA (Cmax, AUClast, AUCinf); Day N = steady-state NCA (Cmax,ss, AUCtau, Cmin,ss, Ctrough, Cavg,ss, CL,ss, t1/2). Accumulation ratios in t_accumulation. N excludes BLQ-driven non-estimable parameters.));
proc report data=_wide nowd split='|';
  columns avisitn AVISIT PARAM PARAMCD stat ("Treatment (Dose)" /* dose cols */);
  define avisitn / order noprint;
  define AVISIT  / order 'Study|Day' width=10;
  define PARAM   / order 'Parameter (units)' width=26;
  define PARAMCD / order noprint;
  define stat    / display 'Statistic' width=16;
  break after AVISIT / skip;
run;
