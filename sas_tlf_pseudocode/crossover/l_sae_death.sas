/******************************************************************************
* LISTING   : l_sae_death  (Crossover - 2x2 or Williams)
* TITLE     : Listing of Serious Adverse Events and Deaths
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (AESER='Y' or AESDTH='Y')
* NOTE      : PSEUDOCODE. One row per serious / fatal AE record. Crossover ->
*             show analysis treatment at onset (TRTA), period (APERIODC) and
*             participant sequence (TRTSEQP) so each SAE is anchored to a treatment
*             period. Ordered by sequence, participant, period, onset. Includes
*             seriousness criteria, relationship, action, outcome and death date.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);            /* TRTVAR=TRTA SEQVAR=TRTSEQP        */

data sae;
  set adam.adae(where=(SAFFL='Y' and (AESER='Y' or AESDTH='Y')));
  length subjid $20 seq $12 perc $12 trt $40 relday $8 sev $12 rel $20 acn $24 out $24 te $4 dthdt $11;
  subjid = scan(USUBJID,-1,'-');
  seq    = &SEQVAR;                          /* TRTSEQP                        */
  perc   = APERIODC;                         /* analysis period label          */
  trt    = &TRTVAR;                          /* TRTA at onset                  */
  sev    = put(AESEVN, aesev.);
  rel    = AREL;                             /* analysis relationship          */
  te     = ifc(TRTEMFL='Y','Yes','No');
  acn    = AEACN;
  out    = AEOUT;
  relday = ifc(missing(ASTDY),' ',put(ASTDY,4.));
  durn   = ADURN;
  dthdt  = ifc(missing(DTHDT),' ',put(DTHDT, yymmdd10.));   /* death date      */
  /* seriousness criteria: build a compact label from AESxxxx flags           */
  length sercrit $60;
  sercrit = catx(', ',
              ifc(AESDTH='Y','Death',''),     ifc(AESLIFE='Y','Life-threat.',''),
              ifc(AESHOSP='Y','Hospitaliz.',''), ifc(AESDISAB='Y','Disability',''),
              ifc(AESCONG='Y','Cong. anomaly',''), ifc(AESMIE='Y','Other med. important',''));
  keep seq perc trt subjid AEDECOD AESOC ASTDT relday durn sev rel te acn out dthdt sercrit APERIOD;
run;

proc sort data=sae; by seq subjid APERIOD ASTDT AEDECOD; run;

%tfltitle(num=16.2.7.2, type=Listing,
          text=Listing of Serious Adverse Events and Deaths,
          pop=Safety Population,
          foot=%str(Includes events with AESER=Y or AESDTH=Y. Crossover: Seq = TRTSEQP; Period = APERIODC; Treatment = TRTA at onset. Criteria from AES* seriousness flags. Rel = analysis relationship. MedDRA v27.0.));
proc report data=sae nowd split='*';
  columns seq subjid perc trt ('Adverse Event' AESOC AEDECOD)
          ('Onset*(Day)' relday) durn sev ('Seriousness*Criteria' sercrit)
          ('TEAE' te) ('Relationship' rel) ('Action Taken' acn)
          ('Outcome' out) ('Death*Date' dthdt);
  define seq    / order 'Sequence'  width=10;
  define subjid / order 'Participant'   width=12;
  define perc   / order 'Period'    width=10;
  define trt    / display 'Treatment' width=14 flow;
  define AESOC  / display 'System Organ Class' width=20 flow;
  define AEDECOD/ display 'Preferred Term'     width=20 flow;
  define relday / display center width=6;
  define durn   / display 'Dur*(days)' center width=6;
  define sev    / display 'Severity'  width=10;
  define sercrit/ display width=18 flow;
  define te     / display center width=6;
  define rel    / display width=14 flow;
  define acn    / display width=14 flow;
  define out    / display width=14 flow;
  define dthdt  / display center width=11;
  break after seq / page;
run;
