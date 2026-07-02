/******************************************************************************
* TABLE     : t_ae_by_severity  (Multiple Ascending Dose)
* TITLE     : Treatment-Emergent Adverse Events by System Organ Class,
*             Preferred Term and Maximum Severity, by Dose Level
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (TRTEMFL='Y'; severity from AESEVN/ASEV)
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS with >=1 event (distinct USUBJID),
*             NOT event rows. A participant is counted at the MAXIMUM severity
*             experienced within each SOC/PT (mild/moderate/severe), so a
*             participant appears once per severity category at each level. n (%) per
*             dose level; % denominator = SAFFL N per dose column.
*             MAD design: column var = TRT01A/TRT01AN (= dose level); placebo
*             pooled in ADaM; severity taken as max over the multiple-dose period.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* TRTVAR=TRT01A             */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/* treatment-emergent records from the Safety population                     */
data adae; set adam.adae(where=(TRTEMFL='Y' and SAFFL='Y'));
  length sevcat $10;
  select(AESEVN);
    when(1) sevcat='Mild';
    when(2) sevcat='Moderate';
    when(3) sevcat='Severe';
    otherwise sevcat=ASEV;     /* fallback to character severity            */
  end;
run;

/*--- maximum severity per participant within SOC*PT (avoid double counting) ----
* For each USUBJID x dose x SOC x PT keep the single max-severity record so a
* participant contributes to exactly one severity category at that term.        */
proc sql;
  create table _maxsev as
    select &TRTVAR as trt length=200, &TRTNVAR as trtn,
           USUBJID, AESOC, AEDECOD, max(AESEVN) as maxsevn
    from adae group by &TRTVAR, &TRTNVAR, USUBJID, AESOC, AEDECOD;
quit;
data _maxsev; set _maxsev; length sevcat $10;
  select(maxsevn);
    when(1) sevcat='Mild'; when(2) sevcat='Moderate'; when(3) sevcat='Severe';
    otherwise sevcat='Unknown';
  end;
run;

/*--- participant counts per SOC*PT*severity, per dose level --------------------*/
proc sql;
  create table _cnt as
    select trt, trtn, AESOC, AEDECOD, sevcat,
           count(distinct USUBJID) as nsubj
    from _maxsev group by trt, trtn, AESOC, AEDECOD, sevcat
  union all  /* Total column */
    select 'Total' as trt, 9999 as trtn, AESOC, AEDECOD, sevcat,
           count(distinct USUBJID) as nsubj
    from _maxsev group by AESOC, AEDECOD, sevcat;
quit;

/*--- ordering keys (SOC then PT by overall freq) + n (%) -------------------*/
proc sql;
  create table _ord as
    select AESOC, AEDECOD, sum(nsubj) as ptn from _cnt where trt='Total'
    group by AESOC, AEDECOD;
  create table _rep as
    select c.AESOC, c.AEDECOD, c.sevcat, c.trtn, o.ptn, b.N,
           catx(' ', put(c.nsubj,4.),
                cats('(', put(100*c.nsubj/b.N,5.1), '%)')) as value length=40
    from _cnt c left join _ord o on c.AESOC=o.AESOC and c.AEDECOD=o.AEDECOD
                left join _bign b on c.trtn=b.trtn
    order by o.ptn desc, c.AESOC, c.AEDECOD,
             case c.sevcat when 'Mild' then 1 when 'Moderate' then 2 else 3 end, c.trtn;
quit;
proc transpose data=_rep out=_wide; by descending ptn AESOC AEDECOD sevcat; id trtn; var value; run;

%tfltitle(num=14.3.1.2, type=Table,
   text=%str(Treatment-Emergent Adverse Events by System Organ Class, Preferred Term and Maximum Severity, by Dose Level),
   pop=Safety Population,
   foot=%str(A participant is counted once per severity category at the maximum severity within each term over the multiple-dose period. Columns = ascending dose levels (placebo pooled). %% = participants / N in dose column. MedDRA v27.0.));
proc report data=_wide nowd split='|';
  columns ptn AESOC AEDECOD sevcat ("Dose Level" /* ascending dose cols + Total */);
  define ptn    / order descending noprint;
  define AESOC  / order 'System Organ Class' width=28 flow;
  define AEDECOD/ order 'Preferred Term'     width=28 flow;
  define sevcat / order 'Severity'           width=10;
  /* define <each TRT01AN col> / display center "&header (N=&n)"; ordered ascending dose */
run;
