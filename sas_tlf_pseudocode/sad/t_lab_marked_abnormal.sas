/******************************************************************************
* TABLE     : t_lab_marked_abnormal  (Single Ascending Dose)
* TITLE     : Treatment-Emergent Markedly Abnormal Laboratory Values by
*             Parameter
* POPULATION: Safety Population (SAFFL='Y'), on-treatment evaluable
* INPUT     : ADLB (PARAM/PARAMCD, ATOXGR/ATOXGRN, BTOXGRN, ANRIND,
*             ATOXGRH/ATOXGRL, ONTRTFL)
* NOTE      : PSEUDOCODE. "Markedly abnormal" = treatment-emergent CTCAE
*             Grade >=3 (or marked Low/High per protocol). Counts = PARTICIPANTS
*             (distinct USUBJID) with >=1 qualifying post-baseline value.
*             % denominator = on-treatment evaluable N from ADLB (SAFFL='Y' and
*             ONTRTFL='Y', distinct USUBJID) per dose level.
*             Treatment-emergent = post-baseline grade worse than baseline.
*             SAD design: column = TRT01A (ascending dose level), placebo
*             pooled across cohorts; single dose so "on-treatment" =
*             post-single-dose follow-up window (ONTRTFL).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN  */

/* column denominators (N=) per dose level + pooled placebo + Total :          *
 * on-treatment evaluable N from ADLB (SAFFL='Y' and ONTRTFL='Y', distinct      *
 * USUBJID) -- the denominator for a markedly-abnormal lab read-out is          *
 * participants with an evaluable on-treatment lab, not the full ADSL SAFFL N.  */
proc sql;
  create table _bign as
    select &TRTVAR as trt length=200, &TRTNVAR as trtn,
           count(distinct USUBJID) as N
    from adam.adlb where SAFFL='Y' and ONTRTFL='Y'
    group by &TRTVAR, &TRTNVAR
  union all
    select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as N
    from adam.adlb where SAFFL='Y' and ONTRTFL='Y';
quit;

/*--- post-baseline records with a gradable toxicity ----------------------*/
data lb;
  set adam.adlb(where=(SAFFL='Y' and ONTRTFL='Y' and not missing(ATOXGRN)));
  /* treatment-emergent worsening: post-baseline grade > baseline grade       */
  if missing(BTOXGRN) then BTOXGRN = 0;
  teae_marked = (ATOXGRN >= 3 and ATOXGRN > BTOXGRN);   /* Grade >=3 emergent */
  /* direction (Low/High) from directional grade (ATOXGRH/ATOXGRL) then ANRIND  */
  length dir $4;
  if not missing(ATOXGRH) and ATOXGRH >= 3 then dir = 'High';
  else if not missing(ATOXGRL) and ATOXGRL >= 3 then dir = 'Low';
  else if index(upcase(ANRIND),'HIGH') then dir = 'High';
  else if index(upcase(ANRIND),'LOW')  then dir = 'Low';
  else dir = ' ';
run;

/*--- participants with >=1 treatment-emergent markedly-abnormal value ---------*
* Counts = DISTINCT USUBJID (participants), not records, per dose level + Total.  *
* A participant counts once per parameter/direction.                          */
proc sql;
  create table _mark as
    select &TRTVAR as trt length=200, &TRTNVAR as trtn,
           PARAMCD, PARAM, dir,
           count(distinct USUBJID) as nsubj
    from lb where teae_marked=1
    group by &TRTVAR, &TRTNVAR, PARAMCD, PARAM, dir
  union all  /* Total column: distinct across all dose levels (participant once) */
    select 'Total' as trt, 9999 as trtn, PARAMCD, PARAM, dir,
           count(distinct USUBJID) as nsubj
    from lb where teae_marked=1 group by PARAMCD, PARAM, dir;
quit;
/* merge _bign by trtn -> pct = nsubj/N*100 ; value = "n (xx.x%)"            */

proc sort data=_mark; by PARAMCD PARAM dir trtn; run;
proc transpose data=_mark out=_wide;
  by PARAMCD PARAM dir;            /* one column per dose level + Total       */
  id trtn; var nsubj;
run;

%tfltitle(num=14.3.4.3, type=Table,
   text=%str(Treatment-Emergent Markedly Abnormal Laboratory Values by Parameter),
   pop=Safety Population,
   foot=%str(Markedly abnormal = treatment-emergent CTCAE Grade >=3 (post-baseline grade worse than baseline). A participant counted once per parameter/direction. Columns = ascending dose levels (TRT01A); placebo pooled. % = participants / on-treatment evaluable N in dose level.));
proc report data=_wide nowd split='|';
  columns PARAM dir ("Dose Level" /* dose cols + Total */);
  define PARAM / order 'Laboratory Parameter' width=28 flow;
  define dir   / display 'Direction' width=10;        /* Low / High           */
  break after PARAM / skip;
run;
