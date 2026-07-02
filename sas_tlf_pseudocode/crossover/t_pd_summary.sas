/******************************************************************************
* TABLE     : t_pd_summary  (Crossover - 2x2 or Williams)
* TITLE     : Summary of Pharmacodynamic Biomarker Results and Change from
*             Baseline by Treatment and Visit
* POPULATION: PD / Pharmacodynamic Analysis Population (PDFL='Y')
* INPUT     : ADPD (PARAM/PARAMCD = PD biomarkers; AVAL, BASE, CHG, PCHG;
*             AVISIT/AVISITN, ATPT/ATPTN as applicable; TRTA/TRTAN,
*             APERIOD/APERIODC, TRTSEQP from ADaM)
* NOTE      : PSEUDOCODE. Within-participant crossover: each participant contributes
*             to every treatment received -> summarize by ANALYSIS treatment
*             TRTA (collapsed across period; each participant once per treatment).
*             CHG/PCHG are vs the WITHIN-PERIOD baseline carried on ADPD.
*             Report n, Mean (SD), Median, Min, Max for AVAL, CHG and PCHG at
*             each post-baseline visit/timepoint. A by-period breakout adds
*             APERIODC to CLASS if requested by the SAP. PD compared
*             descriptively (formal Test-vs-Reference contrast = t_be_anova).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTVAR=TRTA TRTNVAR=TRTAN BYPERIOD=APERIOD APERIODC SEQVAR=TRTSEQP */

/*--- header denominators: N per treatment column + Total (PD population) --*/
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=PDFL, out=_bign);

data pd;
  set adam.adpd(where=(PDFL='Y'));
  /* treatment / period / sequence come straight from ADaM - no re-derivation;
     PARAM/PARAMCD order + decimal hints via study format catalog;
     keep baseline + post-baseline analysis visits/timepoints from ADaM     */
run;

/*--- descriptive stats: AVAL, CHG, PCHG by treatment x parameter x visit --
* Reuse %descstat; CLASS includes &TRTVAR (=TRTA) so each treatment the      *
* participant received forms its own column; APERIODC available for by-period.  */
%descstat(ds=pd, var=AVAL,  class=&TRTVAR &TRTNVAR PARAM PARAMCD AVISIT AVISITN,
          where=%str(not missing(AVAL)),  dp=2, out=_aval);
%descstat(ds=pd, var=CHG,   class=&TRTVAR &TRTNVAR PARAM PARAMCD AVISIT AVISITN,
          where=%str(not missing(CHG) and AVISITN>0), dp=2, out=_chg);
%descstat(ds=pd, var=PCHG,  class=&TRTVAR &TRTNVAR PARAM PARAMCD AVISIT AVISITN,
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

/*--- transpose treatment to columns; rows = param x visit x measure x stat */
proc sort data=_stat; by PARAM PARAMCD AVISITN AVISIT measure stat &TRTNVAR; run;
proc transpose data=_stat out=_wide; by PARAM PARAMCD AVISITN AVISIT measure stat;
  id &TRTNVAR; var value;               /* one column per treatment + Total  */
run;

%tfltitle(num=14.2.6.1, type=Table,
   text=%str(Summary of Pharmacodynamic Biomarker Results and Change from Baseline by Treatment and Visit),
   pop=Pharmacodynamic Analysis Population,
   foot=%str(Within-participant crossover: each participant contributes to every treatment received (summary by TRTA, collapsed across period). Change/% change relative to within-period baseline (BASE). N (per treatment) from header. Descriptive only; formal Test-vs-Reference comparison in t_be_anova.));
proc report data=_wide nowd split='|';
  columns PARAM PARAMCD AVISIT AVISITN measure stat ("Treatment" _NAME_ /* trt cols + Total */);
  define PARAM   / order 'PD Parameter (units)' width=26 flow;
  define PARAMCD / order noprint;
  define AVISITN / order noprint;
  define AVISIT  / order 'Visit' width=14;
  define measure / order 'Measure' width=18;
  define stat    / display 'Statistic' width=12;
  /* define <each treatment var> / display center "&header (N=&n)"; */
  break after PARAM / skip;
run;
