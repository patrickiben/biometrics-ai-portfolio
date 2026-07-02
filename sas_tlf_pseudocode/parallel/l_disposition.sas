/******************************************************************************
* LISTING   : l_disposition  (Parallel-group)
* TITLE     : Listing of Participant Disposition
* POPULATION: All Enrolled Participants
* INPUT     : ADSL
* NOTE      : PSEUDOCODE. One row per participant, ordered by treatment then
*             participant. Shows population/disposition flags, completion status,
*             discontinuation reason and key milestone dates. Parallel: one
*             treatment per participant; column var = TRT01A (= dose level for
*             ascending-dose layouts).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);                 /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

data disp;
  set adam.adsl(where=(ENRLFL='Y'));
  length subjid $20 trt $40 site $12 rand $4 saff $4 pkf $4 comp $4 dcsr $40;
  subjid = scan(USUBJID,-1,'-');            /* short site-participant id          */
  site   = SITEID;
  trt    = &TRTVAR;                          /* assigned treatment/dose level  */
  rand   = ifc(RANDFL='Y','Yes','No');
  saff   = ifc(SAFFL='Y','Yes','No');
  pkf    = ifc(PKFL='Y','Yes','No');
  comp   = ifc(COMPLFL='Y','Completed', ifc(DCSFL='Y','Discontinued',' '));
  dcsr   = DCSREAS;                          /* discontinuation reason         */
  /* milestone dates kept as ADaM numeric *DT, displayed with date9.          */
  keep site trt subjid rand saff pkf comp dcsr RANDDT TRTSDT TRTEDT EOSDT TRT01AN;
run;

proc sort data=disp; by TRT01AN trt site subjid; run;

%tfltitle(num=16.2.1, type=Listing, text=Listing of Participant Disposition,
          pop=All Enrolled Participants,
          foot=%str(Rand = randomized; SAF = Safety Population; PK = PK Population. Status and reason from ADSL (COMPLFL/DCSFL/DCSREAS).));
proc report data=disp nowd split='*';
  columns trt site subjid ('Populations' rand saff pkf)
          RANDDT TRTSDT TRTEDT EOSDT ('Status' comp) ('Reason for*Discontinuation' dcsr);
  define trt    / order 'Treatment' width=18 flow;
  define site   / order 'Site'      width=8;
  define subjid / order 'Participant'   width=12;
  define rand   / display 'Rand'    center width=6;
  define saff   / display 'SAF'     center width=6;
  define pkf    / display 'PK'      center width=6;
  define RANDDT / display 'Rand*Date'   format=date9. width=10;
  define TRTSDT / display 'First*Dose'  format=date9. width=10;
  define TRTEDT / display 'Last*Dose'   format=date9. width=10;
  define EOSDT  / display 'End of*Study' format=date9. width=10;
  define comp   / display 'Status'      width=14 flow;
  define dcsr   / display width=22 flow;
  break after trt / page;                    /* one treatment per page block  */
run;
