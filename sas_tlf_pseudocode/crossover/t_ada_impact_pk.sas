/******************************************************************************
* TABLE     : t_ada_impact_pk  (Crossover - 2x2 or Williams)
* TITLE     : Impact of Anti-Drug Antibody (ADA) Status on Plasma PK Exposure
*             by Treatment
* POPULATION: PK Parameter Population (PKFL='Y') with ADA-evaluable status
* INPUT     : ADPP (PARAMCD = CMAX, AUCLST, AUCIFO) merged to participant-level
*             ADA status from ADIS (TEADAFL / ADAPOSFL); TRTA/TRTAN,
*             APERIOD/APERIODC, TRTSEQP from ADaM
* NOTE      : PSEUDOCODE. Exposure summarized by ADA status WITHIN each
*             analysis treatment (TRTA), so a within-study reader can see
*             whether immunogenicity attenuated exposure for Test vs Reference.
*             ADA status is matched PER TREATMENT/PERIOD (a participant may be ADA
*             positive under one treatment and negative under another).
*             Report PK arithmetic n, Geo Mean, Geo CV% (and arithmetic
*             Mean (SD)) by ADA-positive vs ADA-negative within each treatment.
*             Tmax (if shown) = Median (Min, Max) only. Descriptive subgroup
*             summary (formal Test-vs-Reference contrast = t_be_anova).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTVAR=TRTA + APERIOD/APERIODC + TRTSEQP */

/*--- participant x treatment(x period) ADA status from ADIS (no re-derivation) */
proc sql;
  create table _adast as
    select distinct USUBJID, &TRTVAR, &TRTNVAR, APERIOD,
           max(case when TEADAFL='Y' then 1 else 0 end) as teada
    from adam.adis
    where ISEVALFL='Y' and PARCAT1='ADA'
    group by USUBJID, &TRTVAR, &TRTNVAR, APERIOD;
quit;

/*--- merge ADA status onto the matching ADPP record (same treatment+period) */
proc sql;
  create table pp as
    select p.*, coalesce(a.teada,.) as teada,
           case when a.teada=1 then 'ADA positive'
                when a.teada=0 then 'ADA negative'
                else 'ADA status unknown' end as adagrp length=20
    from adam.adpp(where=(PKFL='Y' and PARAMCD in ('CMAX','AUCLST','AUCIFO')
                          and AVAL>0)) as p
    left join _adast as a
      on p.USUBJID=a.USUBJID and p.&TRTNVAR=a.&TRTNVAR and p.APERIOD=a.APERIOD;
quit;

/*--- PK arithmetic + geometric summary by treatment x ADA group x param --*
* Reuse %pkstats: class drives treatment, ADA subgroup, and parameter. The  *
* geometric stats are the headline for exposure; arithmetic shown alongside.*/
%pkstats(ds=pp, var=AVAL, class=&TRTVAR &TRTNVAR adagrp PARAMCD PARAM,
         where=%str(1), out=_pk);

data _stat; set _pk;
  if missing(PARAMCD) or missing(adagrp) then delete;   /* drop marginals    */
  length stat $20 value $30;
  /* build display rows per treatment x ADA group x parameter:
     'n'            = put(n,5.)
     'Geo Mean'     = put(geomean, 8.3)
     'Geo CV%'      = put(geocv,   6.1)
     'Mean (SD)'    = catx(' ', put(amean,8.3), cats('(',put(asd,8.3),')'))
     'Median'       = put(med,8.3)
     'Min, Max'     = catx(', ', put(min,8.3), put(max,8.3))                 */
run;

proc sort data=_stat; by PARAM PARAMCD &TRTNVAR adagrp stat; run;
proc transpose data=_stat out=_wide; by PARAM PARAMCD &TRTNVAR;
  id adagrp; var value;   /* columns = ADA negative / ADA positive (within trt) */
run;

%tfltitle(num=14.5.2.1, type=Table,
   text=%str(Impact of Anti-Drug Antibody (ADA) Status on Plasma PK Exposure by Treatment),
   pop=Pharmacokinetic Parameter Population (ADA-evaluable),
   foot=%str(Exposure by ADA-positive vs ADA-negative WITHIN each analysis treatment (crossover; ADA status matched per treatment/period). Geo Mean / Geo CV% are the headline; arithmetic Mean (SD) shown alongside. Geometric stats undefined if AVAL<=0 (excluded). Descriptive subgroup summary; formal Test-vs-Reference comparison in t_be_anova.));
proc report data=_wide nowd split='|';
  columns PARAM PARAMCD &TRTNVAR stat ("ADA Status" /* ADA neg / ADA pos cols */);
  define PARAM    / order 'PK Parameter (units)' width=24 flow;
  define PARAMCD  / order noprint;
  define &TRTNVAR / order 'Treatment' width=16;
  define stat     / display 'Statistic' width=12;
  /* define <ADA negative> / display center 'ADA Negative (n=..)';
     define <ADA positive> / display center 'ADA Positive (n=..)';          */
  break after PARAM / skip;
run;
