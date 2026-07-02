/******************************************************************************
* TABLE     : t_ae_by_severity  (Single Ascending Dose)
* TITLE     : Treatment-Emergent Adverse Events by System Organ Class,
*             Preferred Term and Maximum Severity by Dose Level
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (TRTEMFL='Y'; AESEVN/ASEV = Mild/Moderate/Severe)
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS with >=1 event (distinct USUBJID),
*             NOT event rows. Each participant contributes at their MAXIMUM
*             severity per SOC/PT (a participant is counted once, at worst grade).
*             n (%) per dose level x severity; % denominator = SAFFL N per dose
*             column. SOC sorted by overall frequency desc; PT within SOC desc.
*             SAD design: parallel ascending-dose cohorts -> column var =
*             TRT01A/TRT01AN (= dose level), ordered ascending; placebo pooled.
*             Watch for dose-related escalation in worst-grade severity.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                      /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/* treatment-emergent records; map severity to ordered rank (worst = highest)  */
data adae; set adam.adae(where=(TRTEMFL='Y' and SAFFL='Y'));
  sevn = AESEVN;                              /* 1=Mild 2=Moderate 3=Severe      */
  if missing(sevn) then sevn = whichc(upcase(ASEV),'MILD','MODERATE','SEVERE');
run;

/*--- maximum severity per participant within SOC*PT (count participant once, at worst) */
proc means data=adae nway noprint;
  class USUBJID &TRTVAR &TRTNVAR AESOC AEDECOD;
  var sevn; output out=_maxsev max=maxsevn;
run;
data _maxsev; set _maxsev;
  length sevcat $10;
  sevcat = scan('Mild Moderate Severe', maxsevn, ' ');   /* worst-grade text     */
run;

/*--- participant counts per SOC*PT x dose level x worst-severity ------------------*/
proc sql;
  create table _socpt as
    select &TRTVAR as trt length=200, &TRTNVAR as trtn, AESOC, AEDECOD, sevcat,
           count(distinct USUBJID) as nsubj
    from _maxsev group by &TRTVAR, &TRTNVAR, AESOC, AEDECOD, sevcat;
quit;

/*--- SOC level: participant counted once per SOC at their worst grand severity ----*/
proc means data=adae nway noprint;
  class USUBJID &TRTVAR &TRTNVAR AESOC;
  var sevn; output out=_maxsoc max=maxsevn;
run;
data _maxsoc; set _maxsoc; length sevcat $10;
  sevcat = scan('Mild Moderate Severe', maxsevn, ' '); run;
proc sql;
  create table _soc as
    select &TRTVAR as trt length=200, &TRTNVAR as trtn, AESOC, sevcat,
           count(distinct USUBJID) as nsubj
    from _maxsoc group by &TRTVAR, &TRTNVAR, AESOC, sevcat;
quit;

/*--- "Any TEAE" overall row: participant once at overall worst severity, per dose -*/
proc means data=adae nway noprint;
  class USUBJID &TRTVAR &TRTNVAR; var sevn; output out=_maxany max=maxsevn;
run;
data _maxany; set _maxany; length sevcat $10;
  sevcat = scan('Mild Moderate Severe', maxsevn, ' '); run;
proc sql;
  create table _any as
    select &TRTVAR as trt length=200, &TRTNVAR as trtn, sevcat,
           count(distinct USUBJID) as nsubj
    from _maxany group by &TRTVAR, &TRTNVAR, sevcat;
quit;

/*--- ordering: SOC by total participant count desc; PT within SOC desc ------------*/
proc sql;
  create table _socord as
    select AESOC, count(distinct USUBJID) as socn
    from _maxsoc group by AESOC;
  create table _ptord as
    select AESOC, AEDECOD, count(distinct USUBJID) as ptn
    from _maxsev group by AESOC, AEDECOD;
quit;

/*--- assemble report shell: Any TEAE -> SOC -> indented PT --------------------*/
data _rep;
  set _any(in=a) _soc(in=s) _socpt(in=p);
  length term $200;
  if a then do; term='Participants with any TEAE'; level=0; end;
  else if s then do; term=AESOC;               level=1; end;
  else do; term='   '||AEDECOD;                 level=2; end;
  /* merge socn/ptn for sort keys; merge _bign by trtn for denominator          */
  /* value = catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)'))       */
run;
/* columns = dose level x severity (Mild/Moderate/Severe + dose Total); unique   */
proc sort data=_rep; by socn ptn level term trtn sevcat; run;
proc transpose data=_rep out=_wide;
  by socn ptn level term;
  id trtn sevcat;                              /* one block per dose x severity  */
  var value;
run;

%tfltitle(num=14.3.1.2, type=Table,
   text=%str(Treatment-Emergent Adverse Events by System Organ Class, Preferred Term and Maximum Severity by Dose Level),
   pop=Safety Population,
   foot=%str(A participant is counted once at each level at their maximum severity. Severity per AESEVN (Mild/Moderate/Severe). Columns = ascending dose levels (placebo pooled). % = participants / N in dose column. MedDRA v27.0.));
proc report data=_wide nowd split='|';
  columns socn ptn level term ("Dose Level by Maximum Severity" /* dose x sev cols */);
  define socn  / order descending noprint;
  define ptn   / order descending noprint;
  define level / noprint;
  define term  / order 'System Organ Class|  Preferred Term' width=40 flow;
run;
