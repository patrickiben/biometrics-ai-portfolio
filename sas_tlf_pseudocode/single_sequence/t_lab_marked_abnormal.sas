/******************************************************************************
* TABLE     : t_lab_marked_abnormal  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Treatment-Emergent Markedly Abnormal Laboratory Values by
*             Parameter and Period
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, ATOXGR/ATOXGRN, ATOXGRH/ATOXGRL,
*             BTOXGR/BTOXGRN, ANRIND, ONTRTFL, APERIOD/APERIODC)
* NOTE      : PSEUDOCODE. "Markedly abnormal" = treatment-emergent CTCAE
*             Grade >=3 (or marked Low/High per protocol). Counts = PARTICIPANTS
*             (distinct USUBJID) with >=1 qualifying post-baseline value.
*             Single-/fixed-sequence design: columns = PERIOD (APERIOD/APERIODC)
*             - Period 1 (Reference, victim alone) | Period 2 (Test, victim +
*             perpetrator). A participant may appear under each period received.
*             Treatment-emergent worsening assessed relative to the WITHIN-PERIOD
*             baseline grade (post > baseline).
*             % denominator = participants DOSED/evaluable in that period.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA TRTNVAR=TRTAN BYPERIOD=APERIOD APERIODC SEQVAR=(none) */

/*--- per-PERIOD column denominators: participants evaluable in each period -----
* The period IS the column. Build N by APERIODC from ADSL/ADLB (a participant with
* an on-treatment record in the period contributes to that period's N), + Total */
proc sql noprint;
  create table _bign as
    select APERIOD as trtn, APERIODC as trt length=200,
           count(distinct USUBJID) as N
    from adam.adlb where SAFFL='Y' and ONTRTFL='Y' group by APERIOD, APERIODC;
quit;

/*--- post-baseline records with a gradable toxicity ----------------------*/
data lb;
  set adam.adlb(where=(SAFFL='Y' and ONTRTFL='Y'
                       and not missing(ATOXGRN) and not missing(APERIOD)));
  /* treatment-emergent worsening: post-baseline grade > within-period baseline */
  if missing(BTOXGRN) then BTOXGRN = 0;
  teae_marked = (ATOXGRN >= 3 and ATOXGRN > BTOXGRN);   /* Grade >=3 emergent */
  /* direction (Low/High) from directional toxicity grades (ATOXGRH/ATOXGRL),  */
  /* falling back to ANRIND -- identical derivation to the R twin              */
  length dir $4;
  if      (not missing(ATOXGRH) and ATOXGRH >= 3) then dir = 'High';
  else if (not missing(ATOXGRL) and ATOXGRL >= 3) then dir = 'Low';
  else if index(upcase(ANRIND),'HIGH') then dir = 'High';
  else if index(upcase(ANRIND),'LOW')  then dir = 'Low';
  else dir = ' ';
run;

/*--- participants with >=1 treatment-emergent markedly-abnormal value, by period */
proc sql;
  create table _mark as
    select APERIOD, APERIODC, PARAMCD, PARAM, dir,
           count(distinct USUBJID) as nsubj
    from lb where teae_marked=1 and dir ne ' '
    group by APERIOD, APERIODC, PARAMCD, PARAM, dir;
quit;
/* merge _bign on APERIOD -> pct = nsubj/N*100 ; value = "n (xx.x%)"          */

/*--- denominator note: participants with >=1 evaluable post-baseline value -----*/
proc sql;
  create table _eval as
    select APERIOD, PARAMCD, count(distinct USUBJID) as Neval
    from lb group by APERIOD, PARAMCD;
quit;

proc sort data=_mark; by PARAMCD PARAM dir APERIOD; run;
proc transpose data=_mark out=_wide;
  by PARAMCD PARAM dir;            /* one column per period                    */
  id APERIOD; var nsubj;
run;

%tfltitle(num=14.3.4.3, type=Table,
   text=%str(Treatment-Emergent Markedly Abnormal Laboratory Values by Parameter and Period),
   pop=Safety Population,
   foot=%str(Markedly abnormal = treatment-emergent CTCAE Grade >=3 (post-baseline grade worse than within-period baseline). A participant counted once per parameter/direction within period. Columns = Period 1 (reference, victim alone), Period 2 (test, victim + perpetrator). A participant may contribute to both period columns. % = participants / N evaluable in period.));
proc report data=_wide nowd split='|';
  columns PARAM dir ("Study Period" /* Period1 | Period2 */);
  define PARAM / order 'Laboratory Parameter' width=28 flow;
  define dir   / display 'Direction' width=10;        /* Low / High           */
  break after PARAM / skip;
run;
