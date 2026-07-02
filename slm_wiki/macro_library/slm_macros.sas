/*====================================================================================
  slm_macros.sas  -  LOCALMIND: a SAS macro library to call a LOCAL, OFFLINE small
                     language model (Ollama / llama.cpp) for the LANGUAGE layer only.
  ------------------------------------------------------------------------------------
  Pattern : SAS/R owns every number and check; the on-device SLM only classifies /
            extracts / routes / drafts, with SCHEMA-CONSTRAINED output, a SAS validator,
            and a human gate. The model never produces a reported number.
  Prefix  : every macro is %slm_<name>.  Base SAS 9.4M5+ (PROC HTTP + JSON libname).
  OFFLINE : the endpoint MUST be loopback (127.0.0.1 / localhost). %slm_init refuses any
            routable host -> "nothing leaves the box" is enforced in code, not by policy.
  REPRO   : temperature 0 + fixed seed + a PINNED model (tag + quantization + sha256
            digest) = a frozen, re-runnable artifact for GAMP-5 / 21 CFR Part 11.
  TRUST   : the model is an UNTRUSTED text source. Output is grammar-constrained at the
            server AND allowlist-validated here (belt + suspenders). Reject, never coerce.
====================================================================================*/

%global SLM_BASE SLM_MODEL SLM_SEED SLM_DIGEST SLM_RC SLM_BACKUP;

/*==== %slm_assert : FAIL LOUD. ========================================================*/
%macro slm_assert(cond=, msg=, abort=N);
  %if not (&cond) %then %do;
    %let SLM_RC=1;
    %put ERROR: [LOCALMIND] ASSERT FAILED: &msg;
    %if %length(&SLM_BACKUP) %then %do;
      filename _slmm email to=("&SLM_BACKUP") subject="LOCALMIND FAILURE - &msg" importance="High";
      data _null_; file _slmm; put "LOCALMIND job FAILED: &msg"; run; filename _slmm clear;
    %end;
    %if &abort=Y %then %abort cancel;
  %end;
%mend slm_assert;

/*==== %slm_init : pin the model, ASSERT loopback + offline, assert the model is pulled,
       capture the model digest for provenance. base defaults to the Ollama loopback.    */
