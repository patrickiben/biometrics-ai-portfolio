/******************************************************************************
* FIGURE    : f_pkpd_overlay  (Crossover - 2x2 or Williams)
* TITLE     : Mean Plasma Concentration and Pharmacodynamic Response over Time
*             by Treatment (PK/PD Overlay)
* POPULATION: PK Population (PKFL='Y') / PD Population (PDFL='Y')
* INPUT     : ADPC (AVAL = plasma concentration; NRRELTM/ATPTN = nominal time)
*             ADPD (AVAL = PD biomarker response; ATPTN/AVISITN = nominal time)
*             TRTA/TRTAN, APERIODC, TRTSEQP from ADaM
* NOTE      : PSEUDOCODE. Dual-axis overlay: mean PK concentration (left,
*             semilog/log10) vs mean PD response (right, linear) on a common
*             nominal-time axis, paneled by ANALYSIS treatment TRTA (Test /
*             Reference).
*             Within-participant crossover: each participant contributes per treatment
*             received, pooled across period -> panels give a direct within-
*             study exposure-response comparison. Descriptive (no within-
*             participant contrast computed here).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* group/panel = TRTA (Test / Reference)   */

%let PCPARM = CONC;      /* analyte concentration PARAMCD (ADPC)             */
%let PDPARM = PDMARK1;   /* PD biomarker PARAMCD (ADPD)                      */

/*--- mean PK concentration per treatment x nominal time -----------------*
* Crossover: CLASS uses &TRTVAR (=TRTA); pooled across period within trt.  */
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
   foot=%str(Left axis (semilog/log10) = mean plasma concentration; right axis (linear) = mean PD response; common nominal-time axis; one panel per analysis treatment (TRTA). Within-participant crossover: pooled across period. Descriptive exposure-response.));
proc sgpanel data=_pkpd;
  panelby &TRTVAR / columns=2 novarname;      /* one panel per treatment       */
  series x=reltm y=conc / lineattrs=(thickness=2) markers
                          markerattrs=(symbol=circlefilled);
  series x=reltm y=resp / lineattrs=(thickness=2 pattern=shortdash) markers
                          markerattrs=(symbol=trianglefilled) y2axis;
  colaxis label='Nominal Time (h)' type=linear;
  /* primary (left) axis log-scaled for concentration */
  rowaxis type=log logbase=10 label='Mean Concentration (units)';
  rowaxis2 type=linear label='Mean PD Response (units)';
run;
