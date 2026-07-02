/******************************************************************************
* LISTING   : l_disposition  (Crossover - 2x2 or Williams)
* TITLE     : Listing of Participant Disposition
* POPULATION: All Enrolled Participants (ENRLFL='Y')
* INPUT     : ADSL
* NOTE      : PSEUDOCODE. One row per participant. Shows the randomized SEQUENCE
*             (TRTSEQP) and the per-period treatments (TRTA in APERIOD 1..k) so
*             the within-participant crossover is visible at a glance, plus per-period
*             completion, the period of any discontinuation (DCPERIOD), reason
*             (DCSREAS), and population flags. Listings show ALL ENROLLED
*             participants (incl. screen failures / pre-dose discontinuations);
*             SAFFL/PKFL shown as Yes/No so they stay visible. Ordered by sequence
*             then participant. The per-period treatment
*             columns are derived for display only from ADSL TRTxxA fields (no
*             re-derivation of analysis variables).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* SEQVAR=TRTSEQP TRTVAR=TRTA BYPERIOD=APERIOD */

data dispo;
  set adam.adsl(where=(ENRLFL='Y'));
  length subjid $20 seq $20 p1trt $24 p2trt $24 compl $20 dcper $8 dcreas $40
         saf $4 pk $4;
  subjid = scan(USUBJID,-1,'-');                 /* short site-participant id      */
  seq    = &SEQVAR;                              /* randomized sequence        */
  /* per-period planned/analysis treatments carried on ADSL (display only)    */
  p1trt  = TRT01A;                               /* Period 1 treatment         */
  p2trt  = TRT02A;                               /* Period 2 treatment         */
  /* for Williams designs add p3trt=TRT03A, p4trt=TRT04A as needed            */
  compl  = ifc(COMPLFL='Y','Completed All','Discontinued');
  dcper  = ifc(DCPERIOD=.,' ',cats('Period ',put(DCPERIOD,1.)));
  dcreas = DCSREAS;                              /* reason if discontinued     */
  saf    = ifc(SAFFL='Y','Yes','No');
  pk     = ifc(PKFL='Y','Yes','No');
  keep subjid TRTSEQPN seq p1trt p2trt compl dcper dcreas saf pk RFSTDTC RFENDTC;
run;

proc sort data=dispo; by TRTSEQPN subjid; run;

%tfltitle(num=16.2.1, type=Listing, text=Listing of Participant Disposition,
          pop=All Enrolled Participants,
          foot=%str(One row per enrolled participant (incl. screen failures / pre-dose discontinuations). SEQ = randomized treatment sequence (TRTSEQP). Period treatments are the analysis treatment per period. SAF/PK = analysis-population membership (Yes/No). DC Period = period in which discontinuation occurred.));
proc report data=dispo nowd split='*';
  columns TRTSEQPN seq subjid ('Treatment by Period' p1trt p2trt)
          ('First*Dose' RFSTDTC) ('Last*Contact' RFENDTC)
          compl ('Disc.*Period' dcper) ('Discontinuation Reason' dcreas)
          ('Population' saf pk);
  define TRTSEQPN / order noprint;
  define seq      / order 'Sequence'  width=12;
  define subjid   / order 'Participant'   width=12;
  define p1trt    / display 'Period 1' width=16 flow;
  define p2trt    / display 'Period 2' width=16 flow;
  define RFSTDTC  / display center width=10;
  define RFENDTC  / display center width=10;
  define compl    / display 'Status'   width=12;
  define dcper    / display center width=8;
  define dcreas   / display width=22 flow;
  define saf      / display 'SAF' center width=5;
  define pk       / display 'PK'  center width=5;
  break after TRTSEQPN / skip;                   /* group rows by sequence     */
run;
