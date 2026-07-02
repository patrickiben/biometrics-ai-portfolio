/******************************************************************************
* TABLE     : t_accumulation  (MAD - Multiple Ascending Dose)  [DESIGN-SPECIFIC]
* TITLE     : Accumulation Ratio and Assessment of Steady State by Dose Level
* POPULATION: PK Parameter Population (PKFL='Y')  [+ ADPC pre-dose troughs]
* INPUT     : ADPP (RACMAX RACAUC = pre-derived ratios ; or per-day CMAX/CMAXSS,
*             AUCLST/AUCTAU to form ratios) ; ADPC (PARAMCD pre-dose trough
*             concentration by study day; ABLFL/ATPTN=0 pre-dose samples)
* NOTE      : PSEUDOCODE. THIS is a file that differs by design (MAD only). Two
*             linked MAD-specific read-outs on repeated dosing:
*               (1) ACCUMULATION RATIO Rac = steady-state exposure / Day-1 exposure
*                   (Rac(Cmax)=Cmax,ss/Cmax day1 ; Rac(AUC)=AUCtau,ss/AUClast day1).
*                   Within-participant ratios from ADPP (RACMAX/RACAUC) or formed by
*                   participant across day 1 and day N, summarized as GEOMETRIC mean
*                   and Geo CV% by dose level (ratios -> log scale).
*               (2) STEADY-STATE ASSESSMENT via the pre-dose trough series: compare
*                   pre-dose (Ctrough) across consecutive dosing days; steady state
*                   is supported when successive troughs no longer rise (descriptive
*                   trend, optionally a within-participant log-linear slope across the
*                   last few days with 95% CI including 0). Column = TRT01A (= dose).
*             Geometric stats require ratio>0 / conc>0. Descriptive; no between-
*             dose hypothesis test here (see t_dose_proportionality_ss).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* column = TRT01A (= dose)   */

%let SS_FIRSTDAY = 5;   /* first dosing day of the steady-state trough window  */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=PKFL, out=_bign);

/*==========================================================================*
* PART 1 - ACCUMULATION RATIO Rac (steady-state vs Day 1), by dose level     *
*==========================================================================*/
/* Preferred: ADPP already carries the within-participant ratio parameters.       *
* If not pre-derived, build the per-participant ratio across study days first.    */
data rac;
  set adam.adpp(where=(PKFL='Y' and PARAMCD in ('RACMAX','RACAUC') and AVAL>0));
  lnval = log(AVAL);                           /* ratios summarized on log     */
run;

/* geometric summary of the ratio per dose level x ratio-parameter ---------*/
proc means data=rac noprint;
  class &TRTVAR &TRTNVAR PARAMCD PARAM;
  var lnval;
  output out=_racg n=n mean=gmean_log std=gsd_log;
run;
data _racd; set _racg; length stat $20 value $30;
  /* Geo Mean = exp(gmean_log); Geo CV% = 100*sqrt(exp(gsd_log**2)-1)         */
  /* emit rows: n / Geo Mean (Rac) / Geo CV% ; (optionally 95% CI of Rac)     */
run;

/*==========================================================================*
* PART 2 - STEADY-STATE ATTAINMENT from the pre-dose trough series           *
*==========================================================================*/
/* Pull pre-dose (trough) concentrations across dosing days from ADPC.        *
* ATPTN=0 (or ABLFL pre-dose flag) marks the trough sample each day.          */
data trough;
  set adam.adpc(where=(PKFL='Y' and ATPTN=0 and AVAL>0));
  avisitn = AVISITN;                           /* dosing day                   */
  lnconc  = log(AVAL);
run;

/* descriptive trough by dose level x day (geometric mean trend) -----------*/
proc means data=trough noprint;
  class &TRTVAR &TRTNVAR avisitn AVISIT;
  var lnconc;
  output out=_trg n=n mean=gmean_log std=gsd_log;
run;
data _trgd; set _trg; length stat $20 value $30;
  /* Geo Mean trough = exp(gmean_log); Geo CV%; one row per dosing day        */
  /* steady state supported when successive troughs plateau (no further rise) */
run;

/* OPTIONAL within-participant slope across the last K dosing days (steady-state  *
* test): if the 95% CI of the log-linear trough slope includes 0, the data    *
* are consistent with steady state having been reached.                       */
proc mixed data=trough(where=(avisitn>= &SS_FIRSTDAY)) method=reml;
  class USUBJID &TRTVAR;
  model lnconc = &TRTVAR avisitn*&TRTVAR / solution cl;   /* slope per dose    */
  random intercept / subject=USUBJID;
  ods output SolutionF=_slope;                  /* slope estimate + 95% CI     */
run;
/* _ssflag: 'Consistent with steady state' if slope 95% CI contains 0         */

/*==========================================================================*
* Assemble: Rac block (Part 1) then trough/steady-state block (Part 2)       *
*==========================================================================*/
data _all; set _racd _trgd; run;   /* + slope summary rows from _slope        */
proc sort data=_all; by stat; run;
proc transpose data=_all out=_wide; by stat; id &TRTNVAR; var value; run;

%tfltitle(num=14.4.4.1, type=Table,
   text=%str(Accumulation Ratio and Assessment of Steady State by Dose Level),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(Multiple ascending dose. Rac = steady-state exposure / Day-1 exposure within participant (Rac(Cmax)=Cmax,ss/Cmax day1; Rac(AUC)=AUCtau,ss/AUClast day1); summarized as geometric mean and Geo CV% per dose level. Steady-state assessment: geometric mean pre-dose (trough) concentration by dosing day; steady state is supported when successive troughs plateau. Slope test (optional): within-participant log-linear trough slope over the last dosing days; a 95% CI including 0 is consistent with steady state. Geometric statistics on values > 0. Descriptive.));
proc report data=_wide nowd split='|';
  columns stat ("Dose Level" /* dose cols + Total from &_bign */);
  define stat / order 'Statistic' width=34 flow;
run;
