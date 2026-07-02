/******************************************************************************
* LISTING   : l_disposition  (Single Ascending Dose)
* TITLE     : Listing of Participant Disposition
* POPULATION: All Enrolled Participants (ENRLFL='Y')
* INPUT     : ADSL
* NOTE      : PSEUDOCODE. One row per participant. SAD: parallel ascending-dose
*             cohorts, ONE treatment per participant -> NO sequence/period columns.
*             Shows the assigned dose level (TRT01A = cohort), enrolled/
*             randomized/safety/PK population flags, single-dose date, study
*             completion status, and reason/date of any discontinuation.
*             Listings show ALL enrolled participants, ordered by ascending dose
*             level (cohort) then participant. Display fields carried from ADSL
*             (no re-derivation of analysis variables).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);           /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN (one trt/subj) */

data dispo;
  set adam.adsl(where=(ENRLFL='Y'));
  length subjid $20 dose $24 compl $20 dcreas $40 rand $4 saf $4 pk $4;
  subjid = scan(USUBJID,-1,'-');                 /* short site-participant id      */
  dose   = &TRTVAR;                              /* assigned dose level/cohort */
  rand   = ifc(RANDFL='Y','Yes','No');
  saf    = ifc(SAFFL='Y','Yes','No');            /* received single dose       */
  pk     = ifc(PKFL='Y','Yes','No');
  compl  = ifc(COMPLFL='Y','Completed','Discontinued');
  dcreas = DCSREAS;                              /* reason if discontinued     */
  /* RFSTDTC = single-dose date; RFENDTC = last study contact (display only)   */
  keep &TRTNVAR subjid dose rand saf pk RFSTDTC RFENDTC compl DCSDTC dcreas;
run;

proc sort data=dispo; by &TRTNVAR subjid; run;     /* ascending dose then participant */

%tfltitle(num=16.1.1, type=Listing, text=Listing of Participant Disposition,
          pop=All Enrolled Participants,
          foot=%str(One row per participant. Dose Level = assigned cohort (TRT01A); single dose administered. Rows grouped by ascending dose level. Disc. Date/Reason from ADSL (DCSDTC / DCSREAS).));
proc report data=dispo nowd split='*';
  columns &TRTNVAR dose subjid ('Populations' rand saf pk)
          ('First*Dose' RFSTDTC) ('Last*Contact' RFENDTC)
          compl ('Disc.*Date' DCSDTC) ('Discontinuation Reason' dcreas);
  define &TRTNVAR / order noprint;
  define dose     / order 'Dose Level'  width=16 flow;
  define subjid   / order 'Participant'     width=12;
  define rand     / display 'Rand' center width=5;
  define saf      / display 'SAF'  center width=5;
  define pk       / display 'PK'   center width=5;
  define RFSTDTC  / display center width=10;
  define RFENDTC  / display center width=10;
  define compl    / display 'Status'    width=12;
  define DCSDTC   / display center width=10;
  define dcreas   / display width=22 flow;
  break after &TRTNVAR / skip;                    /* group rows by dose cohort  */
run;
