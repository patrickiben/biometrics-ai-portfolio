/******************************************************************************
* TABLE     : t_ae_by_soc_pt  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Treatment-Emergent Adverse Events by System Organ Class and
*             Preferred Term, by Period
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (TRTEMFL='Y')
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS with >=1 event (distinct USUBJID),
*             NOT event rows. Columns are the fixed PERIODS via APERIOD/APERIODC
*             (Period 1 = victim alone [reference], later period = victim +
*             perpetrator); NO randomized sequence. n (%) per period;
*             % denominator = Safety N exposed per period. SOC sorted by overall
*             frequency desc; PT within SOC desc.
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

/* treatment-emergent only; keep participants from the Safety population         */
data adae; set adam.adae(where=(TRTEMFL='Y' and SAFFL='Y')); run;

/*--- 1) "Any TEAE" overall row (distinct participants, any event), per period -*/
%aecount(ds=adae, trtvar=APERIODC, popden=_bign, where=%str(TRTEMFL='Y'),
         byvars=%str(_dummy), out=_any);   /* _dummy=1 -> overall row        */

/*--- 2) by SOC (distinct participants within SOC), per period ----------------*/
%aecount(ds=adae, trtvar=APERIODC, popden=_bign, byvars=%str(AESOC), out=_soc);

/*--- 3) by SOC*PT (distinct participants within SOC and PT), per period -------*/
%aecount(ds=adae, trtvar=APERIODC, popden=_bign, byvars=%str(AESOC AEDECOD), out=_socpt);

/*--- ordering: SOC by overall participant count desc; PT within SOC desc ------
* "Overall" sort key = nsubj summed across the period rows (%aecount emits no
* trt='Total' row, so sum across all treatment/period rows instead).        */
proc sql;
  create table _socord as
    select AESOC, sum(nsubj) as socn from _soc group by AESOC;
  create table _ptord as
    select AESOC, AEDECOD, sum(nsubj) as ptn from _socpt
    group by AESOC, AEDECOD;
quit;
/* merge socn/ptn back for sort keys; indent PT under SOC (leading spaces)   */

/*--- assemble report shell: Any TEAE -> SOC -> indented PT ---------------*/
data _rep;
  set _any(in=a) _soc(in=s) _socpt(in=p);
  length term $200;
  if a then do; term='Participants with any TEAE'; level=0; end;
  else if s then do; term=AESOC;               level=1; end;
  else do; term='   '||AEDECOD;                 level=2; end;
  /* value = catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)'))   */
run;
proc transpose data=_rep out=_wide; by socn ptn level term; id APERIOD; var value; run;

%tfltitle(num=14.3.1.2, type=Table,
   text=%str(Treatment-Emergent Adverse Events by System Organ Class and Preferred Term, by Period),
   pop=Safety Population,
   foot=%str(A participant is counted once at each level per period. MedDRA v27.0. Period 1 = reference; subsequent period(s) = test condition. % = participants with the event / N exposed in the period.));
proc report data=_wide nowd split='|';
  columns socn ptn level term ("By Period" /* period cols: P1=Reference, P2=Test... */);
  define socn  / order descending noprint;
  define ptn   / order descending noprint;
  define term  / order 'System Organ Class|  Preferred Term' width=40 flow;
run;
