/******************************************************************************
* LISTING   : l_disposition  (Multiple Ascending Dose)
* TITLE     : Listing of Participant Disposition
* POPULATION: All Enrolled Participants
* INPUT     : ADSL
* NOTE      : PSEUDOCODE. One row per participant, ordered by dose level then
*             participant. Shows population/disposition flags, dosing-regimen
*             milestones, completion status, discontinuation reason and key
*             dates. MAD: parallel ascending-dose cohorts, one dose level per
*             participant; column var = TRT01A (= dose level). Because dosing is
*             repeated, the listing carries NUMBER OF DOSES, completed-regimen
*             status and the PK steady-state flag (PKSSFL) so reviewers can see
*             which participants reached the dosing duration required for
*             steady-state / accumulation (Rac) PK.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

data disp;
  set adam.adsl(where=(ENRLFL='Y'));
  length subjid $20 trt $40 site $12 rand $4 saff $4 pkf $4 pkss $4 sstat $14 comp $4 dcsr $40;
  subjid = scan(USUBJID,-1,'-');            /* short site-participant id          */
  site   = SITEID;
  trt    = &TRTVAR;                          /* assigned dose level            */
  rand   = ifc(RANDFL='Y','Yes','No');
  saff   = ifc(SAFFL='Y','Yes','No');
  pkf    = ifc(PKFL='Y','Yes','No');
  pkss   = ifc(PKSSFL='Y','Yes','No');       /* PK steady-state population      */
  sstat  = EOSSTT;                            /* study status: COMPLETED/DISCONTINUED */
  comp   = ifc(COMPLFL='Y','Yes','No');      /* completed full dosing regimen      */
  dcsr   = DCSREAS;                          /* discontinuation reason (blank if completed) */
  /* CUMDOSEN = number of doses received (ADSL exposure summary var)           */
  /* milestone dates kept as ADaM numeric *DT, displayed with date9.           */
  keep site trt subjid rand saff pkf pkss sstat comp dcsr CUMDOSEN
       RANDDT TRTSDT TRTEDT EOSDT TRT01AN;
run;

proc sort data=disp; by TRT01AN trt site subjid; run;

%tfltitle(num=16.2.1, type=Listing, text=Listing of Participant Disposition,
          pop=All Enrolled Participants,
          foot=%str(Treatment = assigned dose level (TRT01A). Rand = randomized; SAF = Safety Population; PK = PK Population; PKss = PK Steady-State Population. First/Last Dose span the multiple-dose regimen; #Doses = number of doses received. Study Status = EOSSTT; Completed = completed full dosing regimen (COMPLFL); Reason from ADSL DCSREAS (blank if completed). Listed on All Enrolled so screen-failures and pre-dose discontinuations remain visible.));
proc report data=disp nowd split='*';
  columns trt site subjid ('Populations' rand saff pkf pkss)
          RANDDT TRTSDT TRTEDT CUMDOSEN EOSDT
          ('Status' sstat comp) ('Reason for*Discontinuation' dcsr);
  define trt    / order 'Dose Level' width=18 flow;
  define site   / order 'Site'      width=8;
  define subjid / order 'Participant'   width=12;
  define rand   / display 'Rand'    center width=6;
  define saff   / display 'SAF'     center width=6;
  define pkf    / display 'PK'      center width=6;
  define pkss   / display 'PKss'    center width=6;
  define RANDDT  / display 'Rand*Date'    format=date9. width=10;
  define TRTSDT  / display 'First*Dose'   format=date9. width=10;
  define TRTEDT  / display 'Last*Dose'    format=date9. width=10;
  define CUMDOSEN/ display '#Doses'       width=7 center;
  define EOSDT   / display 'End of*Study' format=date9. width=10;
  define sstat   / display 'Study*Status' width=12 flow;
  define comp    / display 'Completed'    center width=9;
  define dcsr    / display width=22 flow;
  break after trt / page;                    /* one dose-level block per page  */
run;
