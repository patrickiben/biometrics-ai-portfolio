/******************************************************************************
* TABLE     : t_lab_shift  (Single Ascending Dose)
* TITLE     : Shift from Baseline to Worst Post-Baseline Normal Range
*             Category by Laboratory Parameter
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, BNRIND, ANRIND, AVISITN)
* NOTE      : PSEUDOCODE. Shift = baseline normal-range indicator (BNRIND)
*             vs worst post-baseline indicator (ANRIND), cross-tabulated.
*             Counts = PARTICIPANTS (distinct USUBJID). % denominator = participants
*             with a non-missing baseline category in that dose level. One
*             table block per parameter; separate panel per dose level.
*             SAD design: parallel ascending cohorts, single dose; column/
*             panel = TRT01A (dose level), placebo pooled across cohorts.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN  */

/* analysis records: Safety pop, records contributing to shift analysis      */
data lb;
  set adam.adlb(where=(SAFFL='Y' and ANL01FL='Y'
                       and not missing(BNRIND) and not missing(ANRIND)));
  /* order categories LOW < NORMAL < HIGH (numeric rank for sort/worst)       */
  bn = whichc(upcase(BNRIND),'LOW','NORMAL','HIGH');   /* baseline rank       */
  an = whichc(upcase(ANRIND),'LOW','NORMAL','HIGH');   /* postbaseline rank   */
run;

/*--- worst post-baseline category per participant/parameter -------------------*/
/* "worst" = furthest from NORMAL. Rank by distance from NORMAL (dist=|an-2|), *
* so both LOW (an=1) and HIGH (an=3) outrank NORMAL (an=2). Take the max      *
* distance per participant, then resolve direction below NORMAL -> LOW, above ->  *
* HIGH.                                                                       */
data lb;
  set lb;
  dist = abs(an - 2);                 /* distance from NORMAL (LOW/HIGH = 1)   */
  sdist = (an - 2);                   /* signed: <0 below NORMAL, >0 above     */
run;
proc means data=lb nway noprint;
  class USUBJID &TRTVAR &TRTNVAR PARAMCD PARAM BNRIND bn;
  var dist sdist;
  output out=_worst max(dist)=dist_worst max(sdist)=hi_ext min(sdist)=lo_ext;
run;
data _worst; set _worst;
  length ANRIND_W $20;
  /* direction of the most-extreme shift: prefer HIGH on ties (hi_ext>=dist)   */
  if dist_worst = 0 then ANRIND_W = 'NORMAL';
  else if hi_ext = dist_worst then ANRIND_W = 'HIGH';   /* extreme above NORMAL */
  else ANRIND_W = 'LOW';                                /* extreme below NORMAL */
run;

/*--- denominator: participants with non-missing baseline category, per dose -----*/
proc sql;
  create table _den as
    select &TRTNVAR, PARAMCD, count(distinct USUBJID) as Nbase
    from _worst group by &TRTNVAR, PARAMCD;
quit;

/*--- shift counts: distinct participants per baseline x worst-postbaseline cell */
proc sql;
  create table _shift as
    select &TRTVAR, &TRTNVAR, PARAMCD, PARAM, BNRIND, bn, ANRIND_W,
           count(distinct USUBJID) as nsubj
    from _worst
    group by &TRTVAR, &TRTNVAR, PARAMCD, PARAM, BNRIND, bn, ANRIND_W;
quit;
/* merge Nbase by dose+param -> pct = nsubj/Nbase*100 ; value = "n (xx.x%)"   */

proc sort data=_shift; by PARAMCD PARAM &TRTNVAR bn BNRIND; run;
proc transpose data=_shift out=_wide;
  by PARAMCD PARAM &TRTNVAR bn BNRIND;
  id ANRIND_W; var nsubj;          /* columns = worst Low / Normal / High     */
run;

%tfltitle(num=14.3.4.2, type=Table,
   text=%str(Shift from Baseline to Worst Post-Baseline Normal Range Category by Laboratory Parameter),
   pop=Safety Population,
   foot=%str(Rows = baseline category (BNRIND); columns = worst post-baseline category. Counts = participants with a non-missing baseline category. % = n / participants with baseline category in dose level. One panel per dose level (TRT01A); placebo pooled.));
proc report data=_wide nowd split='|';
  columns PARAM &TRTNVAR BNRIND ('Worst Post-Baseline Category' Low Normal High);
  define PARAM    / order 'Laboratory|Parameter' width=24 flow;
  define &TRTNVAR / order 'Dose Level' width=18;      /* panel per dose level */
  define BNRIND   / order 'Baseline|Category'    width=12;
  define Low      / display 'Low'    center width=12;
  define Normal   / display 'Normal' center width=12;
  define High     / display 'High'   center width=12;
  break after &TRTNVAR / skip;
run;
