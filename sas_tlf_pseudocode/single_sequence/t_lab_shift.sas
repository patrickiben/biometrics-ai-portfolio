/******************************************************************************
* TABLE     : t_lab_shift  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Shift from Baseline to Worst Post-Baseline Normal Range
*             Category by Laboratory Parameter and Period
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, BNRIND, ANRIND, AVISITN, APERIOD/APERIODC)
* NOTE      : PSEUDOCODE. Shift = within-period baseline normal-range indicator
*             (BNRIND) vs worst post-baseline indicator (ANRIND), cross-
*             tabulated. Counts = PARTICIPANTS (distinct USUBJID). % denominator =
*             participants with a non-missing baseline category in that period.
*             Single-/fixed-sequence design -> one panel per PERIOD
*             (APERIOD/APERIODC): Period 1 (Reference, victim alone) and
*             Period 2 (Test, victim + perpetrator). Baseline and worst value
*             are taken WITHIN each period (no pooling across periods). NO
*             randomized sequence; every participant follows the same fixed order.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA TRTNVAR=TRTAN BYPERIOD=APERIOD APERIODC SEQVAR=(none) */

/* analysis records: Safety pop, records contributing to shift analysis      */
/* same analyte list as the R twin                                           */
data lb;
  set adam.adlb(where=(SAFFL='Y' and ANL01FL='Y' and not missing(APERIOD)
                       and not missing(BNRIND) and not missing(ANRIND)
                       and PARAMCD in ('ALT','AST','BILI','ALP','CREAT','K','NA','HGB','WBC','PLAT')));
  /* order categories LOW < NORMAL < HIGH (numeric rank for sort/worst)       */
  bn = whichc(upcase(BNRIND),'LOW','NORMAL','HIGH');   /* baseline rank       */
  an = whichc(upcase(ANRIND),'LOW','NORMAL','HIGH');   /* postbaseline rank   */
  /* Period taken straight from ADaM - no re-derivation                       */
run;

/*--- worst post-baseline category per participant/period/parameter ------------*
* Single-sequence: CLASS carries the PERIOD (&BYPERIOD) so the worst category *
* is taken WITHIN each period the participant was observed in (not pooled across  *
* periods). "worst" = furthest from NORMAL. Rank by distance from NORMAL      *
* (dist=|an-2|), so both LOW (an=1) and HIGH (an=3) outrank NORMAL (an=2).    *
* Take the max distance per participant, then resolve direction below NORMAL ->   *
* LOW, above -> HIGH.                                                         */
data lb;
  set lb;
  dist = abs(an - 2);                 /* distance from NORMAL (LOW/HIGH = 1)   */
  sdist = (an - 2);                   /* signed: <0 below NORMAL, >0 above     */
run;
proc means data=lb nway noprint;
  class USUBJID &BYPERIOD PARAMCD PARAM BNRIND bn;
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

/*--- denominator: participants with non-missing baseline category, per period --*/
proc sql;
  create table _den as
    select APERIOD, APERIODC, PARAMCD, count(distinct USUBJID) as Nbase
    from _worst group by APERIOD, APERIODC, PARAMCD;
quit;

/*--- shift counts: distinct participants per baseline x worst-postbaseline cell */
proc sql;
  create table _shift as
    select APERIOD, APERIODC, PARAMCD, PARAM, BNRIND, bn, ANRIND_W,
           count(distinct USUBJID) as nsubj
    from _worst
    group by APERIOD, APERIODC, PARAMCD, PARAM, BNRIND, bn, ANRIND_W;
quit;
/* merge Nbase by period+param -> pct = nsubj/Nbase*100 ; value = "n (xx.x%)" */

proc sort data=_shift; by PARAMCD PARAM APERIOD APERIODC bn BNRIND; run;
proc transpose data=_shift out=_wide;
  by PARAMCD PARAM APERIOD APERIODC bn BNRIND;
  id ANRIND_W; var nsubj;          /* columns = worst Low / Normal / High     */
run;

%tfltitle(num=14.3.4.2, type=Table,
   text=%str(Shift from Baseline to Worst Post-Baseline Normal Range Category by Laboratory Parameter and Period),
   pop=Safety Population,
   foot=%str(Rows = within-period baseline category (BNRIND); columns = worst post-baseline category. Counts = participants with a non-missing baseline category. % = n / participants with baseline category in period. One panel per study period (Period 1 = reference, victim alone; Period 2 = test, victim + perpetrator). Same fixed sequence for all participants.));
proc report data=_wide nowd split='|';
  columns PARAM APERIODC BNRIND ('Worst Post-Baseline Category' Low Normal High);
  define PARAM    / order 'Laboratory|Parameter' width=24 flow;
  define APERIODC / order 'Study Period' width=18;    /* panel per period     */
  define BNRIND   / order 'Baseline|Category'    width=12;
  define Low      / display 'Low'    center width=12;
  define Normal   / display 'Normal' center width=12;
  define High     / display 'High'   center width=12;
  break after APERIODC / skip;
run;