%macro slm_init(model=, base=http://127.0.0.1:11434, seed=42, backup=);
  %let SLM_BASE=&base; %let SLM_MODEL=&model; %let SLM_SEED=&seed; %let SLM_RC=0; %let SLM_BACKUP=&backup;
  /* GUARD: only a loopback host may ever be called (no egress) */
  %slm_assert(cond=%sysfunc(prxmatch(%str(/^http:\/\/(127\.0\.0\.1|localhost|\[::1\])(:\d+)?(\/|$)/i),&SLM_BASE)),
              msg=non-loopback endpoint blocked (&SLM_BASE) - egress not allowed, abort=Y);
  /* liveness probe (local only) */
  filename _slmv temp;
  proc http url="&SLM_BASE/api/version" method="GET" out=_slmv; run;
  %slm_assert(cond=(&SYS_PROCHTTP_STATUS_CODE=200), msg=local model server not reachable at &SLM_BASE - is it running?, abort=Y);
  filename _slmv clear;
  /* assert the exact model tag is already pulled (no silent download) */
  filename _slmt temp;
  proc http url="&SLM_BASE/api/tags" method="GET" out=_slmt; run;
  libname _slmj JSON fileref=_slmt;
  %local _has; %let _has=0;
  proc sql noprint; select count(*) into :_has trimmed from _slmj.models where upcase(name)=upcase("&SLM_MODEL"); quit;
  libname _slmj clear; filename _slmt clear;
  %slm_assert(cond=(&_has>0), msg=model "&SLM_MODEL" is not pulled (run: ollama pull &SLM_MODEL), abort=Y);
  /* capture the model digest (provenance / model-freeze) */
  filename _slms temp; filename _slmsi temp;
  data _null_; file _slmsi; put '{"model":"' "&SLM_MODEL" '"}'; run;
  proc http url="&SLM_BASE/api/show" method="POST" in=_slmsi out=_slms ct="application/json"; run;
  libname _slmj JSON fileref=_slms;
  proc sql noprint; select digest into :SLM_DIGEST trimmed from _slmj.details; quit;   /* may be .model_info; see README */
  libname _slmj clear; filename _slms clear; filename _slmsi clear;
  %put NOTE: [LOCALMIND] init OK - model=&SLM_MODEL seed=&SLM_SEED endpoint=&SLM_BASE (loopback, offline) digest=&SLM_DIGEST;
%mend slm_init;

/*==== %slm_esc : JSON-escape helper text for a request body (call inside a data step).  */
%macro slm_esc(src, dst);
  &dst = tranwrd(strip(&src),'\','\\'); &dst = tranwrd(&dst,'"','\"');
  &dst = tranwrd(&dst,'0A'x,' ');       &dst = tranwrd(&dst,'0D'x,' ');   /* no raw newlines */
%mend slm_esc;

/*==== %slm_chat : the core call. POST /api/chat with stream=false, temp 0 + seed, and a
       caller-supplied JSON-SCHEMA string (&schema) as the grammar constraint. Double-
       parses (envelope -> message.content is itself a JSON string -> parse again) into
       &out. &sys / &usr are escaped. num_predict generous so the JSON object isn't cut.  */
%macro slm_chat(out=slm_out, num_predict=512, num_ctx=8192);   /* reads globals _SLM_SYS _SLM_USR _SLM_SCHEMA */
  filename _req temp; filename _resp temp; filename _hdr temp;
  data _null_; file _req lrecl=60000; length line $58000 s $20000 u $20000;
    %slm_esc(symget('_SLM_SYS'), s); %slm_esc(symget('_SLM_USR'), u);
    line = cats('{"model":"', "&SLM_MODEL", '","stream":false,'
      , '"keep_alive":"-1","options":{"temperature":0,"seed":', "&SLM_SEED"
      , ',"top_k":1,"top_p":1,"repeat_penalty":1,"num_predict":', "&num_predict"
      , ',"num_ctx":', "&num_ctx", '},'
      , '"format":', symget('_SLM_SCHEMA'), ','
      , '"messages":[{"role":"system","content":"', strip(s), '"},'
      , '{"role":"user","content":"', strip(u), '"}]}');
    l=length(line); put line $varying58000. l;
  run;
  proc http url="&SLM_BASE/api/chat" method="POST" in=_req out=_resp headerout=_hdr ct="application/json"; run;
  %slm_assert(cond=(&SYS_PROCHTTP_STATUS_CODE=200), msg=local model HTTP &SYS_PROCHTTP_STATUS_CODE, abort=Y);
  /* envelope: message.content holds the schema JSON as a STRING */
  libname _o JSON fileref=_resp;
  %local _slmcontent _msgtab;
  %if %sysfunc(exist(_o.message)) %then %let _msgtab=_o.message; %else %let _msgtab=_o.root;
  data _null_; set &_msgtab; call symputx('_slmcontent', content, 'L'); run;
  libname _o clear;
  filename _c temp; data _null_; file _c lrecl=60000; length z $58000; z=symget('_slmcontent'); l=length(z); put z $varying58000. l; run;
  libname _p JSON fileref=_c;
  data &out; set _p.root; run;     /* flat object -> ROOT (or ALLDATA; see README) */
  libname _p clear;
  filename _req clear; filename _resp clear; filename _hdr clear; filename _c clear;
%mend slm_chat;

/*==== %slm_validate : the trust boundary. Check a label var against a pipe-delimited
       allowlist (UPCASE) and confidence in [0,1]; reject+fail-loud on any miss.          */
%macro slm_validate(ds=, field=, allow=, conf=confidence);
  %local bad; %let bad=0;
  data &ds; set &ds; length _v $200;
    _v=upcase(&field);
    /* EXACT whole-element compare vs the pipe list (indexw would split a value with a
       space, e.g. "MEDICAL CODING", and false-reject it) */
    _ok=0; do _k=1 to countw("&allow",'|');
      if strip(_v)=strip(upcase(scan("&allow",_k,'|'))) then _ok=1; end;
    if not _ok then do;
      put "ERROR: [LOCALMIND] off-allowlist &field=" _v " (allowed: &allow)"; call symputx('bad','1'); end;
    %if %length(&conf) %then %do;
      if not missing(&conf) and (&conf<0 or &conf>1) then do;
        put "ERROR: [LOCALMIND] &conf out of range=" &conf; call symputx('bad','1'); end;
    %end;
    /* provenance stamp on every row */
    slm_model="&SLM_MODEL"; slm_digest="&SLM_DIGEST"; slm_seed=&SLM_SEED; slm_temp=0; slm_endpoint="&SLM_BASE";
    drop _v _ok _k;
  run;
  %slm_assert(cond=(&bad=0), msg=model output failed validation - NOT writing anything, abort=Y);
%mend slm_validate;

/*==== %slm_classify : convenience = build a one-enum-field schema from &allow, call the
       model, and validate. Returns &out with the label (&field), confidence, rationale,
       and provenance columns. The flagship for triage/routing/labelling tasks.           */
%macro slm_classify(sys=, usr=, field=label, allow=, out=slm_out);
  /* _SLM_SYS / _SLM_USR carry the prompt text (set here if passed, else the caller set
     them via CALL SYMPUTX for per-row free text that may contain commas/quotes).         */
  %global _SLM_SCHEMA _SLM_SYS _SLM_USR;
  %if %length(%superq(sys)) %then %let _SLM_SYS=%superq(sys);
  %if %length(%superq(usr)) %then %let _SLM_USR=%superq(usr);
  /* build the enum-constrained JSON schema from the pipe-delimited allowlist */
  data _null_; length enumj $4000 sch $6000;
    do i=1 to countw("&allow",'|');
      enumj=cats(enumj, ifc(i>1,',',''), '"', strip(scan("&allow",i,'|')), '"'); end;
    sch=cats('{"type":"object","properties":{"', "&field", '":{"type":"string","enum":[', enumj, ']},'
      , '"confidence":{"type":"number"},"rationale":{"type":"string"}},'
      , '"required":["', "&field", '","confidence","rationale"],"additionalProperties":false}');
    call symputx('_SLM_SCHEMA', sch, 'L');
  run;
  %slm_chat(out=&out);
  %slm_validate(ds=&out, field=&field, allow=&allow);
  %put NOTE: [LOCALMIND] classify ok (&field in {&allow});
%mend slm_classify;

/*==== End slm_macros.sas. See slm_config.sas, triage_driver.sas, slm_companion.R, README. */
