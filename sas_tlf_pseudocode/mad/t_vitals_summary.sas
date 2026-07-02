/******************************************************************************
* TABLE     : t_vitals_summary  (Multiple Ascending Dose)
* TITLE     : Summary of Vital Signs and Change from Baseline by Study Day
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADVS  (PARAMCD: SYSBP, DIABP, PULSE, TEMP, RESP; AVAL, CHG,
*             BASE, AVISIT/AVISITN, ATPT/ATPTN, ADY)
* NOTE      : PSEUDOCODE. MAD design: parallel ascending-dose cohorts with
*             REPEATED dosing over a treatment period -> column var =
*             TRT01A/TRT01AN (= dose level; placebo pooled in ADaM). One
*             treatment per participant => descriptive only (n, Mean(SD), Median,
*             Min, Max) for AVAL and CHG; NO within-participant/by-period model.
*             Because dosing is repeated, the row structure is by STUDY DAY /
*             scheduled visit across the multiple-dose period (Day 1, Day k,
*             ... Day N), so the day-to-day trend is visible. Baseline (BASE)
*             = pre-first-dose value per ADaM; not re-derived here.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

/* column denominators (N=) per dose level + Total (pooled-placebo per ADaM) */
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/*--- analysis-ready vitals: safety pop, on-treatment analysis records -------
* Across the MAD period the pre-dose (trough) record per study day is the
* primary steady-state comparison row; ANL01FL='Y' selects analysis records. */
data advs;
  set adam.advs(where=(SAFFL='Y' and ANL01FL='Y'
                       and PARAMCD in ('SYSBP','DIABP','PULSE','TEMP','RESP')));
run;

/*--- one block per parameter: AVAL then CHG, by dose level x study day ------
* descstat classes on &TRTVAR &TRTNVAR (column) and AVISIT/AVISITN (= study
* day across the multiple-dose period); dp follows ADaM decimal hint.         */
%macro vsblk(pcd=, label=, dp=1, ord=);
  /* observed value */
  %descstat(ds=advs, var=AVAL, class=&TRTVAR &TRTNVAR AVISITN AVISIT,
            where=%str(PARAMCD="&pcd"), dp=&dp, out=_a);
  data _v_&pcd._a; set _a; length param $40 measure $24 stat $20 value $40;
    param="&label"; measure='Observed value'; ord=&ord;
    stat='n';         value=put(n,5.);            output;
    stat='Mean (SD)'; value=catx(' ',cmean,csd);  output;
    stat='Median';    value=cmed;                 output;
    stat='Min, Max';  value=cminmax;              output;
  run;
  /* change from baseline (BASE comes from ADaM; not re-derived) */
  %descstat(ds=advs, var=CHG, class=&TRTVAR &TRTNVAR AVISITN AVISIT,
            where=%str(PARAMCD="&pcd" and AVISITN>0), dp=&dp, out=_c);
  data _v_&pcd._c; set _c; length param $40 measure $24 stat $20 value $40;
    param="&label"; measure='Change from baseline'; ord=&ord;
    stat='n';         value=put(n,5.);            output;
    stat='Mean (SD)'; value=catx(' ',cmean,csd);  output;
    stat='Median';    value=cmed;                 output;
    stat='Min, Max';  value=cminmax;              output;
  run;
%mend vsblk;
%vsblk(pcd=SYSBP, label=Systolic BP (mmHg),       dp=1, ord=1);
%vsblk(pcd=DIABP, label=Diastolic BP (mmHg),      dp=1, ord=2);
%vsblk(pcd=PULSE, label=Pulse Rate (beats/min),   dp=1, ord=3);
%vsblk(pcd=TEMP,  label=Temperature (C),          dp=1, ord=4);
%vsblk(pcd=RESP,  label=Respiratory Rate (br/min),dp=1, ord=5);

/*--- stack, transpose to one column per dose level (ascending) + Total ------*/
data _all; set _v_:; run;
proc sort data=_all; by ord param measure AVISITN AVISIT stat; run;
proc transpose data=_all out=_wide;
  by ord param measure AVISITN AVISIT stat;
  id &TRTNVAR;  var value;             /* one col per dose level + Total (9999) */
run;

%tfltitle(num=14.3.7.1, type=Table,
   text=%str(Summary of Vital Signs and Change from Baseline by Study Day),
   pop=Safety Population,
   foot=%str(Columns = ascending dose levels (placebo pooled). Rows = study days across the multiple-dose period. Change from baseline = post-baseline value - pre-first-dose baseline (ADaM CHG). Descriptive statistics only; one treatment per participant (MAD ascending-dose cohorts).));
proc report data=_wide nowd split='|';
  columns ord param measure AVISITN AVISIT stat
          ("Dose Level" _NAME_ /* ascending dose cols + Total */);
  define ord     / order noprint;
  define param   / order 'Parameter'   width=24;
  define measure / order 'Measure'     width=18;
  define AVISITN / order noprint;
  define AVISIT  / order 'Study Day'   width=14;
  define stat    / display 'Statistic' width=12;
  /* define <each TRT01AN col> / display center "&header (N=&n)"; ascending dose */
run;
