/******************************************************************************
* TABLE     : t_ada_summary  (SAD - Single Ascending Dose)
* TITLE     : Summary of Anti-Drug Antibody (ADA) Incidence by Dose Level
* POPULATION: Immunogenicity / ADA Evaluable Population (ADAFL='Y')
* INPUT     : ADIS (immunogenicity analysis: PARAMCD = ADA result flags such
*             as ADA status, treatment-induced/-boosted, NAb; AVALC/AVAL,
*             baseline vs post-baseline ADA)
* NOTE      : PSEUDOCODE. SAD: parallel ascending cohorts, one (single) dose
*             per participant; column variable = TRT01A/TRT01AN (= dose level,
*             placebo typically pooled). Single dose => one dosing event; ADA
*             assessed at baseline and scheduled post-dose samples. Counts =
*             PARTICIPANTS (distinct USUBJID), NOT records; % denominator = ADA-
*             evaluable N per column (from %bign). Categories: baseline-positive,
*             treatment-emergent (induced + boosted), persistent/transient,
*             NAb-positive.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                       /* column = TRT01A (= dose)     */

/*--- header denominators: ADA-evaluable N per dose column ----------------*/
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=ADAFL, out=_bign);

/*--- one ADA status record per participant (participant-level flags from ADIS) ---
* ADIS carries the derived immunogenicity flags; select the participant-level
* analysis records (e.g. PARAMCD for overall ADA status / NAb status).      */
data ada;
  set adam.adis(where=(ADAFL='Y'));
  length cat $40;
  /* derive ADA category from ADaM-provided immunogenicity flags (no
     re-derivation of the assay result; map flags to display categories):
       baseline ADA-positive            <- ADIS baseline-positive flag
       treatment-induced ADA-positive   <- ADIS induced flag
       treatment-boosted  ADA-positive  <- ADIS boosted flag
       treatment-emergent ADA-positive  <- induced OR boosted
       persistent ADA                   <- ADIS persistence flag
       transient  ADA                   <- ADIS transient flag
       NAb-positive (among ADA+)        <- ADIS NAb flag                     */
run;

/*--- participant counts per ADA category x dose level (distinct USUBJID) ------
* Reuse %catfreq pattern: counts are PARTICIPANTS, % over ADA-evaluable N.       */
proc sql;
  create table _ada as
    select &TRTVAR as trt length=200, &TRTNVAR as trtn, cat,
           count(distinct USUBJID) as nsubj
    from ada
    group by &TRTVAR, &TRTNVAR, cat
  union all   /* Total column */
    select 'Total' as trt, 9999 as trtn, cat,
           count(distinct USUBJID) as nsubj
    from ada group by cat;
quit;

/*--- merge denominators -> n (%) of PARTICIPANTS per dose column -------------*/
proc sql;
  create table _disp as
    select a.trt, a.trtn, a.cat, a.nsubj, b.N,
           cats(put(a.nsubj,4.),' (',put(100*a.nsubj/b.N,5.1),'%)') as value length=20
    from _ada a left join _bign b on a.trtn=b.trtn;
quit;

proc sort data=_disp; by cat trtn; run;
proc transpose data=_disp out=_wide(drop=_name_); by cat; id trtn; var value; run;

%tfltitle(num=14.5.1.1, type=Table,
   text=%str(Summary of Anti-Drug Antibody (ADA) Incidence by Dose Level),
   pop=Immunogenicity (ADA Evaluable) Population,
   foot=%str(Counts = participants (distinct USUBJID); % = participants / ADA-evaluable N per dose level. Treatment-emergent = induced or boosted. NAb = neutralizing antibody (among ADA-positive). SAD: single dose, parallel ascending cohorts (placebo pooled).));
proc report data=_wide nowd split='|';
  columns cat ("Dose Level" /* dose cols incl. Total */);
  define cat / order 'ADA Category' width=40 flow;
run;
