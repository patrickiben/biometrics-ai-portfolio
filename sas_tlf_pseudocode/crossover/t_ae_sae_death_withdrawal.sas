/******************************************************************************
* TABLE     : t_ae_sae_death_withdrawal  (Crossover - 2x2 or Williams)
* TITLE     : Serious Adverse Events, Deaths, and Adverse Events Leading to
*             Study Discontinuation by System Organ Class and Preferred Term
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (TRTEMFL='Y'), ADEX (per-treatment exposed N)
* NOTE      : PSEUDOCODE. Three stacked panels (SAE / Death / AE leading to
*             discontinuation), each: distinct USUBJID by SOC and PT. Columns =
*             analysis treatment (TRTA) + Total; % denominator = treatment-
*             exposed N (from %bign on ADEX). Within-participant crossover -> a
*             participant may appear under more than one treatment column.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);            /* TRTVAR=TRTA  TRTNVAR=TRTAN       */

/* per-treatment exposed denominators (crossover)                             */
proc sql;
  create table _bign as
    select TRTA as trt length=200, TRTAN as trtn, count(distinct USUBJID) as N
      from adam.adex where SAFFL='Y' group by TRTA, TRTAN
    union all
    select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as N
      from adam.adex where SAFFL='Y';
quit;

data adae; set adam.adae(where=(TRTEMFL='Y' and SAFFL='Y')); run;

/*--- one reusable panel: Any -> SOC -> indented PT, distinct participants -------*/
%macro panel(pnl=, anylab=, where=, base=);
  %aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, where=%str(&where),
           byvars=%str(_dummy), out=&base._any);
  %aecount(ds=adae(where=(&where)), trtvar=&TRTVAR, popden=_bign,
           byvars=%str(AESOC), out=&base._soc);
  %aecount(ds=adae(where=(&where)), trtvar=&TRTVAR, popden=_bign,
           byvars=%str(AESOC AEDECOD), out=&base._socpt);
  data &base;
    set &base._any(in=a) &base._soc(in=s) &base._socpt(in=p);
    length panel $50 term $200;  panel="&pnl";  pord=&&&base._ord;
    if a then do; term="&anylab"; level=0; end;
    else if s then do; term=AESOC; level=1; end;
    else do; term='   '||AEDECOD; level=2; end;
    /* value = catx(' ',put(nsubj,4.),cats('(',put(100*nsubj/N,5.1),'%)'))      */
  run;
%mend;

%let p1_ord=1; %panel(pnl=%str(Serious Adverse Events), base=p1,
        anylab=%str(Participants with any serious TEAE),
        where=%str(AESER='Y'));
%let p2_ord=2; %panel(pnl=%str(Adverse Events Leading to Death), base=p2,
        anylab=%str(Participants with any TEAE leading to death),
        where=%str(AESDTH='Y'));
%let p3_ord=3; %panel(pnl=%str(Adverse Events Leading to Discontinuation), base=p3,
        anylab=%str(Participants with any TEAE leading to discontinuation),
        where=%str(AEACN='DRUG WITHDRAWN'));

data _rep; set p1 p2 p3; run;
proc transpose data=_rep out=_wide; by pord panel level term; id &TRTNVAR; var value; run;

%tfltitle(num=14.3.1.5, type=Table,
   text=%str(Serious Adverse Events, Deaths, and Adverse Events Leading to Study Discontinuation),
   pop=Safety Population,
   foot=%str(SAE per AESER; death per AESDTH; discontinuation per AEACN=DRUG WITHDRAWN. Events attributed to TRTA at onset; within-participant crossover -> a participant may appear under more than one treatment. A participant is counted once at each level. MedDRA v27.0.));
proc report data=_wide nowd split='|';
  columns pord panel level term ("Analysis Treatment" /* TRTAN cols + Total */);
  define pord  / order noprint;
  define panel / order 'Category' width=22 flow;
  define level / order noprint;
  define term  / order 'System Organ Class|  Preferred Term' width=38 flow;
  break after panel / skip;
run;
