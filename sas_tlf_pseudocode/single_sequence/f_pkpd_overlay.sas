/******************************************************************************
* FIGURE    : f_pkpd_overlay  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Mean Plasma Concentration and Pharmacodynamic Response over Time
*             by Period (PK/PD Overlay)
* POPULATION: PK Population (PKFL='Y') / PD Population (PDFL='Y')
* INPUT     : ADPC (AVAL = plasma concentration; NRRELTM/ATPTN = nominal time)
*             ADPD (AVAL = PD biomarker response; ATPTN/AVISITN = nominal time)
*             APERIOD/APERIODC, TRTA/TRTAN from ADaM
* NOTE      : PSEUDOCODE. Dual-axis overlay: mean PK concentration (left/primary,
*             LOG10 semilog) vs mean PD response (right/secondary, LINEAR) on a
*             common nominal-time axis, paneled by fixed PERIOD (Period 1 =
*             reference [victim alone], Period 2 = test [victim + perpetrator]).
*             Single-/fixed-sequence: each participant contributes once per period
*             in the fixed order -> panels give a direct within-study exposure-
*             response comparison of test vs reference period. Descriptive (no
*             within-participant contrast computed here).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* group/panel = APERIODC (Reference / Test period) */

%let PCPARM = DRUGA;     /* analyte concentration PARAMCD (ADPC) - same as R  */
%let PDPARM = INHIB;     /* PD biomarker PARAMCD (ADPD) - same as R           */

/*--- mean PK concentration per PERIOD x nominal time --------------------*
* Single-sequence: CLASS uses &BYPERIOD (=APERIOD APERIODC).               */
data pc;
  set adam.adpc(where=(PKFL='Y' and PARAMCD="&PCPARM" and not missing(AVAL)));
  reltm = coalesce(NRRELTM, ATPTN);           /* nominal relative time (h)    */
run;
proc means data=pc nway noprint;
  class &BYPERIOD reltm;
  var AVAL;
  output out=_pk n=npk mean=conc;             /* arithmetic mean conc          */
run;

/*--- mean PD response per PERIOD x nominal time -------------------------*/
data pd;
  set adam.adpd(where=(PDFL='Y' and PARAMCD="&PDPARM" and not missing(AVAL)));
  reltm = coalesce(ATPTN, AVISITN);           /* align to PK time grid         */
run;
proc means data=pd nway noprint;
  class &BYPERIOD reltm;
  var AVAL;
  output out=_pd n=npd mean=resp;             /* mean PD response              */
run;

/*--- merge PK + PD onto common period x time grid -----------------------*/
data _pkpd;
  merge _pk(in=a) _pd(in=b);
  by APERIOD APERIODC reltm;
run;

%tfltitle(num=14.4.5.1, type=Figure,
   text=%str(Mean Plasma Concentration and Pharmacodynamic Response over Time by Period (PK/PD Overlay)),
   pop=Pharmacokinetic and Pharmacodynamic Populations,
   foot=%str(Left axis (LOG10, semilog) = mean plasma concentration; right axis (linear) = mean PD response; common nominal-time axis; one panel per fixed period (APERIODC; Period 1 = reference, subsequent period(s) = test). Single-/fixed-sequence. Descriptive exposure-response.));
proc sgpanel data=_pkpd;
  panelby APERIODC / columns=2 novarname;     /* one panel per fixed period    */
  /* concentration on the PRIMARY (left) axis, LOG10 semilog                   */
  series x=reltm y=conc / lineattrs=(thickness=2) markers
                          markerattrs=(symbol=circlefilled);
  /* PD response on the SECONDARY (right) axis, LINEAR                         */
  series x=reltm y=resp / lineattrs=(thickness=2 pattern=shortdash) markers
                          markerattrs=(symbol=trianglefilled) y2axis;
  colaxis label='Nominal Time (h)' type=linear;
  /* primary (left) rowaxis LOG10-scaled for concentration                    */
  rowaxis type=log logbase=10 label='Mean Concentration (units), log scale';
  /* secondary (right) rowaxis LINEAR for PD response                         */
  rowaxis2 type=linear label='Mean PD Response (units)';
run;
