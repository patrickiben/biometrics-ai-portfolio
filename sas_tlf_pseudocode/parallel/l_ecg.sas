/******************************************************************************
* LISTING   : l_ecg  (Parallel-group)
* TITLE     : Listing of Electrocardiogram (ECG) Results
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADEG  (PARAMCD/PARAM, AVAL, BASE, CHG, AVISIT/AVISITN,
*             ATPT/ATPTN, ADT/ADTM, ANRIND, EGCLSIG/overall interpretation)
* NOTE      : PSEUDOCODE. Participant-level listing, one row per ECG parameter
*             measurement. Parallel-group: column var = TRT01A (one
*             treatment per participant); sorted within arm by participant, visit,
*             timepoint, parameter. Out-of-range flagged from ADaM ANRIND.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);          /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

/*--- all analysis ECG records for safety population -------------------------*/
data eg;
  set adam.adeg(where=(SAFFL='Y'
                       and PARAMCD in ('HR','PR','QRS','QT','QTCF','QTCB')));
  length subjid $20 flag $1;
  subjid = scan(USUBJID, -1, '-');                 /* short participant id        */
  flag   = ifc(ANRIND in ('LOW','HIGH'), '*', ' ');/* out-of-range marker     */
  length cval cbase cchg $12;
  cval  = put(AVAL, best8.);
  cbase = put(BASE, best8.);
  cchg  = ifc(AVISITN>0, put(CHG, best8.), ' ');
run;

proc sort data=eg;
  by &TRTNVAR &TRTVAR subjid AVISITN ATPTN PARAMCD;
run;

%tfltitle(num=16.2.8.1, type=Listing,
   text=%str(Listing of Electrocardiogram (ECG) Results),
   pop=Safety Population,
   foot=%str(* = value outside reference range (ADaM ANRIND). CHG = change from baseline. QTcF = Fridericia-corrected QT. One treatment per participant (parallel-group). Times relative to dosing.));
proc report data=eg nowd split='|';
  columns &TRTVAR subjid AGE SEX PARAM AVISIT ATPT ADT
          AVAL flag BASE cchg ANRIND EGINTP;
  define &TRTVAR / order 'Treatment|Arm'        width=14;
  define subjid  / order 'Participant'              width=10;
  define AGE     / display 'Age'                width=4;
  define SEX     / display 'Sex'                width=4;
  define PARAM   / order  'Parameter'           width=20;
  define AVISIT  / order  'Visit'               width=12;
  define ATPT    / display 'Timepoint'          width=14;
  define ADT     / display 'Date'               width=11 format=date9.;
  define AVAL    / display 'Value'              width=8;
  define flag    / display ' '                  width=2;
  define BASE    / display 'Baseline'           width=8;
  define cchg    / display 'Change|from BL'     width=8;
  define ANRIND  / display 'Ref|Range Ind'      width=8;
  define EGINTP  / display 'Overall|Interpretation' width=16;
  break after &TRTVAR / skip;
run;
