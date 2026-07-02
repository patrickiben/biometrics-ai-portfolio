/******************************************************************************
* LISTING   : l_vitals  (Multiple Ascending Dose)
* TITLE     : Listing of Vital Signs
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADVS  (PARAMCD/PARAM, AVAL, BASE, CHG, AVISIT/AVISITN,
*             ATPT/ATPTN, ADT/ADTM, ADY, ANRIND, position)
* NOTE      : PSEUDOCODE. Participant-level listing, one row per vital
*             measurement. MAD design: column var = TRT01A (= dose level,
*             one treatment per participant; placebo pooled in ADaM). With
*             repeated dosing each participant has multiple study days, so rows
*             are sorted within dose level by participant, study day, timepoint,
*             parameter to show the full multiple-dose time course.
*             Out-of-range flagged from ADaM ANRIND.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

/*--- all analysis vital records for safety population -----------------------*/
data vs;
  set adam.advs(where=(SAFFL='Y'
                       and PARAMCD in ('SYSBP','DIABP','PULSE','TEMP','RESP')));
  length subjid $20 flag $1;
  subjid = scan(USUBJID, -1, '-');                 /* short participant id        */
  flag   = ifc(ANRIND in ('LOW','HIGH'), '*', ' ');/* out-of-range marker     */
  /* observed value with ADaM decimal hint; baseline + change carried in ADaM */
  length cval cbase cchg $12;
  cval  = put(AVAL, best8.);
  cbase = put(BASE, best8.);
  cchg  = ifc(AVISITN>0, put(CHG, best8.), ' ');
run;

/*--- sort within dose level by participant, study day, timepoint, parameter -----*/
proc sort data=vs;
  by &TRTNVAR &TRTVAR subjid ADY AVISITN ATPTN PARAMCD;
run;

%tfltitle(num=16.2.7.4, type=Listing,
   text=%str(Listing of Vital Signs),
   pop=Safety Population,
   foot=%str(* = value outside reference range (ADaM ANRIND). CHG = change from baseline (pre-first-dose). Column = dose level, one treatment per participant (MAD; placebo pooled). Rows ordered by study day across the multiple-dose period; times relative to dosing.));
proc report data=vs nowd split='|';
  columns &TRTVAR subjid AGE SEX PARAM ADY AVISIT ATPT ADT
          AVAL flag BASE cchg ANRIND;
  define &TRTVAR / order 'Dose|Level'           width=14;
  define subjid  / order 'Participant'              width=10;
  define AGE     / display 'Age'                width=4;
  define SEX     / display 'Sex'                width=4;
  define PARAM   / order  'Parameter'           width=20;
  define ADY     / order  'Study|Day'           width=6;
  define AVISIT  / order  'Visit'               width=12;
  define ATPT    / display 'Timepoint'          width=14;
  define ADT     / display 'Date'               width=11 format=date9.;
  define AVAL    / display 'Value'              width=8;
  define flag    / display ' '                  width=2;
  define BASE    / display 'Baseline'           width=8;
  define cchg    / display 'Change|from BL'     width=8;
  define ANRIND  / display 'Ref|Range Ind'      width=8;
  break after &TRTVAR / skip;
run;
