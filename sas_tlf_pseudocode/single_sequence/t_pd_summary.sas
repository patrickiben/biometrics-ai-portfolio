/******************************************************************************
* TABLE     : t_pd_summary  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Summary of Pharmacodynamic Biomarker Results and Change from
*             Baseline by Period and Visit
* POPULATION: PD / Pharmacodynamic Analysis Population (PDFL='Y')
* INPUT     : ADPD (PARAM/PARAMCD = PD biomarkers; AVAL, BASE, CHG, PCHG;
*             AVISIT/AVISITN, ATPT/ATPTN as applicable; APERIOD/APERIODC,
*             TRTA/TRTAN from ADaM)
* NOTE      : PSEUDOCODE. Single-/fixed-sequence (no randomized sequence):
*             every participant passes through the fixed PERIODS in the same order
*             (e.g. Period 1 = victim alone [reference], Period 2 = victim +
*             perpetrator [test]). Summarize BY PERIOD (APERIODC) so each fixed
*             period forms its own column; CHG/PCHG are vs the WITHIN-PERIOD
*             baseline carried on ADPD. Report n, Mean (SD), Median, Min, Max
*             for AVAL, CHG and PCHG at each post-baseline visit/timepoint. PD
*             compared descriptively (formal test-vs-reference-period ratio =
*             t_be_anova for this design).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA TRTNVAR=TRTAN BYPERIOD=APERIOD APERIODC SEQVAR= */

/*--- header denominators: N per PERIOD column + Total (PD population) -------
* Single-sequence summaries are BY PERIOD (fixed order, no sequence), so the
* "column" variable is APERIODC, not the treatment arm. APERIOD/APERIODC are
* BDS per-record vars (not on ADSL), so the per-period N is built from the
* period-bearing source ADPD (mirror t_exposure.sas): distinct participants in the
* PD population per period, plus a Total column.                             */
proc sql noprint;
  create table _bign as
    select APERIOD as trtn, APERIODC as trt length=200,
           count(distinct USUBJID) as N
    from adam.adpd where PDFL='Y' group by APERIOD, APERIODC
  union all
    select 9999 as trtn, 'Total' as trt, count(distinct USUBJID) as N
    from adam.adpd where PDFL='Y';
quit;

data pd;
  set adam.adpd(where=(PDFL='Y'));
  /* period / treatment come straight from ADaM - no re-derivation;
     PARAM/PARAMCD order + decimal hints via study format catalog;
     keep baseline + post-baseline analysis visits/timepoints from ADaM      */
run;

/*--- descriptive stats: AVAL, CHG, PCHG by period x parameter x visit ------
* Reuse %descstat; CLASS uses &BYPERIOD (=APERIOD APERIODC) so each fixed     *
* period forms its own column.                                              */
%descstat(ds=pd, var=AVAL,  class=&BYPERIOD PARAM PARAMCD AVISIT AVISITN,
          where=%str(not missing(AVAL)),  dp=2, out=_aval);
%descstat(ds=pd, var=CHG,   class=&BYPERIOD PARAM PARAMCD AVISIT AVISITN,
          where=%str(not missing(CHG) and AVISITN>0), dp=2, out=_chg);
%descstat(ds=pd, var=PCHG,  class=&BYPERIOD PARAM PARAMCD AVISIT AVISITN,
          where=%str(not missing(PCHG) and AVISITN>0), dp=1, out=_pchg);

/*--- stack the three measures into one statistic column ------------------*/
data _stat; length measure $24 stat $20 value $30;
  set _aval (in=a) _chg (in=c) _pchg (in=p);
  if missing(AVISITN) then delete;      /* drop PROC MEANS _TYPE_ marginals  */
  if a then measure='Observed value';
  else if c then measure='Change from baseline';
  else if p then measure='% Change from baseline';
  /* emit display rows per measure:
     'n'                = put(n,3.)
     'Mean (SD)'        = catx(' ', cmean, csd)
     'Median'           = cmed
     'Min, Max'         = cminmax                                            */
run;

/*--- transpose PERIOD to columns; rows = param x visit x measure x stat ----*/
proc sort data=_stat; by PARAM PARAMCD AVISITN AVISIT measure stat APERIOD; run;
proc transpose data=_stat out=_wide; by PARAM PARAMCD AVISITN AVISIT measure stat;
  id APERIOD; var value;                /* one column per fixed period + Total */
run;

%tfltitle(num=14.4.6.1, type=Table,
   text=%str(Summary of Pharmacodynamic Biomarker Results and Change from Baseline by Period and Visit),
   pop=Pharmacodynamic Analysis Population,
   foot=%str(Single-/fixed-sequence: every participant passes the fixed periods in the same order (Period 1 = reference; subsequent period(s) = test). Summary BY PERIOD (APERIODC). Change/% change relative to within-period baseline (BASE). N (per period) from header. Descriptive only; formal test-vs-reference-period comparison in t_be_anova.));
proc report data=_wide nowd split='|';
  columns PARAM PARAMCD AVISIT AVISITN measure stat ("By Period" _NAME_ /* P1=Reference, P2=Test... + Total */);
  define PARAM   / order 'PD Parameter (units)' width=26 flow;
  define PARAMCD / order noprint;
  define AVISITN / order noprint;
  define AVISIT  / order 'Visit' width=14;
  define measure / order 'Measure' width=18;
  define stat    / display 'Statistic' width=12;
  /* define <each period var> / display center "&header (N=&n)"; */
  break after PARAM / skip;
run;
