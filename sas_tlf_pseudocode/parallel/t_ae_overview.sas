/******************************************************************************
* TABLE     : t_ae_overview  (Parallel-group)
* TITLE     : Overview of Treatment-Emergent Adverse Events
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (TRTEMFL='Y' for emergent categories)
* NOTE      : PSEUDOCODE. One row per AE category (any TEAE, related TEAE,
*             serious TEAE, severe TEAE, TEAE leading to discontinuation,
*             TEAE leading to dose modification, TEAE leading to death).
*             Counts = PARTICIPANTS with >=1 qualifying event (distinct USUBJID),
*             NOT event rows. n (%) per arm; % denominator = SAFFL N per arm.
*             Parallel design: column var = TRT01A/TRT01AN (= dose level).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);                 /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

/* column denominators (N=) per arm + Total */
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/* treatment-emergent records from the Safety population                       */
data adae; set adam.adae(where=(TRTEMFL='Y' and SAFFL='Y'));
  length relfl serfl sevfl dcfl modfl dthfl 3;
  relfl = (upcase(AREL) in ('RELATED','POSSIBLE','PROBABLE','DEFINITE'));  /* related to study drug */
  serfl = (AESER='Y');                                   /* serious                 */
  sevfl = (AESEVN=3 or upcase(ASEV)='SEVERE');           /* severe (max grade)      */
  dcfl  = (upcase(AEACN)='DRUG WITHDRAWN');              /* led to discontinuation  */
  modfl = (upcase(AEACN) in ('DOSE REDUCED','DRUG INTERRUPTED'));  /* dose modification */
  dthfl = (AESDTH='Y' or upcase(AEOUT)='FATAL');         /* led to death            */
run;

/*--- participant-level counts per AE category, per arm ----------------------------
* Each category = distinct USUBJID with >=1 event meeting the flag, per column. */
%macro aecat(where=, label=, ord=);
  proc sql;
    create table _c&ord as
      select &TRTVAR as trt length=200, &TRTNVAR as trtn,
             count(distinct USUBJID) as nsubj
      from adae where &where group by &TRTVAR, &TRTNVAR
    union all  /* Total column */
      select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as nsubj
      from adae where &where;
  quit;
  data _c&ord; set _c&ord; length catlbl $60; catlbl="&label"; ord=&ord; run;
%mend aecat;

%aecat(where=%str(1),       label=%str(Participants with any TEAE),                         ord=1);
%aecat(where=%str(relfl=1), label=%str(Participants with drug-related TEAE),                ord=2);
%aecat(where=%str(serfl=1), label=%str(Participants with serious TEAE),                     ord=3);
%aecat(where=%str(serfl=1 and relfl=1), label=%str(Participants with drug-related serious TEAE), ord=4);
%aecat(where=%str(sevfl=1), label=%str(Participants with severe TEAE),                      ord=5);
%aecat(where=%str(dcfl=1),  label=%str(Participants with TEAE leading to discontinuation),  ord=6);
%aecat(where=%str(modfl=1), label=%str(Participants with TEAE leading to dose modification),ord=7);
%aecat(where=%str(dthfl=1), label=%str(Participants with TEAE leading to death),            ord=8);

/*--- stack categories, attach denominators, build n (%) -----------------------*/
data _all; set _c1-_c8; run;
proc sql;
  create table _rep as
    select a.ord, a.catlbl, a.trtn, a.nsubj, b.N,
           catx(' ', put(a.nsubj,4.),
                cats('(', put(100*a.nsubj/b.N, 5.1), '%)')) as value length=40
    from _all a left join _bign b on a.trtn=b.trtn
    order by a.ord, a.trtn;
quit;

/*--- one column per treatment (dose) + Total ----------------------------------*/
proc transpose data=_rep out=_wide; by ord catlbl; id trtn; var value; run;

%tfltitle(num=14.3.1, type=Table,
   text=%str(Overview of Treatment-Emergent Adverse Events),
   pop=Safety Population,
   foot=%str(TEAE = treatment-emergent AE (TRTEMFL='Y'). A participant is counted once in each category. % = participants with the event / N in arm. MedDRA v27.0.));
proc report data=_wide nowd split='|';
  columns ord catlbl ("Treatment (Dose)" /* dose cols + Total */);
  define ord    / order noprint;
  define catlbl / order 'Adverse Event Category' width=42 flow;
  /* define <each TRT01AN col> / display center "&header (N=&n)"; */
run;
