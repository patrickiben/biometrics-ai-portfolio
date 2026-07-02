/******************************************************************************
* TABLE     : t_ae_by_relationship  (Single Ascending Dose)
* TITLE     : Treatment-Emergent Adverse Events Related to Study Drug by
*             System Organ Class and Preferred Term and Dose Level
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (TRTEMFL='Y'; AREL = analysis relationship to study drug)
* NOTE      : PSEUDOCODE. Restricted to drug-RELATED treatment-emergent AEs.
*             Counts = PARTICIPANTS with >=1 related event (distinct USUBJID),
*             NOT event rows. n (%) per dose level; % denominator = SAFFL N per
*             dose column. SOC sorted by overall frequency desc; PT within SOC
*             desc.
*             SAD design: parallel ascending-dose cohorts -> column var =
*             TRT01A/TRT01AN (= dose level), ordered ascending; placebo pooled.
*             Drug-related, dose-ordered AE display supports the dose-escalation
*             safety review (SRC/DSMB cohort go/no-go).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                      /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/* treatment-emergent AND related to study drug (analysis relationship AREL)    */
data adae;
  set adam.adae(where=(TRTEMFL='Y' and SAFFL='Y'));
  relfl = (upcase(AREL) in ('RELATED','POSSIBLE','PROBABLE','DEFINITE'));
  if relfl;                                   /* keep related events only        */
run;

/*--- 1) "Any related TEAE" overall row (distinct participants, any related event) -*/
%aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, where=%str(relfl=1),
         byvars=%str(_dummy), out=_any);      /* _dummy=1 -> overall row         */

/*--- 2) by SOC (distinct participants within SOC) ---------------------------------*/
%aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, byvars=%str(AESOC), out=_soc);

/*--- 3) by SOC*PT (distinct participants within SOC and PT) -----------------------*/
%aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, byvars=%str(AESOC AEDECOD), out=_socpt);

/*--- ordering: SOC by total-column participant count desc; PT within SOC desc -----*/
proc sql;
  create table _socord as
    select AESOC, sum(nsubj) as socn from _soc group by AESOC;
  create table _ptord as
    select AESOC, AEDECOD, sum(nsubj) as ptn from _socpt
    group by AESOC, AEDECOD;
quit;
/* merge socn/ptn back for sort keys; indent PT under SOC (leading spaces)       */

/*--- assemble report shell: Any related TEAE -> SOC -> indented PT ------------*/
data _rep;
  set _any(in=a) _soc(in=s) _socpt(in=p);
  length term $200;
  if a then do; term='Participants with any related TEAE'; level=0; end;
  else if s then do; term=AESOC;                        level=1; end;
  else do; term='   '||AEDECOD;                          level=2; end;
  /* value = catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)'))       */
run;
/* columns ordered ASCENDING by dose (TRT01AN) + Total                           */
proc transpose data=_rep out=_wide; by socn ptn level term; id &TRTNVAR; var value; run;

%tfltitle(num=14.3.1.3, type=Table,
   text=%str(Treatment-Emergent Adverse Events Related to Study Drug by System Organ Class and Preferred Term and Dose Level),
   pop=Safety Population,
   foot=%str(Related = AREL in (Related/Possible/Probable/Definite). A participant is counted once at each level. Columns = ascending dose levels (placebo pooled). % = participants / N in dose column. MedDRA v27.0.));
proc report data=_wide nowd split='|';
  columns socn ptn level term ("Dose Level" /* ascending dose cols + Total */);
  define socn  / order descending noprint;
  define ptn   / order descending noprint;
  define level / noprint;
  define term  / order 'System Organ Class|  Preferred Term' width=40 flow;
run;
