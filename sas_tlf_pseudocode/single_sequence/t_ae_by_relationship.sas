/******************************************************************************
* TABLE     : t_ae_by_relationship  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Treatment-Emergent Adverse Events Related to Study Drug by
*             System Organ Class and Preferred Term, by Period
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (TRTEMFL='Y'); relationship from AREL
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS (distinct USUBJID), drug-related
*             TEAEs only. Related = AREL in (RELATED/POSSIBLE/PROBABLE/DEFINITE)
*             per the analysis relationship variable. Columns = fixed PERIODS
*             via APERIOD/APERIODC (Period 1 = victim alone [reference], later =
*             victim + perpetrator); NO randomized sequence. % denominator =
*             Safety N exposed per period.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA; BYPERIOD=APERIOD APERIODC */

/* column denominators = participants exposed in each PERIOD. APERIOD/APERIODC are
* BDS per-record vars (not on ADSL), so the per-period denominator is built from
* the period-bearing source ADEX (mirror t_exposure.sas): participants dosed in the
* period, plus a Total column.                                              */
proc sql noprint;
  create table _bign as
    select APERIOD as trtn, APERIODC as trt length=200,
           count(distinct USUBJID) as N
    from adam.adex where SAFFL='Y' group by APERIOD, APERIODC
  union all
    select 9999 as trtn, 'Total' as trt, count(distinct USUBJID) as N
    from adam.adex where SAFFL='Y';
quit;

/* treatment-emergent AND drug-related, Safety population                    */
data adae;
  set adam.adae(where=(TRTEMFL='Y' and SAFFL='Y'
                       and AREL in ('RELATED','POSSIBLE','PROBABLE','DEFINITE')));
run;

/*--- Any related TEAE overall row (distinct participants), per period ---------*/
%aecount(ds=adae, trtvar=APERIODC, popden=_bign, where=%str(TRTEMFL='Y'),
         byvars=%str(_dummy), out=_any);

/*--- by SOC (distinct participants), per period ------------------------------*/
%aecount(ds=adae, trtvar=APERIODC, popden=_bign, byvars=%str(AESOC), out=_soc);

/*--- by SOC*PT (distinct participants), per period ---------------------------*/
%aecount(ds=adae, trtvar=APERIODC, popden=_bign, byvars=%str(AESOC AEDECOD), out=_socpt);

/*--- ordering: SOC by overall (pooled) participant count desc; PT within SOC --*
* %aecount emits no trt='Total' row, so sum nsubj across all period rows.    */
proc sql;
  create table _socord as
    select AESOC, sum(nsubj) as socn from _soc group by AESOC;
  create table _ptord as
    select AESOC, AEDECOD, sum(nsubj) as ptn from _socpt
    group by AESOC, AEDECOD;
quit;

data _rep;
  set _any(in=a) _soc(in=s) _socpt(in=p);
  length term $200;
  if a then do; term='Participants with any related TEAE'; level=0; end;
  else if s then do; term=AESOC;                       level=1; end;
  else do; term='   '||AEDECOD;                         level=2; end;
  /* value = catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)'))   */
run;
proc transpose data=_rep out=_wide; by socn ptn level term; id APERIOD; var value; run;

%tfltitle(num=14.3.1.4, type=Table,
   text=%str(Drug-Related Treatment-Emergent Adverse Events by System Organ Class and Preferred Term, by Period),
   pop=Safety Population,
   foot=%str(Related = analysis relationship (AREL) of related/possible/probable/definite. A participant is counted once at each level per period. Period 1 = reference; later period(s) = test condition. % = participants / N exposed in the period. MedDRA v27.0.));
proc report data=_wide nowd split='|';
  columns socn ptn level term ("By Period" /* period cols: P1=Reference, P2=Test... */);
  define socn  / order descending noprint;
  define ptn   / order descending noprint;
  define term  / order 'System Organ Class|  Preferred Term' width=40 flow;
run;
