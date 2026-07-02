/******************************************************************************
* TABLE     : t_ae_by_relationship  (Crossover - 2x2 or Williams)
* TITLE     : Treatment-Related Treatment-Emergent Adverse Events by System
*             Organ Class and Preferred Term
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (TRTEMFL='Y'), ADEX (per-treatment exposed N)
* NOTE      : PSEUDOCODE. Related = AREL in (RELATED, POSSIBLY/PROBABLY
*             RELATED) per the analysis relationship variable (no re-derivation).
*             Columns = analysis treatment (TRTA) + Total; counts = distinct
*             USUBJID; % denominator = treatment-exposed N (from %bign on ADEX).
*             Within-participant crossover -> a participant may appear under >1 column.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);            /* TRTVAR=TRTA  TRTNVAR=TRTAN       */

/* per-treatment exposed denominators (crossover)                             */
proc sql;
  create table _bign as
    select TRTA as trt length=200, TRTAN as trtn, count(distinct USUBJID) as N
      from adam.adex where SAFFL='Y' group by TRTA, TRTAN
    union all
    select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as N
      from adam.adex where SAFFL='Y';
quit;

/* treatment-emergent AND related (analysis relationship from ADaM)           */
data adae;
  set adam.adae(where=(TRTEMFL='Y' and SAFFL='Y'
                       and upcase(AREL) in ('RELATED','POSSIBLE','PROBABLE','DEFINITE')));
run;

/*--- 1) "Any related TEAE" overall row ------------------------------------*/
%aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, where=%str(TRTEMFL='Y'),
         byvars=%str(_dummy), out=_any);

/*--- 2) by SOC ; 3) by SOC*PT (distinct participants) -------------------------*/
%aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, byvars=%str(AESOC), out=_soc);
%aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, byvars=%str(AESOC AEDECOD), out=_socpt);

/*--- ordering: SOC by total-column participant count desc; PT within SOC desc --*/
proc sql;
  create table _ord as
    select AESOC, AEDECOD, sum(nsubj) as ordn from _socpt
    group by AESOC, AEDECOD;
quit;

data _rep;
  set _any(in=a) _soc(in=s) _socpt(in=p);
  length term $200;
  if a then do; term='Participants with any related TEAE'; level=0; end;
  else if s then do; term=AESOC;                        level=1; end;
  else do; term='   '||AEDECOD;                          level=2; end;
  /* value = catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)'))     */
run;
proc transpose data=_rep out=_wide; by level term; id &TRTNVAR; var value; run;

%tfltitle(num=14.3.1.4, type=Table,
   text=%str(Treatment-Related Treatment-Emergent Adverse Events by System Organ Class and Preferred Term),
   pop=Safety Population,
   foot=%str(Related = analysis relationship (AREL) of related/possibly/probably related. Events attributed to TRTA at onset; within-participant crossover -> a participant may appear under more than one treatment. A participant is counted once at each level. MedDRA v27.0.));
proc report data=_wide nowd split='|';
  columns level term ("Analysis Treatment" /* TRTAN cols + Total */);
  define level / order noprint;
  define term  / order 'System Organ Class|  Preferred Term' width=40 flow;
run;
