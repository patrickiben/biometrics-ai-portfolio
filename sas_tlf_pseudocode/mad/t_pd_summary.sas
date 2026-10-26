/******************************************************************************
* TABLE     : t_pd_summary  (MAD - Multiple Ascending Dose)
* TITLE     : Summary of Pharmacodynamic Biomarker Results and Change from
*             Baseline by Dose Level, Study Day and Time
* POPULATION: PD / Pharmacodynamic Analysis Population (PDFL='Y')
* INPUT     : ADPD (PARAM/PARAMCD = PD biomarkers; AVAL, BASE, CHG, PCHG;
*             AVISIT/AVISITN study day, ATPT/ATPTN time post-dose)
* NOTE      : PSEUDOCODE. MAD: parallel ascending cohorts, REPEATED (multi-day)
*             dosing; one assigned dose level per participant; column variable =
*             TRT01A/TRT01AN (= dose level, placebo pooled). Because dosing is
*             repeated, the PD response is read over STUDY DAYS (AVISITN, e.g.
*             Day 1 vs Day N) as well as time post-dose (ATPTN) so the
*             onset/maintenance of the PD effect at STEADY STATE can be seen.
*             PD compared DESCRIPTIVELY across dose levels (no within-participant
*             or period contrast). Report n, Mean (SD), Median, Min, Max for
*             AVAL, CHG and PCHG at each post-baseline study day / timepoint.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* column = TRT01A (= dose)     */

/*--- header denominators: N per dose column (PD population) --------------*/
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=PDFL, out=_bign);

data pd;
  set adam.adpd(where=(PDFL='Y'));
  /* PARAM/PARAMCD order + decimal hints via study format catalog;
     keep baseline + post-baseline study days/timepoints from ADaM. For MAD
     the analysis grid spans the repeated-dosing period (Day 1 ... Day N).    */
  reltm = coalesce(ATPTN, AVISITN);            /* nominal time post-dose       */
run;

/*--- descriptive stats: AVAL, CHG, PCHG by dose x parameter x day x time -
* Reuse %descstat for each measure; class drives the row/column structure.
* AVISITN carries the study day so Day 1 and steady-state day are both rows.  */
%descstat(ds=pd, var=AVAL,  class=&TRTVAR &TRTNVAR PARAM PARAMCD AVISIT AVISITN ATPT ATPTN,
          where=%str(not missing(AVAL)),  dp=2, out=_aval);
%descstat(ds=pd, var=CHG,   class=&TRTVAR &TRTNVAR PARAM PARAMCD AVISIT AVISITN ATPT ATPTN,
          where=%str(not missing(CHG) and AVISITN>0), dp=2, out=_chg);
%descstat(ds=pd, var=PCHG,  class=&TRTVAR &TRTNVAR PARAM PARAMCD AVISIT AVISITN ATPT ATPTN,
          where=%str(not missing(PCHG) and AVISITN>0), dp=1, out=_pchg);

/*--- stack the three measures into one statistic column ------------------*/
data _stat; length measure $24 stat $20 value $30;
  set _aval (in=a) _chg (in=c) _pchg (in=p);
  if a then measure='Observed value';
  else if c then measure='Change from baseline';
  else if p then measure='% Change from baseline';
  /* emit display rows per measure: n / Mean (SD) / Median / Min, Max:
     'n'                = put(n,3.)
     'Mean (SD)'        = catx(' ', cmean, csd)
     'Median'           = cmed
     'Min, Max'         = cminmax                                            */
run;

/*--- transpose dose to columns; rows = param x day x time x measure x stat */
proc sort data=_stat; by PARAM PARAMCD AVISITN AVISIT ATPTN measure stat &TRTNVAR; run;
proc transpose data=_stat out=_wide; by PARAM PARAMCD AVISITN AVISIT ATPTN measure stat;
  id &TRTNVAR; var value;
run;

/*--- MAD-SPECIFIC: PD steady-state read on the PRE-DOSE (trough) value -----
* Mirrors the R twin. Pre-dose records (ATPTN<=0 or ATPT='PRE-DOSE') on active
* dose levels; trough geometric mean by dose x study day on the log scale
* (values > 0), then a log-linear trough-vs-day slope per active dose with a
* random participant intercept. A 95% CI for the day slope that INCLUDES 0
* supports a PD plateau. Descriptive support.                                */
data trough;
  set pd(where=(not missing(AVAL) and &TRTNVAR>0 and
                ((not missing(ATPTN) and ATPTN<=0) or upcase(ATPT)='PRE-DOSE')));
  if AVAL>0 then lntr = log(AVAL);             /* log trough value             */
run;
proc means data=trough(where=(AVAL>0)) noprint;
  class &TRTVAR &TRTNVAR ADY; var lntr;
  output out=_trgeo n=n mean=gmean_log;
run;
data _trgeo; set _trgeo;
  geomean = exp(gmean_log);                    /* trough geometric mean        */
run;
proc sort data=trough(where=(AVAL>0 and ADY>0)) out=_trss; by &TRTNVAR; run;
proc mixed data=_trss method=reml;
  by &TRTNVAR;
  class USUBJID;
  model lntr = ADY / solution cl;              /* log-linear trough slope      */
  random intercept / subject=USUBJID;
  ods output SolutionF=_trslope;               /* ADY slope + 95% CI           */
run;

/*--- OPTIONAL dose-response of a steady-state PD metric (power model) ------
* Peak PD value per participant on active doses (metric > 0), fitted on the
* log-log scale as in the dose-proportionality power model; slope + 90% CI.  */
proc means data=pd(where=(not missing(AVAL) and &TRTNVAR>0)) noprint nway;
  class USUBJID &TRTNVAR; var AVAL;
  output out=_metric max=metric;
run;
data _metric; set _metric(where=(metric>0));
  lnmetric = log(metric);
  lndose   = log(&TRTNVAR);
run;
proc reg data=_metric;
  model lnmetric = lndose / clb alpha=0.10;    /* slope beta + 90% CI          */
  ods output ParameterEstimates=_drfit;
run;

%tfltitle(num=14.4.6.1, type=Table,
   text=%str(Summary of Pharmacodynamic Biomarker Results and Change from Baseline by Dose Level, Study Day and Time),
   pop=Pharmacodynamic Analysis Population,
   foot=%str(Descriptive summary by dose level. MAD: repeated dosing; PD read across study days (Day 1 ... steady-state day) and time post-dose. PD compared descriptively across ascending doses (placebo pooled). Change and % change relative to baseline (BASE). N (per dose) from header.));
proc report data=_wide nowd split='|';
  columns PARAM PARAMCD AVISIT AVISITN ATPTN measure stat ("Dose Level" /* dose cols */);
  define PARAM   / order 'PD Parameter (units)' width=26 flow;
  define PARAMCD / order noprint;
  define AVISITN / order noprint;
  define ATPTN   / order noprint;
  define AVISIT  / order 'Study Day / Time' width=16;
  define measure / order 'Measure' width=18;
  define stat    / display 'Statistic' width=12;
  break after PARAM / skip;
run;
