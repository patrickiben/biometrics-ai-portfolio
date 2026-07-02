/******************************************************************************
* TABLE     : t_ae_by_relationship  (Multiple Ascending Dose)
* TITLE     : Drug-Related Treatment-Emergent Adverse Events by System Organ
*             Class and Preferred Term, by Dose Level
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (TRTEMFL='Y'; relationship from AREL)
* NOTE      : PSEUDOCODE. Drug-related = AREL in (RELATED/POSSIBLE/PROBABLE/
*             DEFINITE) per analysis-relationship convention. Counts = PARTICIPANTS
*             with >=1 related event (distinct USUBJID), NOT event rows. n (%)
*             per dose level; % denominator = SAFFL N per dose column. SOC sorted
*             by overall related-event frequency desc; PT within SOC desc.
*             MAD design: column var = TRT01A/TRT01AN (= dose level); placebo
*             pooled in ADaM; relationship assessed over the multiple-dose period.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* TRTVAR=TRT01A             */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/* treatment-emergent AND drug-related, Safety population                    */
data adae;
  set adam.adae(where=(TRTEMFL='Y' and SAFFL='Y'));
  if upcase(AREL) in ('RELATED','POSSIBLE','PROBABLE','DEFINITE');  /* related */
run;

/*--- 1) "Any related TEAE" overall row (distinct participants) --------------*/
%aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, where=%str(1),
         byvars=%str(_dummy), out=_any);   /* _dummy=1 -> overall row      */

/*--- 2) by SOC (distinct participants within SOC) ---------------------------*/
%aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, where=%str(1),
         byvars=%str(AESOC), out=_soc);

/*--- 3) by SOC*PT (distinct participants within SOC and PT) -----------------*/
%aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, where=%str(1),
         byvars=%str(AESOC AEDECOD), out=_socpt);

/*--- ordering: SOC by total-column participant count desc; PT within SOC desc */
proc sql;
  create table _socord as
    select AESOC, sum(nsubj) as socn from _soc group by AESOC;
  create table _ptord as
    select AESOC, AEDECOD, sum(nsubj) as ptn from _socpt
    group by AESOC, AEDECOD;
quit;
/* merge socn/ptn back for sort keys; indent PT under SOC (leading spaces) */

/*--- assemble report shell: Any related TEAE -> SOC -> indented PT ------*/
data _rep;
  set _any(in=a) _soc(in=s) _socpt(in=p);
  length term $200;
  if a then do; term='Participants with any drug-related TEAE'; level=0; end;
  else if s then do; term=AESOC;                            level=1; end;
  else do; term='   '||AEDECOD;                              level=2; end;
  /* value = catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)')) */
run;
proc transpose data=_rep out=_wide; by socn ptn level term; id &TRTNVAR; var value; run;

%tfltitle(num=14.3.1.3, type=Table,
   text=%str(Drug-Related Treatment-Emergent Adverse Events by System Organ Class and Preferred Term, by Dose Level),
   pop=Safety Population,
   foot=%str(Drug-related per analysis relationship (AREL). A participant is counted once at each level. Columns = ascending dose levels (placebo pooled). MedDRA v27.0. %% = participants with the event / N in dose column.));
proc report data=_wide nowd split='|';
  columns socn ptn level term ("Dose Level" /* ascending dose cols + Total */);
  define socn  / order descending noprint;
  define ptn   / order descending noprint;
  define term  / order 'System Organ Class|  Preferred Term' width=40 flow;
  /* define <each TRT01AN col> / display center "&header (N=&n)"; ordered ascending dose */
run;
