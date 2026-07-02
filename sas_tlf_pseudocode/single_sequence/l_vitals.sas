/******************************************************************************
* LISTING   : l_vitals  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Listing of Vital Signs
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADVS (all vital-sign parameters)
* NOTE      : PSEUDOCODE. Participant-level listing ordered by participant, treatment
*             PERIOD, treatment, parameter, visit/timepoint. Shows actual value,
*             within-period baseline and change, and reference-range indicator.
*             Single-/fixed-sequence key: NO sequence variable; APERIODC / TRTA
*             retained so a reader sees what each participant got in each fixed
*             period (e.g. Period 1 victim alone, Period 2 victim + perpetrator).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* BYPERIOD=APERIOD APERIODC ; TRTVAR=TRTA ; no SEQVAR */

data vs;
  set adam.advs(where=(SAFFL='Y'));
  length subjid $20;
  subjid = scan(USUBJID, -1, '-');           /* short participant id for display  */
run;

proc sort data=vs;
  by USUBJID APERIOD APERIODC &TRTVAR PARAMCD AVISITN ATPTN;
run;

%tfltitle(num=16.2.7.2, type=Listing,
   text=%str(Listing of Vital Signs),
   pop=Safety Population,
   foot=%str(Baseline = within-period baseline; CHG = AVAL - BASE. ANRIND = reference-range indicator (L/N/H). Single-/fixed-sequence: ordered by participant and fixed treatment period (no randomized sequence).));
proc report data=vs nowd split='|';
  columns subjid APERIODC &TRTVAR PARAM AVISIT ATPT
          AVAL BASE CHG ANRIND;
  define subjid  / order 'Participant'         width=10;
  define APERIODC/ order 'Period'          width=12;
  define &TRTVAR / order 'Treatment'       width=18;
  define PARAM   / order 'Parameter'       width=22;
  define AVISIT  / order 'Visit'           width=14;
  define ATPT    / display 'Timepoint'     width=12;
  define AVAL    / display 'Value'         width=8;
  define BASE    / display 'Baseline'      width=9;
  define CHG     / display 'Change'        width=8;
  define ANRIND  / display 'Range|Ind'     width=7;
run;
