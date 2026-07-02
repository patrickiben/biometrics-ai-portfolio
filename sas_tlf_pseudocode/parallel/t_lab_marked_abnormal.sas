/******************************************************************************
* TABLE     : t_lab_marked_abnormal  (Parallel-group)
* TITLE     : Treatment-Emergent Markedly Abnormal Laboratory Values by
*             Parameter
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, ATOXGR/ATOXGRN, BTOXGR/BTOXGRN, ANRIND,
*             ONTRTFL)
* NOTE      : PSEUDOCODE. "Markedly abnormal" = treatment-emergent CTCAE
*             Grade >=3 (post-baseline grade worse than baseline grade).
*             Counts = PARTICIPANTS (distinct USUBJID) with >=1 qualifying
*             post-baseline value per analyte. % denominator = SAFFL N per arm
*             (from %bign). Per parameter three criterion rows are reported:
*             Any Markedly Abnormal, Markedly High, Markedly Low. Direction
*             (High/Low) from ANRIND; "Any" counts all qualifying records
*             regardless of direction. Columns = treatment arms + Total.
*             Parallel design: column = TRT01A.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);          /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN  */

/* column denominators (N=) per arm + Total (Safety Population) */
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/*--- post-baseline records with a gradable toxicity ----------------------*/
%let analytes = 'ALT' 'AST' 'BILI' 'ALP' 'CREAT' 'K' 'NA' 'HGB' 'WBC' 'PLAT' 'GLUC';
data lb;
  set adam.adlb(where=(SAFFL='Y' and ONTRTFL='Y' and not missing(ATOXGRN)
                       and PARAMCD in (&analytes)));
  /* treatment-emergent worsening: post-baseline grade > baseline grade       */
  if missing(BTOXGRN) then BTOXGRN = 0;
  teae_marked = (ATOXGRN >= 3 and ATOXGRN > BTOXGRN);   /* Grade >=3 emergent */
  /* direction (High/Low) carried for the directional criterion rows          */
  mhi = (teae_marked and index(upcase(ANRIND),'HIGH'));   /* marked High      */
  mlo = (teae_marked and index(upcase(ANRIND),'LOW'));    /* marked Low       */
run;

/*--- distinct participants per criterion, per parameter x arm -----------------*/
/* Any Markedly Abnormal = any qualifying record (direction-agnostic);          *
* Markedly High / Markedly Low = directional splits via ANRIND.                */
proc sql;
  create table _crit as
    select &TRTVAR, &TRTNVAR, PARAMCD, PARAM,
           count(distinct case when teae_marked=1 then USUBJID end) as Any_Markedly_Abnormal,
           count(distinct case when mhi=1         then USUBJID end) as Markedly_High,
           count(distinct case when mlo=1         then USUBJID end) as Markedly_Low
    from lb
    group by &TRTVAR, &TRTNVAR, PARAMCD, PARAM
  union all  /* Total column: distinct across arms (participant counted once)   */
    select 'Total' as &TRTVAR length=200, 9999 as &TRTNVAR, PARAMCD, PARAM,
           count(distinct case when teae_marked=1 then USUBJID end) as Any_Markedly_Abnormal,
           count(distinct case when mhi=1         then USUBJID end) as Markedly_High,
           count(distinct case when mlo=1         then USUBJID end) as Markedly_Low
    from lb
    group by PARAMCD, PARAM;
quit;

/*--- denominator note: participants with >=1 evaluable post-baseline value -----*/
proc sql;
  create table _eval as
    select &TRTNVAR, PARAMCD, count(distinct USUBJID) as Neval
    from lb group by &TRTNVAR, PARAMCD;
quit;

/*--- stack the three criterion rows long; one row per param x criterion x arm --*/
data _long;
  set _crit;
  length criterion $24;  cord = .;
  criterion='Any Markedly Abnormal'; nsubj=Any_Markedly_Abnormal; cord=1; output;
  criterion='Markedly High';         nsubj=Markedly_High;         cord=2; output;
  criterion='Markedly Low';          nsubj=Markedly_Low;          cord=3; output;
  keep &TRTVAR &TRTNVAR PARAMCD PARAM criterion cord nsubj;
run;
/* merge _bign on &TRTNVAR (incl. Total=9999) -> pct = nsubj/N*100 ;            *
* value = "n (xx.x%)". The merged value table now carries arm cols AND Total.  */

proc sort data=_long; by PARAMCD PARAM cord criterion &TRTNVAR; run;
proc transpose data=_long out=_wide;
  by PARAMCD PARAM cord criterion;   /* one column per arm + Total (9999)       */
  id &TRTNVAR; var nsubj;
run;

%tfltitle(num=14.3.4.3, type=Table,
   text=%str(Treatment-Emergent Markedly Abnormal Laboratory Values by Parameter),
   pop=Safety Population,
   foot=%str(Markedly abnormal = treatment-emergent CTCAE Grade >=3 (post-baseline grade worse than baseline). Markedly High/Low from ANRIND direction; Any = any qualifying record. A participant counted once per criterion per parameter. % = participants / N in arm.));
proc report data=_wide nowd split='|';
  columns PARAM cord criterion ("Treatment Arm" /* arm cols + Total */);
  define PARAM     / order 'Laboratory Parameter' width=28 flow;
  define cord      / order noprint;                   /* criterion sort key     */
  define criterion / display 'Criterion' width=22;    /* Any / High / Low       */
  break after PARAM / skip;
run;
