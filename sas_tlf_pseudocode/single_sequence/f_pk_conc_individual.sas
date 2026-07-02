/******************************************************************************
* FIGURE    : f_pk_conc_individual  (Single-/fixed-sequence - e.g. DDI)
* TITLE     : Individual Plasma Concentration-Time Profiles by Participant
*             (Semi-Logarithmic)
* POPULATION: PK Concentration Population (PKFL='Y')
* INPUT     : ADPC (AVAL = concentration; ATPTN = nominal time)
* NOTE      : PSEUDOCODE. Single-/fixed-sequence -> one panel per PARTICIPANT, with
*             that participant's Reference (victim alone) and Test (victim+
*             perpetrator) period profiles OVERLAID on the same axes (grouped by
*             APERIODC). This is the within-participant DDI view: each participant is
*             their own control, so the interaction effect is read panel by
*             panel. Semi-log y. Paneled via SGPANEL across participants.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* overlay = APERIODC; panel = USUBJID       */

data pc;
  set adam.adpc(where=(PKFL='Y'));
  length subjid $20;
  subjid = scan(USUBJID,-1,'-');
  trt    = &TRTVAR;                          /* treatment given this period    */
  if upcase(AVALC)='BLQ' then AVAL=.;        /* drop BLQ from individual log    */
  ylog   = ifn(AVAL>0, AVAL, .);
run;
proc sort data=pc; by subjid APERIOD ATPTN; run;

%tfltitle(num=14.4.2.3, type=Figure,
   text=%str(Individual Plasma Concentration-Time Profiles by Participant (Semi-Logarithmic)),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(One panel per participant; Reference and Test period profiles overlaid (dosing period, APERIODC) so each participant serves as own control. Semi-log y; BLQ omitted. Nominal sampling times.));
/*--- one panel per participant, Reference vs Test overlaid -------------------*/
proc sgpanel data=pc;
  panelby subjid / columns=4 rows=3 novarname;
  series  x=ATPTN y=ylog / group=APERIODC markers
                           lineattrs=(thickness=1.5) markerattrs=(symbol=circlefilled);
  colaxis label='Nominal Time (h)' values=(0 to 24 by 4);
  rowaxis type=log logbase=10 label='Concentration (unit), log scale';
  keylegend / title='Treatment Period' position=bottom;
run;
