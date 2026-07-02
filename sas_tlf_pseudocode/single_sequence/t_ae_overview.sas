/******************************************************************************
* TABLE     : t_ae_overview  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Overview of Treatment-Emergent Adverse Events by Period
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (TRTEMFL='Y')
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS with >=1 event (distinct USUBJID),
*             NOT event rows. Columns are the fixed PERIODS (e.g. Period 1 =
*             victim alone [reference], Period 2 = victim + perpetrator), via
*             APERIOD/APERIODC. NO randomized sequence. % denominator = the
*             Safety N exposed in each period (participants dosed in the period,
*             from ADEX where SAFFL='Y'; APERIOD/APERIODC are BDS per-record
*             vars, so the per-period denominator cannot come from ADSL).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA; BYPERIOD=APERIOD APERIODC */

/*--- column denominators = participants exposed in each PERIOD ----------------
* Single-sequence safety is summarized BY PERIOD (fixed order, no sequence),
* so the "column" variable is APERIODC, not the treatment arm. APERIOD/APERIODC
* are BDS per-record vars (not on ADSL), so the per-period denominator is built
* from the period-bearing source ADEX (mirror t_exposure.sas): participants dosed
* in the period contribute to that period's N, plus a Total column.        */
proc sql noprint;
  create table _bign as
    select APERIOD as trtn, APERIODC as trt length=200,
           count(distinct USUBJID) as N
    from adam.adex where SAFFL='Y' group by APERIOD, APERIODC
  union all
    select 9999 as trtn, 'Total' as trt, count(distinct USUBJID) as N
    from adam.adex where SAFFL='Y';
quit;

/* treatment-emergent only; keep Safety-population events                    */
data adae; set adam.adae(where=(TRTEMFL='Y' and SAFFL='Y')); run;

/*--- participant-level event flags within each period (+ Total column) --------
* Each category emits per-period rows plus a Total row (trtn=9999) so the report
* shows period columns AND a Total column, matching the R twin.               */
proc sql;
  /* any TEAE */
  create table _any as
    select APERIODC as trt, APERIOD as trtn, count(distinct USUBJID) as nsubj
    from adae group by APERIODC, APERIOD
  union all
    select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as nsubj from adae;
  /* serious TEAE */
  create table _ser as
    select APERIODC as trt, APERIOD as trtn, count(distinct USUBJID) as nsubj
    from adae where AESER='Y' group by APERIODC, APERIOD
  union all
    select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as nsubj
    from adae where AESER='Y';
  /* drug-related TEAE (analysis relationship) */
  create table _rel as
    select APERIODC as trt, APERIOD as trtn, count(distinct USUBJID) as nsubj
    from adae where AREL in ('RELATED','POSSIBLE','PROBABLE','DEFINITE')
    group by APERIODC, APERIOD
  union all
    select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as nsubj
    from adae where AREL in ('RELATED','POSSIBLE','PROBABLE','DEFINITE');
  /* severe (Grade 3+) TEAE -- AESEVN>=3 to match the R twin */
  create table _sev as
    select APERIODC as trt, APERIOD as trtn, count(distinct USUBJID) as nsubj
    from adae where AESEVN>=3 group by APERIODC, APERIOD
  union all
    select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as nsubj
    from adae where AESEVN>=3;
  /* TEAE leading to study-drug discontinuation */
  create table _dsc as
    select APERIODC as trt, APERIOD as trtn, count(distinct USUBJID) as nsubj
    from adae where AEACN='DRUG WITHDRAWN' group by APERIODC, APERIOD
  union all
    select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as nsubj
    from adae where AEACN='DRUG WITHDRAWN';
  /* TEAE leading to death */
  create table _dth as
    select APERIODC as trt, APERIOD as trtn, count(distinct USUBJID) as nsubj
    from adae where AESDTH='Y' group by APERIODC, APERIOD
  union all
    select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as nsubj
    from adae where AESDTH='Y';
quit;

/*--- stack category rows; merge denominators -> n (%) of PARTICIPANTS --------*/
data _rep;
  set _any(in=a) _ser(in=b) _rel(in=c) _sev(in=d) _dsc(in=e) _dth(in=f);
  length cat $60;  order=_n_;
  if a then do; cat='Participants with any TEAE';                     order=1; end;
  if b then do; cat='Participants with any serious TEAE';             order=2; end;
  if c then do; cat='Participants with any drug-related TEAE';        order=3; end;
  if d then do; cat='Participants with any severe TEAE';              order=4; end;
  if e then do; cat='TEAE leading to study-drug discontinuation'; order=5; end;
  if f then do; cat='TEAE leading to death';                      order=6; end;
run;
/* %catpct: merge _rep to _bign by period -> value = n (xx.x%) per period   */
proc transpose data=_rep out=_wide; by order cat; id trtn; var value; run;

%tfltitle(num=14.3.1.1, type=Table,
   text=%str(Overview of Treatment-Emergent Adverse Events by Period),
   pop=Safety Population,
   foot=%str(TEAE = treatment-emergent adverse event. A participant is counted once per category per period. Period 1 = reference; subsequent period(s) = test condition. % = participants with the event / N exposed in the period. MedDRA v27.0.));
proc report data=_wide nowd split='|';
  columns order cat ("By Period" /* period cols: P1=Reference, P2=Test... + Total */);
  define order / order noprint;
  define cat   / order 'Category' width=42 flow;
  /* define <each period var> and the Total column (trtn=9999) for display      */
run;
