/******************************************************************************
* FIGURE    : f_pkpd_overlay  (Parallel-group / per-dose)
* TITLE     : Mean Plasma Concentration and Pharmacodynamic Response over Time
*             by Treatment (PK/PD Overlay)
* POPULATION: PK Population (PKFL='Y') / PD Population (PDFL='Y')
* INPUT     : ADPC (AVAL = plasma concentration; NRRELTM/ATPTN = nominal time)
*             ADPD (AVAL = PD biomarker response; ATPTN/AVISITN = nominal time)
* NOTE      : PSEUDOCODE. Dual-axis overlay: mean PK concentration (left,
*             often semilog) vs mean PD response (right) on a common time
*             axis, paneled/grouped by treatment (dose). Parallel-group:
*             one treatment per participant; group var = TRT01A. Descriptive
*             exposure-response visualization (no within-participant contrast).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);                 /* group/panel = TRT01A (dose)  */

%let PCPARM = CONC;      /* analyte concentration PARAMCD (ADPC)             */
%let PDPARM = PDMARK1;   /* PD biomarker PARAMCD (ADPD)                      */

/*--- mean PK concentration per treatment x nominal time -----------------*/
data pc;
  set adam.adpc(where=(PKFL='Y' and PARAMCD="&PCPARM" and not missing(AVAL)));
  reltm = coalesce(NRRELTM, ATPTN);           /* nominal relative time (h)    */
run;
proc means data=pc nway noprint;
  class &TRTVAR &TRTNVAR reltm;
  var AVAL;
  output out=_pk n=npk mean=conc;             /* arithmetic mean conc          */
run;

/*--- mean PD response per treatment x nominal time ----------------------*/
data pd;
  set adam.adpd(where=(PDFL='Y' and PARAMCD="&PDPARM" and not missing(AVAL)));
  reltm = coalesce(ATPTN, AVISITN);           /* align to PK time grid         */
run;
proc means data=pd nway noprint;
  class &TRTVAR &TRTNVAR reltm;
  var AVAL;
  output out=_pd n=npd mean=resp;             /* mean PD response              */
run;

/*--- merge PK + PD onto common treatment x time grid --------------------*/
data _pkpd;
  merge _pk(in=a) _pd(in=b);
  by &TRTVAR &TRTNVAR reltm;
run;

%tfltitle(num=14.4.5.1, type=Figure,
   text=%str(Mean Plasma Concentration and Pharmacodynamic Response over Time by Treatment (PK/PD Overlay)),
   pop=Pharmacokinetic and Pharmacodynamic Populations,
   foot=%str(Right axis (semilog) = mean plasma concentration; left axis = mean PD response; common nominal-time axis; paneled by treatment (dose). Parallel-group: descriptive exposure-response.));
proc sgpanel data=_pkpd;
  panelby &TRTVAR / columns=2 novarname;      /* one panel per dose level      */
  series x=reltm y=conc / lineattrs=(thickness=2) markers
                          markerattrs=(symbol=circlefilled) y2axis;
  series x=reltm y=resp / lineattrs=(thickness=2 pattern=shortdash) markers
                          markerattrs=(symbol=trianglefilled);
  colaxis label='Nominal Time (h)' type=linear;
  rowaxis label='Mean PD Response (units)';
  /* y2axis log-scaled for concentration */
  rowaxis2 type=log logbase=10 label='Mean Concentration (units)';
run;
