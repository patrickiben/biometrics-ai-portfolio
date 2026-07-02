/******************************************************************************
* TABLE     : t_prior_con_meds  (Single Ascending Dose)
* TITLE     : Prior and Concomitant Medications
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADCM
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS with >=1 medication (distinct
*             USUBJID), NOT medication rows. n (%) per column; % denom =
*             SAFFL N per column. Summarized by WHO-DD ATC class (CMCLAS) and
*             Preferred Term (CMDECOD). Prior vs concomitant split by ADCM
*             timing flags (PREFL / ONTRTFL); for SAD, "concomitant" = taken
*             around the single dosing day / PK collection window. SAD:
*             parallel ascending-dose cohorts, ONE treatment per participant;
*             columns = TRT01A = assigned dose level (placebo often pooled).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                      /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/* Safety-population CM records; timing flags from ADCM (no re-derivation).
   PREFL='Y' = started before the single dose (prior);
   ONTRTFL='Y' = concomitant (around single-dose day / PK window).            */
data adcm; set adam.adcm(where=(SAFFL='Y')); run;

/*--- build one block per CM window (Prior, Concomitant) -------------------*
* Each block: Any med (overall) -> ATC class -> indented Preferred Term,
* each = distinct participants (a participant counted once per level).               */
%macro cmblk(flag=, label=, base=);
  /* overall "any" row */
  %aecount(ds=adcm, trtvar=&TRTVAR, popden=_bign, where=%str(&flag='Y'),
           byvars=%str(_dummy), out=_any&base);
  /* by ATC class */
  %aecount(ds=adcm, trtvar=&TRTVAR, popden=_bign, where=%str(&flag='Y'),
           byvars=%str(CMCLAS), out=_cls&base);
  /* by class*PT */
  %aecount(ds=adcm, trtvar=&TRTVAR, popden=_bign, where=%str(&flag='Y'),
           byvars=%str(CMCLAS CMDECOD), out=_clspt&base);

  proc sql;
    create table _clso&base as
      select CMCLAS, sum(nsubj) as clsn from _cls&base group by CMCLAS;
    create table _pto&base as
      select CMCLAS, CMDECOD, sum(nsubj) as ptn from _clspt&base
      group by CMCLAS, CMDECOD;
  quit;

  data _blk&base;
    set _any&base(in=a) _cls&base(in=c) _clspt&base(in=p);
    length term $200 section $20;
    section="&label";
    if a then do; term="Participants with any &label medication"; level=0; end;
    else if c then do; term=CMCLAS;        level=1; end;
    else do; term='   '||CMDECOD;          level=2; end;
    /* value = catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)'))  */
  run;
%mend cmblk;
%cmblk(flag=PREFL,   label=Prior,        base=1);   /* started before single dose */
%cmblk(flag=ONTRTFL, label=Concomitant,  base=2);   /* around dosing / PK window   */

/*--- stack the two windows, order class/PT by Total participant count desc ----*/
data _rep; set _blk1(in=a) _blk2(in=b);
  if a then secord=1; else secord=2;
run;
proc transpose data=_rep out=_wide;
  by secord section clsn ptn level term notsorted; id &TRTNVAR; var value;
run;

%tfltitle(num=14.1.6, type=Table, text=Prior and Concomitant Medications,
          pop=Safety Population,
          foot=%str(A participant is counted once at each level within a window. WHO-DD coding. Prior = started before the single dose; Concomitant = taken around the single-dose day / PK window. Column = assigned dose level (TRT01A); placebo may be pooled. Percentages based on Safety Population N per dose level.));
proc report data=_wide nowd split='|';
  columns secord section clsn ptn level term ("Dose Level" /* dose cols + Total */);
  define secord  / order noprint;
  define section / order noprint;
  define clsn    / order descending noprint;
  define ptn     / order descending noprint;
  define level   / order noprint;
  define term    / order 'ATC Class|  Preferred Term' width=44 flow;
  break before secord / page;                 /* Prior vs Concomitant blocks */
run;
