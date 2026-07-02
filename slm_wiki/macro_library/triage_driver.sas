/*====================================================================================
  triage_driver.sas  -  the worked example as runnable SAS: a scheduled QC-finding triage
  where SAS owns every number/check and a LOCAL small model only labels, routes, and drafts.
  ------------------------------------------------------------------------------------
  Flow : config -> macros -> init (loopback+pinned model) -> SAS owns the findings
         (deterministic) -> per finding, the SLM returns NEW/KNOWN + owner + draft (JSON,
         validated) -> assemble ranked worklist -> HUMAN approves -> write + Part 11 audit.
  Nothing the model emits is written until a human approves it. The model emits no number.
====================================================================================*/
%let ROOT = /sasdata/cp101/localmind;
%include "&ROOT/slm_config.sas";
%include "&ROOT/slm_macros.sas";

/* 1) PIN + go offline-safe: loopback guard, liveness, model-pulled, capture digest */
%slm_init(model=&CFG_MODEL, base=&CFG_BASE, seed=&CFG_SEED, backup=&CFG_BACKUP);

/* 2) SAS owns the findings. These come from validated work (Pinnacle 21 + the study's
      own edit-checks / reconciliation). The MODEL NEVER PRODUCES A COUNT. Here: a stub. */
data findings;
  length finding_id $12 rule $20 findtext $600;
  finding_id="SD0064"; rule="AE date order"; findtext="AESTDTC is after AEENDTC for 3 records in domain AE."; output;
  finding_id="SD0011"; rule="Required var";  findtext="LBSTRESN missing for 12 records where LBSTRESC is numeric."; output;
  finding_id="PK0003"; rule="Timing dev";    findtext="ADPC actual sampling time deviates >10% from nominal at the 4h timepoint for 2 participants."; output;
run;

/* 3) Per finding, ask the local model THREE narrow things as schema-constrained JSON,
      each validated against a controlled vocabulary. Set the per-row text via SYMPUTX so
      free text (commas/quotes) is safe. */
%macro triage(ds=findings, out=worklist);
  %local n i; proc sql noprint; select count(*) into :n trimmed from &ds; quit;
  proc datasets nolist lib=work; delete &out; quit;
  %do i=1 %to &n;
    data _null_; set &ds(firstobs=&i obs=&i);
      call symputx('fid', finding_id); call symputx('_SLM_USR', findtext, 'G');  /* global so %slm_chat reads it */
    run;
    /* (a) new-vs-known, (b) owner routing - two constrained classifications */
    %slm_classify(sys=%nrstr(You triage ONE clinical-data QC finding for routing. Use only the schema. Never invent or change any number.),
                  field=owner, allow=&CFG_OWNERS, out=_own);
    %slm_classify(field=novelty, allow=&CFG_NOVELTY, out=_nov);   /* reuses the same _SLM_USR/_SLM_SYS */
    data _row; merge _own(keep=owner confidence rationale slm_model slm_digest slm_seed)
                     _nov(keep=novelty); length finding_id $12; finding_id="&fid"; run;
    data &out; set %if &i>1 %then &out; _row; run;
  %end;
%mend triage;
%triage(ds=findings, out=worklist);

/* 4) SAS assembles + ranks the worklist deterministically (severity/aging - SAS's math,
      not the model's). Join back the SAS-owned facts; the model's label rides ALONGSIDE. */
proc sql; create table worklist2 as
  select f.finding_id, f.rule, f.findtext, w.novelty, w.owner, w.confidence, w.rationale,
         w.slm_model, w.slm_digest
  from findings f left join worklist w on f.finding_id=w.finding_id
  order by w.owner, f.finding_id; quit;

/* 5) HUMAN GATE: the biostatistician reviews worklist2 (SAS facts beside the model label
      + draft) and sets approved=1 on the rows to action. (Here: assume reviewed.)        */
data approved; set worklist2; approved=1; /* <- set by the reviewer, not the model */ run;

/* 6) Only approved rows are written, each with a Part 11 audit line incl. the model digest.
      The query text of record is issued by SAS to the EDC; the model's draft was advisory. */
data _null_; set approved; where approved=1;
  file "&ROOT/audit/triage_audit.txt" mod;
  put finding_id +1 owner +1 novelty +1 "model=" slm_model +1 "digest=" slm_digest +1
      "seed=&CFG_SEED temp=0 reviewer=&SYSUSERID datetime=" "%sysfunc(datetime(),e8601dt.)";
run;
%slm_assert(cond=(&SLM_RC=0), msg=LOCALMIND triage finished with errors - see log);
%put NOTE: [LOCALMIND] triage complete - SAS owned the numbers, the model only labelled/drafted, a human approved.;
