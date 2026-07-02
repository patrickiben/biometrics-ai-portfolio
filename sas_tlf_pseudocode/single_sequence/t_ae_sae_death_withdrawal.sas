/******************************************************************************
* TABLE     : t_ae_sae_death_withdrawal  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Serious Adverse Events, Deaths, and AEs Leading to Withdrawal
*             by System Organ Class and Preferred Term, by Period
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (AESER, AESDTH, AEACN, TRTEMFL)
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS (distinct USUBJID). Three stacked
*             sub-tables (SAE / Death / Withdrawal-due-to-AE), each by SOC and
*             PT. Columns = fixed PERIODS via APERIOD/APERIODC (Period 1 = victim
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

/*--- three event subsets (participant-level), each by SOC*PT and period ------*/
%macro block(flag=, label=, cond=, num=);
  %aecount(ds=adae, trtvar=APERIODC, popden=_bign, where=%str(&cond),
           byvars=%str(_dummy),        out=_any_&flag);   /* "Any" row       */
  %aecount(ds=adae, trtvar=APERIODC, popden=_bign, where=%str(&cond),
           byvars=%str(AESOC AEDECOD), out=_pt_&flag);     /* SOC*PT rows     */
  data _blk_&flag;
    set _any_&flag(in=a) _pt_&flag(in=p);
    length section term $200;
    section = "&label";  secord = &num;
    if a then do; term="Participants with any &label"; level=0; end;
    else do; term='   '||catx(': ', AESOC, AEDECOD); level=2; end;
  run;
%mend;
%block(flag=sae, label=%str(serious TEAE),                cond=%str(AESER='Y'),            num=1);
%block(flag=dth, label=%str(TEAE leading to death),       cond=%str(AESDTH='Y'),           num=2);
%block(flag=wd,  label=%str(TEAE leading to withdrawal),  cond=%str(AEACN='DRUG WITHDRAWN'), num=3);

/* value = n (xx.x%) of PARTICIPANTS, denominator = N exposed in the period      */
data _rep; set _blk_sae _blk_dth _blk_wd; run;
proc sort data=_rep; by secord section level term; run;
proc transpose data=_rep out=_wide; by secord section level term; id APERIOD; var value; run;

%tfltitle(num=14.3.1.5, type=Table,
   text=%str(Serious Adverse Events, Deaths, and AEs Leading to Withdrawal by SOC and Preferred Term, by Period),
   pop=Safety Population,
   foot=%str(Treatment-emergent only. SAE per AESER; death per AESDTH; withdrawal = study drug withdrawn (AEACN). A participant is counted once at each level per period. Period 1 = reference; later period(s) = test condition. % = participants / N exposed in the period. MedDRA v27.0.));
proc report data=_wide nowd split='|';
  columns secord section level term ("By Period" /* P1=Reference, P2=Test... */);
  define secord  / order noprint;
  define section / order noprint;
  define level   / order noprint;
  define term    / order 'Category / System Organ Class: Preferred Term' width=46 flow;
  compute before section; line @1 section $200.; endcomp;   /* section header */
run;
