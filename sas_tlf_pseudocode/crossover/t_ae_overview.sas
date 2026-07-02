/******************************************************************************
* TABLE     : t_ae_overview  (Crossover - 2x2 or Williams)
* TITLE     : Overview of Treatment-Emergent Adverse Events
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (TRTEMFL='Y'), ADSL (column denominators)
* NOTE      : PSEUDOCODE. Crossover -> AE attributed to the treatment on at
*             the time of onset (TRTA); columns = each analysis treatment + a
*             Total column. Counts = PARTICIPANTS with >=1 event (distinct USUBJID),
*             NOT event rows. % denominator = SAFFL N per column (from %bign).
*             A participant may contribute to >1 treatment column (within-participant).
*             OPTIONAL by-period view: add APERIODC to the &TRTVAR class spine.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);            /* TRTVAR=TRTA TRTNVAR=TRTAN
                                             BYPERIOD=APERIOD APERIODC
                                             SEQVAR=TRTSEQP                  */

/* Column denominators: distinct participants exposed to each analysis treatment.
   In a crossover, ADSL header N per arm is not meaningful (everyone gets all
   treatments) -> derive the per-treatment safety N from exposure (ADEX) or
   the per-treatment ADAE/ADSL link. Here we count distinct participants per TRTA. */
proc sql;
  create table _bign as
    select TRTA as trt length=200, TRTAN as trtn, count(distinct USUBJID) as N
      from adam.adex where SAFFL='Y'
      group by TRTA, TRTAN
    union all
    select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as N
      from adam.adex where SAFFL='Y';
quit;

/* treatment-emergent only; keep Safety population events                     */
data adae; set adam.adae(where=(TRTEMFL='Y' and SAFFL='Y')); run;

/*--- category-level participant counts (distinct USUBJID per &TRTVAR) ----------*/
%macro ovrow(label=, where=, out=);
  proc sql;
    create table &out as
      select &TRTVAR as trt length=200, &TRTNVAR as trtn,
             count(distinct USUBJID) as nsubj
      from adae where %unquote(&where)
      group by &TRTVAR, &TRTNVAR
    union all
      select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as nsubj
      from adae where %unquote(&where);
  quit;
  data &out; set &out; length term $60; term="&label"; run;
%mend;

%ovrow(label=%str(Participants with any TEAE),            where=%str(TRTEMFL='Y'),                 out=_any);
%ovrow(label=%str(Participants with any related TEAE),    where=%str(TRTEMFL='Y' and upcase(AREL) in ('RELATED','POSSIBLE','PROBABLE','DEFINITE')), out=_rel);
%ovrow(label=%str(Participants with any severe TEAE),     where=%str(TRTEMFL='Y' and AESEVN=3),    out=_sev);
%ovrow(label=%str(Participants with any serious TEAE),    where=%str(TRTEMFL='Y' and AESER='Y'),   out=_ser);
%ovrow(label=%str(Participants with TEAE leading to discontinuation), where=%str(TRTEMFL='Y' and AEACN='DRUG WITHDRAWN'), out=_dsc);
%ovrow(label=%str(Participants with TEAE leading to death), where=%str(TRTEMFL='Y' and AESDTH='Y'), out=_dth);

/*--- stack rows; merge denominator; format n (xx.x%) ----------------------*/
data _rep;
  set _any(in=a) _rel _sev _ser _dsc _dth;
  ord = a + 2*(_n_);                  /* preserve insertion order            */
run;
proc sql;
  create table _repn as
    select r.*, b.N
      from _rep r left join _bign b
      on r.trtn=b.trtn;
quit;
data _repn; set _repn;
  length value $20;
  if N>0 then value = catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)'));
  else        value = put(nsubj,4.);
run;

proc sort data=_repn; by ord term; run;
proc transpose data=_repn out=_wide(drop=_name_); by ord term; id trtn; var value; run;

%tfltitle(num=14.3.1.1, type=Table,
   text=%str(Overview of Treatment-Emergent Adverse Events),
   pop=Safety Population,
   foot=%str(TEAE attributed to the analysis treatment (TRTA) at onset. A participant is counted once per category per treatment; within-participant crossover -> a participant may appear under more than one treatment. %% = participants / treatment-exposed N. MedDRA v27.0.));
proc report data=_wide nowd split='|';
  columns ord term ("Analysis Treatment| (N exposed)" /* TRTAN cols + Total */);
  define ord  / order noprint;
  define term / display 'Category' width=46 flow;
run;
