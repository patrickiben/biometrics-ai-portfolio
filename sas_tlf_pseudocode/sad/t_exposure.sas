/******************************************************************************
* TABLE     : t_exposure  (Single Ascending Dose)
* TITLE     : Extent of Study Drug Exposure
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADEX  (single-dose administration record per participant)
* NOTE      : PSEUDOCODE. SAD: a SINGLE dose is administered, so exposure is
*             the administered dose level itself -- there is NO cumulative
*             dose accumulation, NO duration-of-treatment, and NO dose
*             intensity over multiple days. Exposure summary = the planned and
*             actually-administered dose (mg) per cohort, plus dose deviations
*             and dosing-day fasting/PK-window adherence where collected.
*             Column var = TRT01A = assigned dose level (placebo often pooled).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                      /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/*--- single-dose exposure record per participant from ADEX --------------------*
* Pull treatment from ADEX (TRT01A) -- no re-derivation. For a single dose,
* the relevant ADEX analysis params (PARAMCD) are:
*   DOSE   = administered dose at the single administration (mg)
*   PDOSE  = planned dose for the cohort (mg)
*   DOSEDEV= dose deviation = administered - planned (mg or %)
* Duration/number-of-doses metrics are intentionally NOT summarized for SAD.   */
data adex;
  set adam.adex(where=(SAFFL='Y'));
run;

/*--- continuous exposure metric block, summarized per dose level + Total ---*/
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
%expblk(pcd=DOSE,    label=Administered single dose (mg),  dp=1, ord=1);
%expblk(pcd=PDOSE,   label=Planned dose (mg),              dp=1, ord=2);
%expblk(pcd=DOSEDEV, label=Dose deviation (%),             dp=1, ord=3);

/*--- single-dose administration completeness (n %) ------------------------*
* SAD-specific categorical rows: participants who received the full planned dose,
* participants with a partial/interrupted single administration, etc.            */
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
  data _ec_&ord; set _x_&ord; length charlbl $48 stat $20 value $40;
    charlbl='Single-dose administration n (%)'; stat="&label"; ord=&ord;
    /* value = n (%) vs SAFFL N per column from _bign : "n (xx.x%)"          */
  run;
%mend;
%expcat(flagexpr=%str(PARAMCD='DOSE' and AVAL>0),                      label=Received any study drug, ord=4);
%expcat(flagexpr=%str(PARAMCD='DOSEDEV' and abs(AVAL)<=5),             label=Within 5%% of planned, ord=5);
%expcat(flagexpr=%str(PARAMCD='DOSEDEV' and abs(AVAL)>5),              label=Dose deviation > 5%%,  ord=6);

/*--- stack, transpose to one column per dose level + Total, render --------*/
data _all; set _e_: _ec_:; run;
proc sort data=_all; by ord charlbl stat; run;
proc transpose data=_all out=_wide; by ord charlbl stat; id trtn; var value; run;

%tfltitle(num=14.1.4, type=Table, text=Extent of Study Drug Exposure,
          pop=Safety Population,
          foot=%str(Single ascending dose: one dose administered per participant; no cumulative dose or treatment duration is summarized. Column = assigned dose level (TRT01A); placebo may be pooled. Administered/planned dose from ADEX. Percentages based on Safety Population N per dose level.));
proc report data=_wide nowd split='|';
  columns ord charlbl stat ("Dose Level" _NAME_ /* dose cols + Total */);
  define ord     / order noprint;
  define charlbl / order  'Exposure Metric' width=26 flow;
  define stat    / display 'Statistic'       width=18;
  /* define <each dose var>/display center "&header (N=&n)"; */
run;
