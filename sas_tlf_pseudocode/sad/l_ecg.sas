/******************************************************************************
* LISTING   : l_ecg  (Single Ascending Dose)
* TITLE     : Listing of Electrocardiogram (ECG) Results
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADEG  (PARAMCD/PARAM, AVAL, BASE, CHG, AVISIT/AVISITN,
*             ATPT/ATPTN, ADT/ADTM, ANRIND, EGINTP/overall interpretation)
* NOTE      : PSEUDOCODE. Participant-level listing, one row per ECG parameter
*             measurement. SAD: column var = dose level (TRT01A), one (single)
*             dose per participant; sorted by ascending dose, then participant, visit,
*             timepoint, parameter. Out-of-range flagged from ADaM ANRIND.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN  */

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

/* sort by dose level (ascending via TRT01AN) then participant within cohort      */
proc sort data=eg;
  by &TRTNVAR &TRTVAR subjid AVISITN ATPTN PARAMCD;
run;

%tfltitle(num=16.2.7.3, type=Listing,
   text=%str(Listing of Electrocardiogram (ECG) Results),
   pop=Safety Population,
   foot=%str(* = value outside reference range (ADaM ANRIND). CHG = change from baseline. QTcF = Fridericia-corrected QT. Single dose per participant; participants grouped by ascending dose level. Times relative to dosing.));
proc report data=eg nowd split='|';
  columns &TRTVAR subjid AGE SEX PARAM AVISIT ATPT ADT
          AVAL flag BASE cchg ANRIND EGINTP;
  define &TRTVAR / order 'Dose|Level'           width=14;
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
