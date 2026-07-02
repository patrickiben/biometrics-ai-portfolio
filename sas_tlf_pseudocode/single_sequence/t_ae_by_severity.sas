/******************************************************************************
* TABLE     : t_ae_by_severity  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Treatment-Emergent Adverse Events by System Organ Class,
*             Preferred Term and Maximum Severity, by Period
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (TRTEMFL='Y'); severity from ASEV/AESEVN
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS (distinct USUBJID). A participant is
*             counted once at their MAXIMUM severity per PT (and per period).
*             Columns = fixed PERIODS via APERIOD/APERIODC (Period 1 = victim
*             alone [reference], later = victim + perpetrator); NO randomized
*             sequence. % denominator = Safety N exposed per period.
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

data adae; set adam.adae(where=(TRTEMFL='Y' and SAFFL='Y')); run;

/*--- reduce to MAX severity per participant x period x PT --------------------
* AESEVN: 1=MILD 2=MODERATE 3=SEVERE. Take the worst per participant within PT. */
proc sql;
  create table _maxsev as
    select USUBJID, APERIOD, APERIODC, AESOC, AEDECOD, max(AESEVN) as AESEVN
    from adae group by USUBJID, APERIOD, APERIODC, AESOC, AEDECOD;
quit;

/*--- participants by severity level within PT, per period --------------------*/
proc sql;
  create table _socpt as
    select APERIODC as trt, APERIOD as trtn, AESOC, AEDECOD, AESEVN,
           count(distinct USUBJID) as nsubj
    from _maxsev group by APERIODC, APERIOD, AESOC, AEDECOD, AESEVN;
  /* SOC subtotal (level 1): a participant counted once per SOC at their worst
     severity in the SOC (two-step, mirror the _any idiom so USUBJID is out):
     step 1 = each participant's worst (max) severity within the SOC per period,  */
  create table _socsev as
    select APERIODC, APERIOD, AESOC, USUBJID, max(AESEVN) as maxsevn
    from _maxsev group by APERIODC, APERIOD, AESOC, USUBJID;
  /* step 2 = participants per period x SOC at each worst-severity level           */
  create table _soc as
    select APERIODC as trt, APERIOD as trtn, AESOC, maxsevn as AESEVN,
           count(distinct USUBJID) as nsubj
    from _socsev group by APERIODC, APERIOD, AESOC, maxsevn;
  /* "Any TEAE" overall row by max severity, per period (two-step so the
     participant is NOT in the final GROUP BY; mirror the _socpt idiom):
     step 1 = each participant's worst (max) severity over all PTs per period,    */
  create table _anysev as
    select APERIODC, APERIOD, USUBJID, max(AESEVN) as maxsevn
    from _maxsev group by APERIODC, APERIOD, USUBJID;
  /* step 2 = participants per period at each worst-severity level (USUBJID out)  */
  create table _any as
    select APERIODC as trt, APERIOD as trtn, maxsevn as AESEVN,
           count(distinct USUBJID) as nsubj
    from _anysev group by APERIODC, APERIOD, maxsevn;
quit;

/* %catpct: merge to _bign by period -> value = n (xx.x%) per period/sev    */
/* level 0 = any TEAE; level 1 = SOC subtotal; level 2 = PT within SOC      */
data _rep;
  set _any(in=a) _soc(in=s) _socpt(in=p);
  length term $200 sevc $10;
  sevc = put(AESEVN, aesev.);                 /* MILD/MODERATE/SEVERE        */
  if a then do; term='Participants with any TEAE'; level=0; end;
  else if s then do; term=AESOC; level=1; end;
  else do; term='   '||AEDECOD; level=2; end;
run;
proc sort data=_rep; by level AESOC term sevc; run;
proc transpose data=_rep out=_wide; by level AESOC term; id APERIOD sevc; var value; run;

%tfltitle(num=14.3.1.3, type=Table,
   text=%str(Treatment-Emergent Adverse Events by System Organ Class, Preferred Term and Maximum Severity, by Period),
   pop=Safety Population,
   foot=%str(A participant is counted once at their maximum severity per preferred term (and per SOC) per period. Severity: Mild/Moderate/Severe. Period 1 = reference; later period(s) = test condition. % = participants / N exposed in the period. MedDRA v27.0.));
proc report data=_wide nowd split='|';
  columns level term ("By Period and Maximum Severity" /* P x {Mild|Mod|Sev} */);
  define level / order noprint;
  define term  / order 'System Organ Class|  Preferred Term' width=40 flow;
run;
