/******************************************************************************
* LISTING   : l_ecg  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Listing of ECG Parameters
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADEG (all ECG parameters incl. interpretation)
* NOTE      : PSEUDOCODE. Participant-level listing ordered by participant, treatment
*             PERIOD, treatment, parameter, visit/timepoint. Shows actual value,
*             within-period baseline, change, reference-range indicator and
*             overall ECG interpretation. Single-/fixed-sequence key: NO sequence
*             variable; APERIODC / TRTA retained to show each fixed period's
*             treatment (e.g. Period 1 victim alone, Period 2 victim+perpetrator).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* BYPERIOD=APERIOD APERIODC ; TRTVAR=TRTA ; no SEQVAR */

data eg;
  set adam.adeg(where=(SAFFL='Y'));
  length subjid $20;
  subjid = scan(USUBJID, -1, '-');           /* short participant id for display  */
run;

proc sort data=eg;
  by USUBJID APERIOD APERIODC &TRTVAR PARAMCD AVISITN ATPTN;
run;

%tfltitle(num=16.2.8.1, type=Listing,
   text=%str(Listing of ECG Parameters),
   pop=Safety Population,
   foot=%str(Baseline = within-period baseline; CHG = AVAL - BASE. ANRIND = reference-range indicator. Interpretation = overall ECG read (Normal / Abnormal NCS / Abnormal CS). Single-/fixed-sequence: ordered by participant and fixed treatment period (no randomized sequence).));
proc report data=eg nowd split='|';
  columns subjid APERIODC &TRTVAR PARAM AVISIT ATPT
          AVAL BASE CHG ANRIND AVALC;
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
  define AVALC   / display 'Interpretation' width=18;  /* overall read for interpretation params */
run;
