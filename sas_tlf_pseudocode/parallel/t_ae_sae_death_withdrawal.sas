/******************************************************************************
* TABLE     : t_ae_sae_death_withdrawal  (Parallel-group)
* TITLE     : Serious Adverse Events, Deaths, and Adverse Events Leading to
*             Study Drug Withdrawal by System Organ Class and Preferred Term
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (TRTEMFL='Y'; AESER, AESDTH/AEOUT, AEACN)
* NOTE      : PSEUDOCODE. Three stacked panels, each = PARTICIPANTS with >=1
*             qualifying event (distinct USUBJID), NOT event rows:
*               (A) Serious TEAE        (AESER='Y')
*               (B) TEAE leading to death (AESDTH='Y' or AEOUT='FATAL')
*               (C) TEAE leading to withdrawal of study drug (AEACN='DRUG WITHDRAWN')
*             n (%) per arm; % denominator = SAFFL N per arm. SOC by overall
*             frequency desc; PT within SOC desc.
*             Parallel design: column var = TRT01A/TRT01AN (= dose level).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);                 /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/* treatment-emergent records from the Safety population, with category flags    */
data adae; set adam.adae(where=(TRTEMFL='Y' and SAFFL='Y'));
  serfl = (AESER='Y');                                   /* serious                 */
  dthfl = (AESDTH='Y' or upcase(AEOUT)='FATAL');         /* led to death            */
  wdfl  = (upcase(AEACN)='DRUG WITHDRAWN');              /* led to drug withdrawal  */
run;

/*--- reusable build: Any -> SOC -> indented PT for one category ---------------*/
%macro panel(where=, anylbl=, panel=, out=);
  /* any (overall) */
  %aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, where=%str(&where),
           byvars=%str(_dummy), out=_p_any);
  /* by SOC */
  %aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, where=%str(&where),
           byvars=%str(AESOC), out=_p_soc);
  /* by SOC*PT */
  %aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, where=%str(&where),
           byvars=%str(AESOC AEDECOD), out=_p_socpt);
  data &out;
    set _p_any(in=a) _p_soc(in=s) _p_socpt(in=p);
    length panel $60 term $200;
    panel="&panel";
    if a then do; term="&anylbl"; level=0; end;
    else if s then do; term=AESOC; level=1; end;
    else do; term='   '||AEDECOD; level=2; end;
    /* value = catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)'))     */
  run;
%mend panel;

%panel(where=%str(serfl=1), anylbl=%str(Participants with any serious TEAE),
       panel=%str(Serious TEAEs), out=_a);
%panel(where=%str(dthfl=1), anylbl=%str(Participants with any TEAE leading to death),
       panel=%str(TEAEs Leading to Death), out=_b);
%panel(where=%str(wdfl=1),  anylbl=%str(Participants with any TEAE leading to withdrawal),
       panel=%str(TEAEs Leading to Study Drug Withdrawal), out=_c);

/*--- panel order, then SOC by total freq desc, PT within SOC desc -------------*/
data _rep; set _a(in=a) _b(in=b) _c(in=c);
  if a then pord=1; else if b then pord=2; else pord=3;
run;
/* merge socn/ptn (Total-column participant counts) within panel for sort keys       */

proc sort data=_rep; by pord panel /*socn ptn*/ level term; run;
proc transpose data=_rep out=_wide; by pord panel level term; id &TRTNVAR; var value; run;

%tfltitle(num=14.3.1.4, type=Table,
   text=%str(Serious Adverse Events, Deaths, and Adverse Events Leading to Study Drug Withdrawal),
   pop=Safety Population,
   foot=%str(All counts are treatment-emergent. A participant is counted once at each level within a panel. % = participants / N in arm. MedDRA v27.0.));
proc report data=_wide nowd split='|';
  columns pord panel level term ("Treatment (Dose)" /* dose cols + Total */);
  define pord  / order noprint;
  define panel / order 'Category' width=18 flow;
  define level / noprint;
  define term  / order 'System Organ Class|  Preferred Term' width=38 flow;
  break after panel / skip;                    /* blank line between panels       */
run;
