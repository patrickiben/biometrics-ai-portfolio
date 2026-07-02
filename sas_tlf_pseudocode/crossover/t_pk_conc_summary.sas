/******************************************************************************
* TABLE     : t_pk_conc_summary  (Crossover - 2x2 or Williams)
* TITLE     : Summary of Plasma Concentrations by Treatment and Nominal Time
* POPULATION: PK Concentration Population (PKFL='Y')
* INPUT     : ADPC (AVAL = concentration; ATPT/ATPTN = nominal sampling time)
* NOTE      : PSEUDOCODE. Crossover within-participant design -> summarize by the
*             ANALYSIS treatment TRTA (the treatment actually received in that
*             period), NOT a fixed planned arm. Same nominal-time grid repeats
*             each period; collapse across period within TRTA. Report n, Mean,
*             SD, CV%, Geo Mean, Geo CV%, Median, Min, Max per treatment x time.
*             BLQ handled per ADPC convention (AVALC='BLQ' -> 0 / excluded from
*             geometric stats). Geometric stats undefined if AVAL<=0.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTVAR=TRTA; BYPERIOD=APERIOD APERIODC */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=PKFL, out=_bign);

data pc;
  set adam.adpc(where=(PKFL='Y'));
  /* crossover: column is the treatment received this period (TRTA), pooled   */
  /* across APERIOD; nominal time = ATPTN ordered by ATPT label              */
  trt   = &TRTVAR;             /* analysis treatment (Test / Reference)       */
  trtn  = &TRTNVAR;
  blqfl = (upcase(AVALC)='BLQ');
  if AVAL>0 then logv = log(AVAL);  /* log conc for geometric stats          */
run;

/*--- arithmetic summary per treatment x nominal time --------------------*/
proc means data=pc noprint;
  class &TRTVAR &TRTNVAR ATPTN ATPT PARAMCD;
  var AVAL;
  output out=_arith n=n nmiss=nmiss mean=mean std=std min=min max=max
                    median=med cv=cv;
run;

/*--- geometric summary on log scale (AVAL>0 only; exclude BLQ/zero) ------*/
proc means data=pc(where=(AVAL>0 and blqfl=0)) noprint;
  class &TRTVAR &TRTNVAR ATPTN PARAMCD; var logv;          /* log(AVAL)      */
  output out=_geo mean=gmean_log std=gsd_log;              /* on logVAL      */
run;
/* GeoMean=exp(gmean_log); GeoCV%=100*sqrt(exp(gsd_log**2)-1)                */

data _cont;
  merge _arith _geo; by &TRTVAR ATPTN PARAMCD;
  length stat $14 value $30;
  /* round to ADPC decimal hints; build display strings stacked as rows:     */
  /* n / Mean / SD / CV% / Geo Mean / Geo CV% / Median / Min / Max           */
  /* number of BLQ shown as n(BLQ) footnote-driven count = nmiss/blq tally   */
run;

/*--- stack stats (rows) within time, treatment across columns -----------*/
proc transpose data=_cont out=_wide; by PARAMCD ATPTN ATPT stat; id &TRTNVAR; var value; run;
proc sort data=_wide; by PARAMCD ATPTN; run;

%tfltitle(num=14.4.1.1, type=Table,
   text=%str(Summary of Plasma Concentrations by Treatment and Nominal Time),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(Within-participant crossover: summarized by treatment received (TRTA), pooled across period. CV% arithmetic; Geo CV% = 100*sqrt(exp(s^2_log)-1). BLQ set to 0 and excluded from geometric statistics. Nominal sampling time shown.));
proc report data=_wide nowd split='|';
  columns PARAMCD ATPTN ATPT stat ("Treatment" /* TRTA cols: Test / Reference */);
  define PARAMCD/ order noprint;
  define ATPTN  / order noprint;
  define ATPT   / order 'Nominal Time' width=16;
  define stat   / display 'Statistic' width=14;
run;
