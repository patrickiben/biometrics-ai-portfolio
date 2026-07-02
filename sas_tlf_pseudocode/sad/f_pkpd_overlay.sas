/******************************************************************************
* FIGURE    : f_pkpd_overlay  (SAD - Single Ascending Dose)
* TITLE     : Mean Plasma Concentration and Pharmacodynamic Response over Time
*             by Dose Level (PK/PD Overlay)
* POPULATION: PK Population (PKFL='Y') / PD Population (PDFL='Y')
* INPUT     : ADPC (AVAL = plasma concentration; NRRELTM/ATPTN = nominal time)
*             ADPD (AVAL = PD biomarker response; ATPTN/AVISITN = nominal time)
* NOTE      : PSEUDOCODE. SAD: parallel ascending cohorts, one (single) dose
*             per participant; panel/group var = TRT01A/TRT01AN (= dose level,
*             placebo pooled). Dual-axis overlay: mean PK concentration (left,
*             semilog) vs mean PD response (right) on a common nominal-time
*             axis, paneled by ascending dose level. Single dose => one profile
*             per participant (no accumulation); times relative to the single dose.
*             Reads the dose-related exposure rise alongside the PD response.
*             Descriptive exposure-response visualization (no within-participant
*             contrast). The formal dose-proportionality analysis of exposure
*             (power model: ln(param)=a+beta*ln(dose), beta + 90% CI) is
*             reported in the dose-proportionality table; this figure is the
*             companion PK/PD visualization.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                       /* panel/group = TRT01A (dose)  */

%let PCPARM = CONC;      /* analyte concentration PARAMCD (ADPC)             */
%let PDPARM = PDMARK1;   /* PD biomarker PARAMCD (ADPD)                      */

/*--- mean PK concentration per dose x nominal time ----------------------*/
data pc;
  set adam.adpc(where=(PKFL='Y' and PARAMCD="&PCPARM" and not missing(AVAL)));
  reltm = coalesce(NRRELTM, ATPTN);           /* nominal time after dose (h)  */
run;
proc means data=pc nway noprint;
  class &TRTVAR &TRTNVAR reltm;
  var AVAL;
  output out=_pk n=npk mean=conc;             /* arithmetic mean conc          */
run;

/*--- mean PD response per dose x nominal time ---------------------------*/
data pd;
  set adam.adpd(where=(PDFL='Y' and PARAMCD="&PDPARM" and not missing(AVAL)));
  reltm = coalesce(ATPTN, AVISITN);           /* align to PK time grid         */
run;
proc means data=pd nway noprint;
  class &TRTVAR &TRTNVAR reltm;
  var AVAL;
  output out=_pd n=npd mean=resp;             /* mean PD response              */
run;

/*--- merge PK + PD onto common dose x time grid -------------------------*/
data _pkpd;
  merge _pk(in=a) _pd(in=b);
  by &TRTVAR &TRTNVAR reltm;
run;

%tfltitle(num=14.4.5.1, type=Figure,
   text=%str(Mean Plasma Concentration and Pharmacodynamic Response over Time by Dose Level (PK/PD Overlay)),
   pop=Pharmacokinetic and Pharmacodynamic Populations,
   foot=%str(Left (primary) axis (semilog, log scale) = mean plasma concentration; right (secondary) axis (linear) = mean PD response; common nominal-time axis after the single dose; paneled by ascending dose level (placebo pooled). SAD: single dose, descriptive exposure-response.));
proc sgpanel data=_pkpd;
  panelby &TRTVAR / columns=2 novarname;      /* one panel per ascending dose  */
  /* concentration on the LEFT/primary axis, log10 (semilog) */
  series x=reltm y=conc / lineattrs=(thickness=2) markers
                          markerattrs=(symbol=circlefilled);
  /* PD response on the RIGHT/secondary axis, linear */
  series x=reltm y=resp / lineattrs=(thickness=2 pattern=shortdash) markers
                          markerattrs=(symbol=trianglefilled) y2axis;
  colaxis label='Nominal Time After Dose (h)' type=linear;
  /* left/primary rowaxis log-scaled for concentration */
  rowaxis type=log logbase=10 label='Mean Concentration (units)';
  /* right/secondary rowaxis linear for PD response */
  rowaxis2 type=linear label='Mean PD Response (units)';
run;
