/******************************************************************************
* LISTING   : l_ae  (Multiple Ascending Dose)
* TITLE     : Listing of Adverse Events by Dose Level
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE
* NOTE      : PSEUDOCODE. One row per AE record, ordered by dose level then
*             participant then onset. Flags SAE / TEAE / relationship / action /
*             outcome. Listings show all events (not just treatment-emergent).
*             MAD design: page-break by dose level (TRT01A); repeated dosing,
*             so onset study day (ASTDY) can span the multiple-dose period -
*             the study day relative to first dose lets the reviewer place each
*             event within the dosing period. Treatment/period vars come from
*             ADaM (no re-derivation).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* TRTVAR=TRT01A             */

data ae;
  set adam.adae(where=(SAFFL='Y'));
  length subjid $20 trt $40 relday $8 sev $12 ser $4 rel $20 acn $24 out $24 te $4;
  subjid = scan(USUBJID,-1,'-');            /* short site-participant id        */
  trt    = &TRTVAR;                         /* dose level (= treatment)     */
  sev    = put(AESEVN, aesev.);             /* MILD/MODERATE/SEVERE         */
  rel    = AREL;                            /* analysis relationship        */
  ser    = ifc(AESER='Y','Yes','No');
  te     = ifc(TRTEMFL='Y','Yes','No');
  acn    = AEACN;                           /* action taken w/ study drug   */
  out    = AEOUT;                           /* outcome                      */
  relday = ifc(missing(ASTDY),' ',put(ASTDY,4.));   /* study day of onset (rel first dose) */
  durn   = ADURN;                           /* duration (n)                 */
keep trt subjid AEDECOD AESOC ASTDT relday durn sev ser rel te acn out &TRTNVAR;
run;

/* order by ascending dose level, then participant, then onset                   */
proc sort data=ae; by &TRTNVAR subjid ASTDT AEDECOD; run;

%tfltitle(num=16.2.7.1, type=Listing, text=Listing of Adverse Events by Dose Level,
          pop=Safety Population,
          foot=%str(TEAE = treatment-emergent over the multiple-dose period. SAE = serious. Rel = relationship to study drug per investigator/analysis. Onset day relative to first dose. MedDRA v27.0.));
proc report data=ae nowd split='*';
  columns &TRTNVAR trt subjid ('Adverse Event' AESOC AEDECOD)
          ('Onset*(Day)' relday) durn sev ('Serious' ser) ('TEAE' te)
          ('Relationship' rel) ('Action Taken' acn) ('Outcome' out);
  define &TRTNVAR / order noprint;          /* ascending-dose sort key      */
  define trt    / order 'Dose Level' width=18;
  define subjid / order 'Participant'   width=12;
  define AESOC  / display 'System Organ Class' width=24 flow;
  define AEDECOD/ display 'Preferred Term'     width=24 flow;
  define relday / display center width=6;
  define durn   / display 'Dur*(days)' center width=6;
  define sev    / display 'Severity'  width=10;
  define ser    / display center width=7;
  define te     / display center width=6;
  define rel    / display width=14 flow;
  define acn    / display width=16 flow;
  define out    / display width=16 flow;
  break after &TRTNVAR / page;              /* one dose level per page block */
run;
