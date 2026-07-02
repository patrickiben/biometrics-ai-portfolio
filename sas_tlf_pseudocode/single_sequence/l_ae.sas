/******************************************************************************
* LISTING   : l_ae  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Listing of Adverse Events by Period
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE
* NOTE      : PSEUDOCODE. One row per AE record, ordered by participant then
*             period then onset. Shows the fixed PERIOD (APERIODC) and the
*             analysis treatment in effect (TRTA, e.g. victim alone vs
*             victim + perpetrator); NO randomized sequence. Flags SAE / TEAE /
*             relationship / action / outcome. Listings show all events
*             (not just treatment-emergent).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA; BYPERIOD=APERIOD APERIODC */

data ae;
  set adam.adae(where=(SAFFL='Y'));
  length subjid $20 perc $24 trt $40 relday $8 sev $12 ser $4 rel $20 acn $24 out $24 te $4;
  subjid = scan(USUBJID,-1,'-');            /* short site-participant id        */
  perc   = APERIODC;                         /* fixed period (col by-var)    */
  trt    = TRTA;                             /* treatment in effect in period*/
  sev    = put(AESEVN, aesev.);              /* MILD/MODERATE/SEVERE         */
  rel    = AREL;                             /* analysis relationship        */
  ser    = ifc(AESER='Y','Yes','No');
  te     = ifc(TRTEMFL='Y','Yes','No');
  acn    = AEACN;                            /* action taken w/ study drug   */
  out    = AEOUT;                            /* outcome                      */
  relday = ifc(missing(ASTDY),' ',put(ASTDY,4.));   /* study day of onset   */
  durn   = ADURN;                            /* duration (n)                 */
keep subjid APERIOD perc trt AEDECOD AESOC ASTDT relday durn sev ser rel te acn out;
run;

proc sort data=ae; by subjid APERIOD ASTDT AEDECOD; run;

%tfltitle(num=16.2.7.1, type=Listing, text=Listing of Adverse Events by Period,
          pop=Safety Population,
          foot=%str(TEAE = treatment-emergent. SAE = serious. Rel = relationship to study drug per investigator/analysis. Period 1 = reference; later period(s) = test condition. MedDRA v27.0.));
proc report data=ae nowd split='*';
  columns subjid perc trt ('Adverse Event' AESOC AEDECOD)
          ('Onset*(Day)' relday) durn sev ('Serious' ser) ('TEAE' te)
          ('Relationship' rel) ('Action Taken' acn) ('Outcome' out);
  define subjid / order 'Participant'   width=12;
  define perc   / order 'Period'    width=16 flow;
  define trt    / display 'Treatment' width=18 flow;
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
  break after subjid / skip;                 /* group records by participant     */
run;
