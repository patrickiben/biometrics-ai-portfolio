/******************************************************************************
* TABLE     : t_ada_impact_pk  (MAD - Multiple Ascending Dose)
* TITLE     : Impact of Anti-Drug Antibody (ADA) Status on Steady-State Plasma
*             PK Exposure by Dose Level
* POPULATION: PK Population (PKFL='Y') with ADA result (ADA-evaluable)
* INPUT     : ADPP (steady-state PARAMCD = CMAXSS, AUCTAU, CTROUGH, RACAUC,
*             RACCMAX, ...) merged with participant-level ADA status from ADIS;
*             ADSL for dose-level column
* NOTE      : PSEUDOCODE. MAD: column = TRT01A/TRT01AN (= dose level, placebo
*             pooled); within each dose, exposure summarized by ADA status
*             (ADA-positive vs ADA-negative). Repeated dosing => the relevant
*             exposure metrics are STEADY-STATE parameters (Cmax,ss, AUCtau,
*             Ctrough) and the ACCUMULATION RATIO (Rac) -- ADA can reduce
*             accumulated exposure, so summarizing these by ADA status is the
*             MAD-specific read. PK stats = GEOMETRIC (n, Geo Mean, Geo CV%,
*             Median, Min, Max) on the log scale, matching the R twin and the
*             geometric-PK convention. Comparison is DESCRIPTIVE (subgroup
*             exposure by ADA status), not an inferential test.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* column = TRT01A (= dose)     */

/*--- participant-level ADA status from ADIS ---------------------------------*
* ADA-positive flag = treatment-emergent (TEADAFL), consistent with t_ada_summary
* and the R twin.                                                              */
proc sql;
  create table _adastat as
    select distinct USUBJID,
           case when max(case when upcase(TEADAFL)='Y' then 1 else 0 end)=1
                then 'ADA-positive' else 'ADA-negative' end as ADAGRP length=20
    from adam.adis where ADAFL='Y'
    group by USUBJID;
quit;

/*--- steady-state PK parameters + ADA group -----------------------------
* Keep the MAD steady-state exposure params and the accumulation ratios.     */
proc sql;
  create table pp as
    select p.*, a.ADAGRP
    from adam.adpp(where=(PKFL='Y'
                          and PARAMCD in ('CMAXSS','AUCTAU','CMINSS','CTROUGH',
                                          'RACMAX','RACAUC'))) p
    inner join _adastat a on p.USUBJID=a.USUBJID;
quit;
data pp; set pp;
  /* all selected params are continuous exposure / ratio metrics; no Tmax     */
  if AVAL>0 then logv = log(AVAL);             /* log value for geometric stats */
run;

/*--- GEOMETRIC summary by dose x ADA group x parameter ------------------
* Geometric stats on the log scale (matches the R twin): GeoMean=exp(mean_log),
* GeoCV%=100*sqrt(exp(var_log)-1). Geometric stats apply to Cmax,ss / AUCtau /
* Ctrough and to Rac. n, Median, Min, Max also reported.                      */
proc means data=pp(where=(AVAL>0)) noprint;
  class &TRTVAR &TRTNVAR ADAGRP PARAMCD PARAM;
  var AVAL;
  output out=_nmm n=n min=min max=max median=med;       /* n + raw-scale range/median */
run;
proc means data=pp(where=(AVAL>0)) noprint;
  class &TRTVAR &TRTNVAR ADAGRP PARAMCD; var logv;          /* log(AVAL)       */
  output out=_geo mean=gmean_log std=gsd_log;              /* on logVAL       */
run;
data _cont; merge _nmm _geo; by &TRTVAR ADAGRP PARAMCD;
  length stat $14 value $30;
  /* back-transform geometric stats; build display rows:
     n / Geo Mean (=exp(gmean_log)) / Geo CV% (=100*sqrt(exp(gsd_log**2)-1)) /
     Median / Min / Max                                                       */
run;

/*--- stack params (rows) x [dose x ADA group] (cols) --------------------*/
proc sort data=_cont; by PARAM PARAMCD stat &TRTNVAR ADAGRP; run;
proc transpose data=_cont out=_wide;
  by PARAM PARAMCD stat;
  id &TRTNVAR ADAGRP;                          /* dose x ADA-status columns    */
  var value;
run;

%tfltitle(num=14.5.2.1, type=Table,
   text=%str(Impact of Anti-Drug Antibody (ADA) Status on Steady-State Plasma PK Exposure by Dose Level),
   pop=Pharmacokinetic Population with ADA Result,
   foot=%str(Steady-state exposure (Cmax,ss, AUCtau, Ctrough) and accumulation ratio (Rac) summarized by ADA status (positive/negative) within each dose level. Geometric stats on the log scale: Geo CV% = 100*sqrt(exp(s^2_log)-1). ADA status = treatment-emergent (TEADAFL). Descriptive subgroup comparison; MAD, placebo pooled.));
proc report data=_wide nowd split='|';
  columns PARAM PARAMCD stat ("Dose Level by ADA Status" /* dose x ADA cols */);
  define PARAM   / order 'Parameter (units)' width=26;
  define PARAMCD / order noprint;
  define stat    / display 'Statistic' width=16;
run;
