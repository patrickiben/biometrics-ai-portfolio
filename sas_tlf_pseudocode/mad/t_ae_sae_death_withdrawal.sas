/******************************************************************************
* TABLE     : t_ae_sae_death_withdrawal  (Multiple Ascending Dose)
* TITLE     : Serious Adverse Events, Deaths, and Adverse Events Leading to
*             Study Discontinuation by Preferred Term, by Dose Level
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (AESER, AESDTH/AEOUT, AEACN)
* NOTE      : PSEUDOCODE. Three stacked panels in one table:
*               Panel A - Serious AEs                (AESER='Y')
*               Panel B - AEs leading to death       (AESDTH='Y' or AEOUT=FATAL)
*               Panel C - AEs leading to study drug withdrawal (AEACN='DRUG WITHDRAWN')
*             Counts = PARTICIPANTS with >=1 qualifying event (distinct USUBJID),
*             NOT event rows. n (%) per dose level; % denominator = SAFFL N per
*             dose column. PT within each panel sorted by overall freq desc.
*             SAEs/deaths are typically reported regardless of treatment-
*             emergence; emergence is shown in the AE listings.
*             MAD design: column var = TRT01A/TRT01AN (= dose level); placebo
*             pooled in ADaM; events captured over the multiple-dose period.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* TRTVAR=TRT01A             */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

data adae; set adam.adae(where=(SAFFL='Y'));
  length serfl dthfl wdfl 3;
  serfl = (AESER='Y');
  dthfl = (AESDTH='Y' or upcase(AEOUT)='FATAL');
  wdfl  = (upcase(AEACN)='DRUG WITHDRAWN');
run;

/*--- one panel = "Any" overall row + by-PT rows for a given flag ----------*/
%macro panel(flag=, panellbl=, ord=);
  /* overall: participants with >=1 qualifying event, per dose + Total */
  %aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, where=%str(&flag=1),
           byvars=%str(_dummy), out=_any&ord);
  /* by preferred term */
  %aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, where=%str(&flag=1),
           byvars=%str(AEDECOD), out=_pt&ord);
  data _p&ord;
    set _any&ord(in=a) _pt&ord(in=p);
    length panel $60 term $200;
    panel="&panellbl"; pord=&ord;
    if a then do; term='Participants with at least one event'; level=0; end;
    else do; term='   '||AEDECOD;                          level=1; end;
    /* value = catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)')) */
  run;
%mend panel;

%panel(flag=serfl, panellbl=%str(Serious Adverse Events),                          ord=1);
%panel(flag=dthfl, panellbl=%str(Adverse Events Leading to Death),                 ord=2);
%panel(flag=wdfl,  panellbl=%str(Adverse Events Leading to Study Drug Withdrawal), ord=3);

data _rep; set _p1 _p2 _p3; run;
/* attach PT overall-freq sort key within panel; transpose to dose columns   */
proc transpose data=_rep out=_wide; by pord panel level term; id &TRTNVAR; var value; run;

%tfltitle(num=14.3.1.4, type=Table,
   text=%str(Serious Adverse Events, Deaths, and Adverse Events Leading to Study Discontinuation by Preferred Term, by Dose Level),
   pop=Safety Population,
   foot=%str(A participant is counted once per preferred term within each panel. Columns = ascending dose levels (placebo pooled). %% = participants with the event / N in dose column. MedDRA v27.0.));
proc report data=_wide nowd split='|';
  columns pord panel level term ("Dose Level" /* ascending dose cols + Total */);
  define pord  / order noprint;
  define panel / order 'Category' width=22 flow;
  define level / order noprint;
  define term  / order 'Preferred Term' width=34 flow;
  /* define <each TRT01AN col> / display center "&header (N=&n)"; ordered ascending dose */
  break after panel / skip;
run;
