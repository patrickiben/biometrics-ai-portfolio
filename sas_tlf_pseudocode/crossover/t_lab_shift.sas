/******************************************************************************
* TABLE     : t_lab_shift  (Crossover - 2x2 or Williams)
* TITLE     : Shift from Baseline to Worst Post-Baseline Normal Range
*             Category by Laboratory Parameter
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, BNRIND, ANRIND, AVISITN, TRTA/TRTAN,
*             APERIODC, TRTSEQP)
* NOTE      : PSEUDOCODE. Shift = within-period baseline normal-range indicator
*             (BNRIND) vs worst post-baseline indicator (ANRIND), cross-
*             tabulated. Counts = PARTICIPANTS (distinct USUBJID). % denominator =
*             participants with a non-missing baseline category in that treatment.
*             Within-participant crossover -> one panel per analysis treatment TRTA
*             (each participant contributes per treatment received; baseline and
*             worst are taken WITHIN each treatment period). APERIODC retained
*             for an optional by-period breakout.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTVAR=TRTA TRTNVAR=TRTAN BYPERIOD=APERIOD APERIODC SEQVAR=TRTSEQP */

/* analysis records: Safety pop, records contributing to shift analysis      */
data lb;
  set adam.adlb(where=(SAFFL='Y' and ANL01FL='Y'
                       and not missing(BNRIND) and not missing(ANRIND)));
  /* order categories LOW < NORMAL < HIGH (numeric rank for sort/worst)       */
  bn = whichc(upcase(BNRIND),'LOW','NORMAL','HIGH');   /* baseline rank       */
  an = whichc(upcase(ANRIND),'LOW','NORMAL','HIGH');   /* postbaseline rank   */
  /* Treatment/period/sequence taken straight from ADaM - no re-derivation    */
run;

/*--- worst post-baseline category per participant/treatment/parameter ---------*
* Crossover: CLASS carries &TRTVAR (=TRTA) so the worst category is taken    *
* WITHIN each treatment the participant received (not pooled across periods).    *
* "worst" = furthest from NORMAL. Rank by distance from NORMAL (dist=|an-2|), *
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

/*--- denominator: participants with non-missing baseline category, per trt -----*/
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
/* merge Nbase by trt+param -> pct = nsubj/Nbase*100 ; value = "n (xx.x%)"    */

proc sort data=_shift; by PARAMCD PARAM &TRTNVAR bn BNRIND; run;
proc transpose data=_shift out=_wide;
  by PARAMCD PARAM &TRTNVAR bn BNRIND;
  id ANRIND_W; var nsubj;          /* columns = worst Low / Normal / High     */
run;

%tfltitle(num=14.3.4.2, type=Table,
   text=%str(Shift from Baseline to Worst Post-Baseline Normal Range Category by Laboratory Parameter),
   pop=Safety Population,
   foot=%str(Rows = within-period baseline category (BNRIND); columns = worst post-baseline category. Counts = participants with a non-missing baseline category. % = n / participants with baseline category in treatment. One panel per analysis treatment (crossover; each participant contributes per treatment received).));
proc report data=_wide nowd split='|';
  columns PARAM &TRTNVAR BNRIND ('Worst Post-Baseline Category' Low Normal High);
  define PARAM    / order 'Laboratory|Parameter' width=24 flow;
  define &TRTNVAR / order 'Treatment' width=18;       /* panel per treatment  */
  define BNRIND   / order 'Baseline|Category'    width=12;
  define Low      / display 'Low'    center width=12;
  define Normal   / display 'Normal' center width=12;
  define High     / display 'High'   center width=12;
  break after &TRTNVAR / skip;
run;
