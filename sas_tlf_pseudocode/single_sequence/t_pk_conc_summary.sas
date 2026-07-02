/******************************************************************************
* TABLE     : t_pk_conc_summary  (Single-/fixed-sequence - e.g. DDI)
* TITLE     : Summary of Plasma Concentrations by Treatment Period and
*             Nominal Time
* POPULATION: PK Concentration Population (PKFL='Y')
* INPUT     : ADPC (AVAL = concentration; ATPT/ATPTN = nominal sampling time)
* NOTE      : PSEUDOCODE. Single-/fixed-sequence design (e.g. DDI: victim alone
*             in the reference period, then victim+perpetrator in the test
*             period). NO randomized sequence -> column = the dosing PERIOD the
*             participant received (APERIOD/APERIODC = Reference vs Test), captured
*             by TRTA. The same nominal-time grid repeats each period; summarize
*             per period x nominal time. Report n, Mean, SD, CV%, Geo Mean,
*             Geo CV%, Median, Min, Max. BLQ handled per ADPC convention
*             (AVALC='BLQ' -> 0 / excluded from geometric stats). Geometric
*             stats undefined if AVAL<=0.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA; BYPERIOD=APERIOD APERIODC   */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=PKFL, out=_bign);

data pc;
  set adam.adpc(where=(PKFL='Y'));
  /* single-seq: column is the dosing PERIOD (Reference / Test), no randomized   */
  /* sequence. TRTA carries the treatment given in that period; APERIODC labels  */
  /* the period (e.g. 'Reference' / 'Test+Perpetrator'). Nominal time = ATPTN.   */
  trt   = &TRTVAR;             /* treatment given this period                    */
  trtn  = &TRTNVAR;
  blqfl = (upcase(AVALC)='BLQ');
  if AVAL>0 then logv = log(AVAL);  /* log conc for geometric stats          */
run;

/*--- arithmetic summary per period x nominal time -----------------------*/
proc means data=pc noprint;
  class &BYPERIOD &TRTVAR &TRTNVAR ATPTN ATPT PARAMCD;
  var AVAL;
  output out=_arith n=n nmiss=nmiss mean=mean std=std min=min max=max
                    median=med cv=cv;
run;

/*--- geometric summary on log scale (AVAL>0 only; exclude BLQ/zero) ------*/
proc means data=pc(where=(AVAL>0 and blqfl=0)) noprint;
  class &BYPERIOD &TRTVAR &TRTNVAR ATPTN PARAMCD; var logv; /* log(AVAL)     */
  output out=_geo mean=gmean_log std=gsd_log;              /* on logVAL      */
run;
/* GeoMean=exp(gmean_log); GeoCV%=100*sqrt(exp(gsd_log**2)-1)                */

data _cont;
  merge _arith _geo; by &BYPERIOD &TRTVAR ATPTN PARAMCD;
  length stat $14 value $30;
  /* round to ADPC decimal hints; build display strings stacked as rows:     */
  /* n / Mean / SD / CV% / Geo Mean / Geo CV% / Median / Min / Max           */
  /* number of BLQ shown as n(BLQ) footnote-driven count = nmiss/blq tally   */
run;

/*--- stack stats (rows) within time; periods across columns -------------*/
proc transpose data=_cont out=_wide; by PARAMCD ATPTN ATPT stat; id APERIOD; var value; run;
proc sort data=_wide; by PARAMCD ATPTN; run;

%tfltitle(num=14.4.1.1, type=Table,
   text=%str(Summary of Plasma Concentrations by Treatment Period and Nominal Time),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(Single-/fixed-sequence: summarized by dosing period (Reference vs Test); no randomized sequence. CV% arithmetic; Geo CV% = 100*sqrt(exp(s^2_log)-1). BLQ set to 0 and excluded from geometric statistics. Nominal sampling time shown.));
proc report data=_wide nowd split='|';
  columns PARAMCD ATPTN ATPT stat ("Treatment Period" /* APERIODC cols: Reference / Test */);
  define PARAMCD/ order noprint;
  define ATPTN  / order noprint;
  define ATPT   / order 'Nominal Time' width=16;
  define stat   / display 'Statistic' width=14;
run;
