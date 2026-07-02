/******************************************************************************
* LISTING   : l_ae  (Crossover - 2x2 or Williams)
* TITLE     : Listing of Adverse Events
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE
* NOTE      : PSEUDOCODE. One row per AE record. Crossover -> show the analysis
*             treatment at onset (TRTA), the period (APERIODC) and the participant's
*             sequence (TRTSEQP) so each event is anchored to a treatment period.
*             Ordered by sequence, participant, period, then onset. Flags SAE / TEAE
*             / relationship / action / outcome. Listings show all events (not
*             just treatment-emergent).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);            /* TRTVAR=TRTA SEQVAR=TRTSEQP
                                             BYPERIOD=APERIOD APERIODC         */

data ae;
  set adam.adae(where=(SAFFL='Y'));
  length subjid $20 seq $12 perc $12 trt $40 relday $8 sev $12 ser $4 rel $20 acn $24 out $24 te $4;
  subjid = scan(USUBJID,-1,'-');            /* short site-participant id          */
  seq    = &SEQVAR;                          /* TRTSEQP e.g. 'TR' / 'RT'       */
  perc   = APERIODC;                         /* analysis period label          */
  trt    = &TRTVAR;                          /* TRTA: treatment at onset       */
  sev    = put(AESEVN, aesev.);              /* MILD/MODERATE/SEVERE           */
  rel    = AREL;                             /* analysis relationship          */
  ser    = ifc(AESER='Y','Yes','No');
  te     = ifc(TRTEMFL='Y','Yes','No');
  acn    = AEACN;                            /* action taken w/ study drug     */
  out    = AEOUT;                            /* outcome                        */
  relday = ifc(missing(ASTDY),' ',put(ASTDY,4.));   /* study day of onset      */
  durn   = ADURN;                            /* duration (n)                   */
  keep seq perc trt subjid AEDECOD AESOC ASTDT relday durn sev ser rel te acn out APERIOD;
run;

proc sort data=ae; by seq subjid APERIOD ASTDT AEDECOD; run;

%tfltitle(num=16.2.7.1, type=Listing, text=Listing of Adverse Events,
          pop=Safety Population,
          foot=%str(Crossover: Seq = randomized treatment sequence (TRTSEQP); Period = analysis period (APERIODC); Treatment = analysis treatment at onset (TRTA). TEAE = treatment-emergent. SAE = serious. Rel = relationship to study drug per analysis. MedDRA v27.0.));
proc report data=ae nowd split='*';
  columns seq subjid perc trt ('Adverse Event' AESOC AEDECOD)
          ('Onset*(Day)' relday) durn sev ('Serious' ser) ('TEAE' te)
          ('Relationship' rel) ('Action Taken' acn) ('Outcome' out);
  define seq    / order 'Sequence'  width=10;
  define subjid / order 'Participant'   width=12;
  define perc   / order 'Period'    width=10;
  define trt    / display 'Treatment' width=16 flow;
  define AESOC  / display 'System Organ Class' width=22 flow;
  define AEDECOD/ display 'Preferred Term'     width=22 flow;
  define relday / display center width=6;
  define durn   / display 'Dur*(days)' center width=6;
  define sev    / display 'Severity'  width=10;
  define ser    / display center width=7;
  define te     / display center width=6;
  define rel    / display width=14 flow;
  define acn    / display width=16 flow;
  define out    / display width=16 flow;
  break after seq / page;                    /* one sequence block per page    */
run;
