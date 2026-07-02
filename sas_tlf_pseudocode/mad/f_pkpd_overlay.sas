/******************************************************************************
* FIGURE    : f_pkpd_overlay  (MAD - Multiple Ascending Dose)
* TITLE     : Mean Plasma Concentration and Pharmacodynamic Response over the
*             Steady-State Dosing Interval by Dose Level (PK/PD Overlay)
* POPULATION: PK Population (PKFL='Y') / PD Population (PDFL='Y')
* INPUT     : ADPC (AVAL = plasma concentration; NRRELTM/ATPTN = time post-dose)
*             ADPD (AVAL = PD biomarker response; ATPTN/AVISITN = time post-dose)
* NOTE      : PSEUDOCODE. Dual-axis overlay: mean PK concentration (left/y2,
*             semilog) vs mean PD response (right/y) on a common time axis,
*             paneled by dose level (= TRT01A; placebo pooled). MAD: repeated
*             dosing => the overlay is read over the STEADY-STATE dosing
*             interval (the rich profile day, e.g. last/Day-N PK day) so the
*             concentration-response relationship is shown at accumulated,
*             steady-state exposure. Restrict to the steady-state PK day
*             (AVISIT/PKDAY) for both domains. Descriptive exposure-response;
*             no within-participant contrast.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* group/panel = TRT01A (dose)  */

%let PCPARM = CONC;      /* analyte concentration PARAMCD (ADPC)               */
%let PDPARM = PDMARK1;   /* PD biomarker PARAMCD (ADPD)                        */
%let SSDAY  = ;          /* steady-state PK day filter (e.g. AVISIT='Day 14'); */
                        /* leave blank to overlay all profiled days           */

/*--- mean PK concentration per dose level x time-in-interval -------------
* Restrict to the steady-state profiling day so the profile reflects the
* accumulated (Rac) exposure, not the Day-1 single-dose profile.             */
data pc;
  set adam.adpc(where=(PKFL='Y' and PARAMCD="&PCPARM" and not missing(AVAL)));
  reltm = coalesce(NRRELTM, ATPTN);            /* nominal time post-dose (h)   */
  /* if &SSDAY set: keep only the steady-state day's profile                  */
run;
proc means data=pc nway noprint;
  class &TRTVAR &TRTNVAR reltm;
  var AVAL;
  output out=_pk n=npk mean=conc;              /* arithmetic mean conc          */
run;

/*--- mean PD response per dose level x time-in-interval ------------------*/
data pd;
  set adam.adpd(where=(PDFL='Y' and PARAMCD="&PDPARM" and not missing(AVAL)));
  reltm = coalesce(ATPTN, AVISITN);            /* align to PK time grid         */
  /* if &SSDAY set: keep only the steady-state day's response                 */
run;
proc means data=pd nway noprint;
  class &TRTVAR &TRTNVAR reltm;
  var AVAL;
  output out=_pd n=npd mean=resp;              /* mean PD response              */
run;

/*--- merge PK + PD onto common dose-level x time grid -------------------*/
data _pkpd;
  merge _pk(in=a) _pd(in=b);
  by &TRTVAR &TRTNVAR reltm;
run;

%tfltitle(num=14.4.5.1, type=Figure,
   text=%str(Mean Plasma Concentration and Pharmacodynamic Response over the Steady-State Dosing Interval by Dose Level (PK/PD Overlay)),
   pop=Pharmacokinetic and Pharmacodynamic Populations,
   foot=%str(Right axis (semilog) = mean plasma concentration; left axis = mean PD response; common time-post-dose axis over the steady-state dosing interval; paneled by dose level. Profile reflects accumulated (steady-state) exposure. MAD: descriptive exposure-response (placebo pooled).));
proc sgpanel data=_pkpd;
  panelby &TRTVAR / columns=2 novarname;       /* one panel per dose level      */
  series x=reltm y=conc / lineattrs=(thickness=2) markers
                          markerattrs=(symbol=circlefilled) y2axis;
  series x=reltm y=resp / lineattrs=(thickness=2 pattern=shortdash) markers
                          markerattrs=(symbol=trianglefilled);
  colaxis label='Time Post-Dose over the Steady-State Interval (h)' type=linear;
  rowaxis label='Mean PD Response (units)';
  /* y2axis log-scaled for concentration */
  rowaxis2 type=log logbase=10 label='Mean Concentration (units)';
run;
