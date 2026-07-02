/******************************************************************************
* TABLE     : t_ae_by_soc_pt  (Parallel-group)
* TITLE     : Treatment-Emergent Adverse Events by System Organ Class and
*             Preferred Term
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (TRTEMFL='Y')
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS with >=1 event (distinct USUBJID),
*             NOT event rows. n (%) per arm; % denominator = SAFFL N per arm.
*             SOC sorted by overall frequency desc; PT within SOC desc.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);                 /* TRTVAR=TRT01A             */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/* treatment-emergent only; keep participants from the Safety population        */
data adae; set adam.adae(where=(TRTEMFL='Y' and SAFFL='Y')); run;

/*--- 1) "Any TEAE" overall row (distinct participants, any event) -----------*/
%aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, where=%str(TRTEMFL='Y'),
         byvars=%str(_dummy), out=_any);   /* _dummy=1 -> overall row      */

/*--- 2) by SOC (distinct participants within SOC) ---------------------------*/
%aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, byvars=%str(AESOC), out=_soc);

/*--- 3) by SOC*PT (distinct participants within SOC and PT) -----------------*/
%aecount(ds=adae, trtvar=&TRTVAR, popden=_bign, byvars=%str(AESOC AEDECOD), out=_socpt);

/*--- ordering: SOC by total-column participant count desc; PT within SOC desc */
proc sql;
  create table _socord as
    select AESOC, sum(nsubj) as socn from _soc group by AESOC;
  create table _ptord as
    select AESOC, AEDECOD, sum(nsubj) as ptn from _socpt
    group by AESOC, AEDECOD;
quit;
/* merge socn/ptn back for sort keys; indent PT under SOC (leading spaces) */

/*--- assemble report shell: Any TEAE -> SOC -> indented PT --------------*/
data _rep;
  set _any(in=a) _soc(in=s) _socpt(in=p);
  length term $200;
  if a then do; term='Participants with any TEAE'; level=0; end;
  else if s then do; term=AESOC;               level=1; end;
  else do; term='   '||AEDECOD;                 level=2; end;
  /* value = catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)')) */
run;
proc transpose data=_rep out=_wide; by socn ptn level term; id &TRTNVAR; var value; run;

%tfltitle(num=14.3.1.1, type=Table,
   text=%str(Treatment-Emergent Adverse Events by System Organ Class and Preferred Term),
   pop=Safety Population,
   foot=%str(A participant is counted once at each level. MedDRA v27.0. % = participants with the event / N in arm.));
proc report data=_wide nowd split='|';
  columns socn ptn level term ("Treatment Arm" /* arm cols + Total */);
  define socn  / order descending noprint;
  define ptn   / order descending noprint;
  define term  / order 'System Organ Class|  Preferred Term' width=40 flow;
run;
