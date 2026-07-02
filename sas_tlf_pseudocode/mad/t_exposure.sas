/******************************************************************************
* TABLE     : t_exposure  (Multiple Ascending Dose)
* TITLE     : Extent of Study Drug Exposure
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADEX  (multiple dosing records per participant over the regimen)
* NOTE      : PSEUDOCODE. MAD: repeated (e.g. once-daily) dosing over a
*             multi-day treatment period; column var = TRT01A = assigned dose
*             level (placebo pooled) + Total, ordered ascending dose.
*             Continuous exposure metrics summarized per dose level: n,
*             Mean(SD), Median, Min-Max. Because dosing is repeated, the key
*             exposure metrics are TREATMENT DURATION (days), NUMBER OF DOSES,
*             CUMULATIVE DOSE, and DOSE INTENSITY (% of planned) -- these define
*             whether a participant reached the planned dosing duration needed for
*             steady-state and accumulation (Rac) PK assessment.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/*--- one exposure summary record per participant from ADEX --------------------*
* ADEX holds repeated dosing records over the regimen. Use ADEX analysis
* exposure params (PARAMCD) which already collapse the dosing history -- no
* re-derivation. Pull treatment (TRT01A) from ADEX.
*   AVAL by PARAMCD: DURD  = duration of exposure (days, first to last dose)
*                    NDOSE = number of doses administered
*                    TDOSE = total cumulative dose (mg)
*                    DOSINT= dose intensity (% of planned cumulative dose)
*                    DOSEMOD = participants with any dose modification (flag-derived) */
data adex; set adam.adex(where=(SAFFL='Y')); run;

/*--- continuous exposure metric block, summarized per dose level + Total --*/
%macro expblk(pcd=, label=, unit=, dp=1, ord=);
  %descstat(ds=adex, var=AVAL, class=&TRTVAR &TRTNVAR,
            where=%str(PARAMCD="&pcd"), dp=&dp, out=_d);
  data _e_&ord; set _d; length charlbl $48 stat $20 value $40;
    charlbl="&label";  ord=&ord;
    stat='n';         value=put(n,5.);            output;
    stat='Mean (SD)'; value=catx(' ',cmean,csd);  output;
    stat='Median';    value=cmed;                 output;
    stat='Min, Max';  value=cminmax;              output;
  run;
%mend;
%expblk(pcd=DURD,   label=Duration of dosing (days),       dp=1, ord=1);
%expblk(pcd=NDOSE,  label=Number of doses received,        dp=0, ord=2);
%expblk(pcd=TDOSE,  label=Cumulative dose (mg),            dp=1, ord=3);
%expblk(pcd=DOSINT, label=Dose intensity (% of planned),   dp=1, ord=4);

/*--- exposure duration / compliance categories (n %) ----------------------*
* MAD-specific milestones: reached planned dosing duration (-> eligible for
* steady-state/Rac PK), and adequate compliance (dose intensity threshold).  */
%macro expcat(flagexpr=, label=, ord=);
  proc sql;
    create table _x_&ord as
      select &TRTVAR as trt length=200, &TRTNVAR as trtn,
             count(distinct USUBJID) as nsubj
      from adex where &flagexpr group by &TRTVAR, &TRTNVAR
    union all
      select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as nsubj
      from adex where &flagexpr;
  quit;
  data _ec_&ord; set _x_&ord; length charlbl $48 stat $24 value $40;
    charlbl='Dosing duration / compliance n (%)'; stat="&label"; ord=&ord;
    /* value = n (%) vs SAFFL N per column from _bign : "n (xx.x%)"          */
  run;
%mend;
%expcat(flagexpr=%str(PARAMCD='DURD' and AVAL>=7),   label=>= 7 days dosed,        ord=5);
%expcat(flagexpr=%str(PARAMCD='DURD' and AVAL>=14),  label=>= 14 days dosed,       ord=6);
%expcat(flagexpr=%str(PARAMCD='DURD' and AVAL>=21),  label=Completed planned days, ord=7);
%expcat(flagexpr=%str(PARAMCD='DOSINT' and AVAL>=80),label=Dose intensity >= 80%,  ord=8);

/*--- stack, transpose to one column per dose level + Total, render --------*/
data _all; set _e_: _ec_:; run;
proc sort data=_all; by ord charlbl stat; run;
proc transpose data=_all out=_wide; by ord charlbl stat; id trtn; var value; run;

%tfltitle(num=14.1.4, type=Table, text=Extent of Study Drug Exposure,
          pop=Safety Population,
          foot=%str(Column = assigned dose level (TRT01A); placebo pooled, columns ordered by ascending dose. Repeated (multiple) dosing over the treatment period; duration, number of doses, cumulative dose and dose intensity from ADEX. "Completed planned days" indicates participants who reached the planned dosing duration required for steady-state and accumulation (Rac) PK. Percentages based on Safety Population N per dose level.));
proc report data=_wide nowd split='|';
  columns ord charlbl stat ("Dose Level" _NAME_ /* dose cols + Total */);
  define ord     / order noprint;
  define charlbl / order  'Exposure Metric' width=28 flow;
  define stat    / display 'Statistic'       width=20;
  /* define <each dose var>/display center "&header (N=&n)"; ordered ascending dose */
run;
