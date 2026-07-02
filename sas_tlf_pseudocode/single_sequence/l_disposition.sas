/******************************************************************************
* LISTING   : l_disposition  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Listing of Participant Disposition and Period Completion
* POPULATION: All Enrolled Participants
* INPUT     : ADSL
* NOTE      : PSEUDOCODE. One row per participant, ordered by fixed sequence then
*             participant. ALL ENROLLED -- NOT filtered to SAFFL -- so screen-fail
*             and pre-dose discontinuations remain visible; SAFFL/PKFL are shown as
*             Yes/No columns rather than used as a row filter. Single-/fixed-sequence
*             design: shows the ONE fixed treatment order (&SEQVAR = TRTSEQP,
*             participant-level on ADSL) plus per-PERIOD start dates and completion
*             status (reference period = Period 1, victim alone; test period =
*             Period 2, victim + perpetrator), so a participant who completes the
*             reference period but discontinues before/within the test period is
*             visible. All status variables pulled from ADSL (no re-derivation).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* SEQVAR=TRTSEQP SEQVARN=TRTSEQPN (participant-level); BYPERIOD=APERIOD APERIODC */

data disp;
  set adam.adsl;
  length subjid $20 seq $40 saf $4 pk $4
         p1stat $14 p2stat $14 eos $16 dcr $40;
  subjid = scan(USUBJID,-1,'-');                 /* short site-participant id     */
  seq    = &SEQVAR;                              /* fixed treatment order (TRTSEQP, participant-level) */
  saf    = ifc(SAFFL='Y','Yes','No');
  pk     = ifc(PKFL='Y','Yes','No');
  /* per-period dosing/completion from ADSL period flags (no re-derivation):
     COMPP1FL/COMPP2FL = completed reference/test period; TR0nSDTM = period
     dose start.                                                              */
  p1stat = ifc(COMPP1FL='Y','Completed',ifc(missing(TR01SDTM),'Not dosed','Discontinued'));
  p2stat = ifc(COMPP2FL='Y','Completed',ifc(missing(TR02SDTM),'Not dosed','Discontinued'));
  eos    = propcase(EOSSTT);                     /* COMPLETED / DISCONTINUED  */
  dcr    = ifc(upcase(EOSSTT)='DISCONTINUED',DCSREAS,'');  /* reason only for discontinuations */
  keep subjid &SEQVARN seq saf pk RFSTDTC p1stat p2stat eos dcr;
run;

proc sort data=disp; by &SEQVARN subjid; run;        /* sequence (numeric key) then participant */

%tfltitle(num=16.2.1, type=Listing,
   text=%str(Listing of Participant Disposition and Period Completion),
   pop=All Enrolled Participants,
   foot=%str(Period 1 = reference (victim alone); Period 2 = test (victim + perpetrator). Period status from ADSL completion flags. EOS = end-of-study status; reason shown for discontinuations. All participants receive the same fixed sequence.));
proc report data=disp nowd split='*';
  columns &SEQVARN seq subjid saf pk ('First*Dose Date' RFSTDTC)
          ('Period 1*(Reference)' p1stat) ('Period 2*(Test)' p2stat)
          ('End of Study' eos) ('Discontinuation*Reason' dcr);
  define &SEQVARN / order noprint;                    /* numeric sequence sort key */
  define seq     / order 'Sequence' width=22 flow;
  define subjid  / order 'Participant'  width=12;
  define saf     / display 'Safety*Pop' center width=7;
  define pk      / display 'PK*Pop'    center width=6;
  define RFSTDTC / display center width=12;
  define p1stat  / display center width=12;
  define p2stat  / display center width=12;
  define eos     / display center width=14;
  define dcr     / display width=22 flow;
run;
