/******************************************************************************
* TABLE     : t_ae_by_severity  (Crossover - 2x2 or Williams)
* TITLE     : Treatment-Emergent Adverse Events by Maximum Severity,
*             System Organ Class and Preferred Term
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (TRTEMFL='Y'), ADEX (per-treatment exposed N)
* NOTE      : PSEUDOCODE. Each participant counted once per SOC/PT at the MAXIMUM
*             severity (ASEV/AESEVN) experienced for that treatment. Columns =
*             analysis treatment (TRTA) + Total; counts = distinct USUBJID;
*             % denominator = treatment-exposed N (from %bign on ADEX).
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

/* treatment-emergent only                                                    */
data adae; set adam.adae(where=(TRTEMFL='Y' and SAFFL='Y')); run;

/*--- reduce to MAX severity per participant * treatment * SOC * PT -------------*/
proc sql;
  create table _maxsev as
    select &TRTVAR as trt length=200, &TRTNVAR as trtn, USUBJID,
           AESOC, AEDECOD, max(AESEVN) as maxsevn
    from adae group by &TRTVAR, &TRTNVAR, USUBJID, AESOC, AEDECOD;
quit;
data _maxsev; set _maxsev;
  length sevcat $12;
  sevcat = put(maxsevn, aesev.);          /* MILD / MODERATE / SEVERE         */
run;

/*--- participant counts by severity category, per treatment, at each level -----
* level 0 = Any TEAE ; 1 = SOC ; 2 = SOC*PT . Distinct USUBJID within cell.   */
%macro sevcount(byvars=, level=, label=, out=);
  proc sql;
    create table &out as
      select trt, trtn, sevcat %if %length(&byvars) %then , &byvars;,
             count(distinct USUBJID) as nsubj
      from _maxsev group by trt, trtn, sevcat %if %length(&byvars) %then , &byvars;
    union all  /* Total column */
      select 'Total' as trt, 9999 as trtn, sevcat
             %if %length(&byvars) %then , &byvars;,
             count(distinct USUBJID) as nsubj
      from _maxsev group by sevcat %if %length(&byvars) %then , &byvars;;
  quit;
  data &out; set &out; length term $200; level=&level;
    %if &level=0 %then term="&label";;
    %if &level=1 %then term=AESOC;;
    %if &level=2 %then term='   '||AEDECOD;;
  run;
%mend;

%sevcount(byvars=%str(),            level=0, label=%str(Participants with any TEAE), out=_any);
%sevcount(byvars=%str(AESOC),       level=1, out=_soc);
%sevcount(byvars=%str(AESOC AEDECOD), level=2, out=_socpt);

data _rep; set _any _soc _socpt;
  /* value = catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)'))
     after merge to _bign on trtn; columns split Mild/Moderate/Severe          */
run;

/* sort SOC by overall freq desc, PT within SOC desc (Total column)           */
proc sql;
  create table _ord as
    select AESOC, AEDECOD, sum(nsubj) as ordn from _socpt where trt='Total'
    group by AESOC, AEDECOD;
quit;

%tfltitle(num=14.3.1.3, type=Table,
   text=%str(Treatment-Emergent Adverse Events by Maximum Severity, System Organ Class and Preferred Term),
   pop=Safety Population,
   foot=%str(A participant is counted once per term at the maximum severity for that treatment. Events attributed to TRTA at onset; within-participant crossover -> a participant may appear under more than one treatment. MedDRA v27.0.));
proc report data=_rep nowd split='|';
  columns level term ('Analysis Treatment' /* TRTAN nested by Mild|Moderate|Severe + Total */);
  define level / order noprint;
  define term  / order 'System Organ Class|  Preferred Term' width=40 flow;
run;
