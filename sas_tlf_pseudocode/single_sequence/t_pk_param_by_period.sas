/******************************************************************************
* TABLE     : t_pk_param_by_period  (Single-/fixed-sequence - e.g. DDI)
* TITLE     : Summary of Plasma PK Parameters by Treatment and Period
* POPULATION: PK Parameter Population (PKFL='Y')
* INPUT     : ADPP (PARAMCD = CMAX, TMAX, AUCLST, AUCIFO, T12, CL, VZ, ...)
* NOTE      : PSEUDOCODE. Design-specific single-/fixed-sequence table. It
*             crosses the treatment given (TRTA) BY dosing period (APERIOD/
*             APERIODC = Reference vs Test). Under a fixed single sequence the
*             treatment and period are aligned for every participant (victim alone
*             in the reference period, victim+perpetrator in the test period),
*             so this is the descriptive read-out that directly supports the
*             drug-interaction comparison the t_be_anova mixed model tests
*             formally (Test vs Reference, NO sequence term). Reviewers compare
*             each parameter across the two periods to eyeball the interaction
*             magnitude and any unexpected period-to-period drift before the
*             model. Report n, Geo Mean, Geo CV%, Mean, SD, CV%, Median, Min,
*             Max. Tmax = Median (Min, Max) only.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA; BYPERIOD=APERIOD APERIODC     */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=PKFL, out=_bign);

data pp;
  set adam.adpp(where=(PKFL='Y'));
  trt    = &TRTVAR;                          /* treatment given this period     */
  trtn   = &TRTNVAR;
  /* &BYPERIOD = APERIOD APERIODC -> column nesting Treatment x Period           */
  tmaxfl = (PARAMCD='TMAX');
  if AVAL>0 then logv = log(AVAL);          /* log value for geometric stats   */
run;

/*--- arithmetic + geometric summary per treatment x period x parameter --*/
proc means data=pp(where=(tmaxfl=0)) noprint;
  class &TRTVAR &TRTNVAR &BYPERIOD PARAMCD PARAM;
  var AVAL;
  output out=_arith n=n mean=mean std=std min=min max=max median=med cv=cv;
run;
proc means data=pp(where=(tmaxfl=0 and AVAL>0)) noprint;
  class &TRTVAR &TRTNVAR &BYPERIOD PARAMCD; var logv;       /* log(AVAL)        */
  output out=_geo mean=gmean_log std=gsd_log;              /* on logVAL        */
run;
/* GeoMean=exp(gmean_log); GeoCV%=100*sqrt(exp(gsd_log**2)-1)                   */

data _cont; merge _arith _geo; by &TRTVAR &BYPERIOD PARAMCD;
  length stat $14 value $30;
  /* build display strings: n / Geo Mean / Geo CV% / Mean / SD / CV% /
     Median / Min / Max, rounded to ADaM decimal hints per parameter            */
run;

/*--- Tmax: Median (Min, Max) only ---------------------------------------*/
proc means data=pp(where=(tmaxfl=1)) noprint;
  class &TRTVAR &TRTNVAR &BYPERIOD PARAMCD PARAM; var AVAL;
  output out=_tmax n=n median=med min=min max=max;
run;
data _tmaxd; set _tmax; length stat $14 value $30;
  stat='Median (Min, Max)';
  value=catx(' ', put(med,8.2), cats('(',put(min,8.2),', ',put(max,8.2),')'));
run;

/*--- columns = Treatment x Period; rows = Parameter x Statistic ---------*/
data _all; set _cont _tmaxd; run;
/* build a single column key combining treatment and period for transpose       */
data _all; set _all; length colkey $40;
  colkey = catx('_', cats('T',&TRTNVAR), cats('P',APERIOD));   /* e.g. T1_P2    */
run;
proc sort data=_all; by PARAM PARAMCD stat; run;
proc transpose data=_all out=_wide; by PARAM PARAMCD stat; id colkey; var value; run;

%tfltitle(num=14.4.4.3, type=Table,
   text=%str(Summary of Plasma Pharmacokinetic Parameters by Treatment and Period),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(Single-/fixed-sequence: descriptive support for the Test-vs-Reference drug-interaction read-out (formal test: t_be_anova mixed model, treatment term, NO sequence term). CV% arithmetic; Geo CV% = 100*sqrt(exp(s^2_log)-1). Tmax: Median (Min, Max). Columns nest treatment given within period (Reference vs Test).));
proc report data=_wide nowd split='|';
  columns PARAM PARAMCD stat
          ("Treatment x Period" /* Reference / Test columns */);
  define PARAM  / order 'Parameter (units)' width=26;
  define PARAMCD/ order noprint;
  define stat   / display 'Statistic' width=16;
run;
