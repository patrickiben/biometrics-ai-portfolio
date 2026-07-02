/******************************************************************************
* TABLE     : t_ada_impact_pk  (SAD - Single Ascending Dose)
* TITLE     : Impact of Anti-Drug Antibody (ADA) Status on Plasma PK Exposure
*             by Dose Level
* POPULATION: PK Population (PKFL='Y') with ADA result (ADA-evaluable)
* INPUT     : ADPP (PARAMCD = CMAX, AUCLST, AUCIFO, ...) merged with participant-
*             level ADA status from ADIS; ADSL for dose-level column
* NOTE      : PSEUDOCODE. SAD: parallel ascending cohorts, one (single) dose
*             per participant; column = TRT01A/TRT01AN (= dose level, placebo
*             pooled). Single dose => single-dose exposure parameters (Cmax,
*             AUClast, AUCinf); no accumulation / no steady-state Rac. Within
*             each dose, single-dose exposure parameters summarized by ADA
*             status (ADA-positive vs ADA-negative). PK stats = arithmetic
*             n, Mean, SD, CV%, Geo Mean, Geo CV%, Median, Min, Max. Tmax
*             (if shown) = Median (Min, Max) only. Comparison is DESCRIPTIVE
*             (subgroup exposure by ADA status), not an inferential test.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                       /* column = TRT01A (= dose)     */

/*--- participant-level ADA status from ADIS ---------------------------------*/
proc sql;
  create table _adastat as
    select distinct USUBJID,
           /* ADaM-provided overall ADA status flag mapped to label:
              'ADA-positive' / 'ADA-negative' (treatment-emergent basis)     */
           case when ADAEMFL='Y' then 'ADA-positive'
                else 'ADA-negative' end as ADAGRP length=20
    from adam.adis where ADAFL='Y';
quit;

/*--- single-dose PK parameters + ADA group; keep exposure params ---------*/
proc sql;
  create table pp as
    select p.*, a.ADAGRP
    from adam.adpp(where=(PKFL='Y'
                          and PARAMCD in ('CMAX','AUCLST','AUCIFO','TMAX'))) p
    inner join _adastat a on p.USUBJID=a.USUBJID;
quit;
data pp; set pp;
  tmaxfl = (PARAMCD='TMAX');                   /* Tmax -> median (min,max)     */
  if AVAL>0 then logv = log(AVAL);             /* log value for geometric stats */
run;

/*--- arithmetic + geometric summary by dose x ADA group x parameter -----
* Reuse %pkstats pattern: arithmetic n/Mean/SD/CV% + geometric on log scale */
proc means data=pp(where=(tmaxfl=0)) noprint;
  class &TRTVAR &TRTNVAR ADAGRP PARAMCD PARAM;
  var AVAL;
  output out=_arith n=n mean=mean std=std min=min max=max cv=cv;
run;
/* geometric: PROC MEANS on log(AVAL), AVAL>0; GeoMean=exp(mean_log),
   GeoCV%=100*sqrt(exp(var_log)-1)                                           */
proc means data=pp(where=(tmaxfl=0 and AVAL>0)) noprint;
  class &TRTVAR &TRTNVAR ADAGRP PARAMCD; var logv;          /* log(AVAL)       */
  output out=_geo mean=gmean_log std=gsd_log;              /* on logVAL       */
run;
data _cont; merge _arith _geo; by &TRTVAR ADAGRP PARAMCD;
  length stat $14 value $30;
  /* round to ADaM decimal hints; build display rows:
     n / Mean / SD / CV% / Geo Mean / Geo CV% / Median / Min / Max           */
run;

/*--- Tmax: Median (Min, Max) only ---------------------------------------*/
proc means data=pp(where=(tmaxfl=1)) noprint;
  class &TRTVAR &TRTNVAR ADAGRP PARAMCD; var AVAL;
  output out=_tmax median=med min=min max=max;
run;
data _tmaxd; set _tmax; length stat $14 value $30;
  stat='Median (Min, Max)';
  value=catx(' ', put(med,8.2), cats('(',put(min,8.2),', ',put(max,8.2),')'));
run;

/*--- stack params (rows) x [dose x ADA group] (cols) --------------------*/
data _all; set _cont _tmaxd; run;
proc sort data=_all; by PARAM PARAMCD stat &TRTNVAR ADAGRP; run;
proc transpose data=_all out=_wide;
  by PARAM PARAMCD stat;
  id &TRTNVAR ADAGRP;                          /* dose x ADA-status columns    */
  var value;
run;

%tfltitle(num=14.5.2.1, type=Table,
   text=%str(Impact of Anti-Drug Antibody (ADA) Status on Plasma PK Exposure by Dose Level),
   pop=Pharmacokinetic Population with ADA Result,
   foot=%str(Single-dose exposure parameters summarized by ADA status (positive/negative) within each dose level. CV% arithmetic; Geo CV% = 100*sqrt(exp(s^2_log)-1). Tmax: Median (Min, Max). Descriptive subgroup comparison; SAD: single dose, no accumulation.));
proc report data=_wide nowd split='|';
  columns PARAM PARAMCD stat ("Dose Level by ADA Status" /* dose x ADA cols */);
  define PARAM   / order 'Parameter (units)' width=26;
  define PARAMCD / order noprint;
  define stat    / display 'Statistic' width=16;
run;
