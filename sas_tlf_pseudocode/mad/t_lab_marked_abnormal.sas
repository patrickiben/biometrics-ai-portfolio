/******************************************************************************
* TABLE     : t_lab_marked_abnormal  (MAD - Multiple Ascending Dose)
* TITLE     : Treatment-Emergent Markedly Abnormal Laboratory Values
* POPULATION: Safety Population (SAFFL='Y'), on-treatment evaluable
* INPUT     : ADLB (PARAM/PARAMCD, ATOXGRN, BTOXGRN, ATOXGRH, ATOXGRL, ANRIND,
*             ONTRTFL, TRT01A/TRT01AN)
* NOTE      : PSEUDOCODE. Counts PARTICIPANTS (distinct USUBJID) with >=1
*             TREATMENT-EMERGENT markedly abnormal value per parameter, split
*             Low / High. "Markedly abnormal" = treatment-emergent CTCAE Grade >=3:
*             ATOXGRN >= 3 AND ATOXGRN > coalesce(BTOXGRN,0) (post-baseline grade
*             worse than baseline). Direction from ATOXGRH/ATOXGRL (ANRIND fallback).
*             % denominator = on-treatment evaluable N from ADLB (SAFFL='Y' and
*             ONTRTFL='Y', distinct USUBJID) per dose level. MAD: parallel cohorts,
*             one (dose) treatment per participant -> columns = dose level (TRT01A).
*             Repeated dosing -> a participant is counted if ANY on-treatment value
*             across Day 1..Day N qualifies. Fold-of-limit logic NOT used.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);          /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN (= dose) */

/* on-treatment analysis records; identify treatment-emergent marked values   */
data lb;
  set adam.adlb(where=(SAFFL='Y' and ONTRTFL='Y'));
  length mdir $4;
  /* treatment-emergent CTCAE Grade >= 3 (post-baseline grade worse than baseline) */
  marked = (not missing(ATOXGRN) and ATOXGRN >= 3
            and ATOXGRN > coalesce(BTOXGRN, 0));
  /* direction from CTCAE high/low grade vars; ANRIND fallback                  */
       if not missing(ATOXGRH) and ATOXGRH >= 3 then mdir='High';
  else if not missing(ATOXGRL) and ATOXGRL >= 3 then mdir='Low';
  else mdir = ifc(upcase(ANRIND)='HIGH','High','Low');
  if marked;                          /* keep only treatment-emergent marked records */
  /* Treatment (= dose level) taken straight from ADaM - no re-derivation       */
run;

/* column denominators (N=) per dose level + Total : on-treatment evaluable N  *
 * from ADLB (SAFFL='Y' and ONTRTFL='Y', distinct USUBJID).                     */
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

/*--- participants with >=1 marked value, per dose x parameter x direction -------*
* Counts = DISTINCT USUBJID (participants), not records. CLASS carries &TRTVAR    *
* (=TRT01A) so each dose-level cohort is its own column. A participant counts if   *
* any value across the multiple-dose period is marked.                        */
proc sql;
  create table _mark as
    select &TRTVAR as trt length=200, &TRTNVAR as trtn,
           PARAMCD, PARAM, mdir,
           count(distinct USUBJID) as nsubj
    from lb
    group by &TRTVAR, &TRTNVAR, PARAMCD, PARAM, mdir
  union all  /* Total column */
    select 'Total' as trt, 9999 as trtn, PARAMCD, PARAM, mdir,
           count(distinct USUBJID) as nsubj
    from lb group by PARAMCD, PARAM, mdir;
quit;
/* merge _bign by trtn -> pct = nsubj/N*100 ; value = "n (xx.x%)"             */

proc sort data=_mark; by PARAMCD PARAM mdir trtn; run;
proc transpose data=_mark out=_wide;
  by PARAMCD PARAM mdir;
  id trtn; var nsubj;             /* one col per dose level + Total           */
run;

%tfltitle(num=14.3.4.3, type=Table,
   text=%str(Treatment-Emergent Markedly Abnormal Laboratory Values),
   pop=Safety Population,
   foot=%str(Counts = participants (distinct USUBJID) with at least one treatment-emergent markedly abnormal value over the multiple-dose period. Marked = treatment-emergent CTCAE Grade >= 3 (ATOXGRN >= 3 and ATOXGRN > baseline grade). Direction from ATOXGRH/ATOXGRL (ANRIND fallback). Denominator = on-treatment evaluable N (SAFFL='Y' and ONTRTFL='Y', distinct USUBJID) per dose level (MAD; one dose per participant).));
proc report data=_wide nowd split='|';
  columns PARAM mdir ("Dose Level" /* dose cols + Total */);
  define PARAM / order 'Laboratory|Parameter' width=24 flow;
  define mdir  / display 'Direction'           width=10;   /* Low / High      */
  /* define <each dose-level var> / display center "&header (N=&n)";          */
  break after PARAM / skip;
run;
