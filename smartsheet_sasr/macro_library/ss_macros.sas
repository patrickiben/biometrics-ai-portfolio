/*====================================================================================
  ss_macros.sas  -  SHEETLINK: a deterministic SAS macro library for driving Smartsheet
                    from scheduled SAS (no AI). PROC HTTP + the JSON LIBNAME engine.
  ------------------------------------------------------------------------------------
  Pattern : scheduled SAS writes ops-only data to Smartsheet by a stable key (idempotent
            upsert); Smartsheet's own configured workflows send the rich notifications.
  Prefix  : every macro is %ss_<name>.  Base SAS 9.4M5+ (PROC HTTP + JSON libname).
  GOVERNANCE (load-bearing): Smartsheet is a CLOUD SaaS -> only NON-SENSITIVE OPERATIONAL
            data may leave the tenant (milestone dates, deliverable/QC status, % complete,
            aggregate enrollment counts, ownership). NEVER PHI, participant-level, unblinded,
            or reported clinical numbers. %ss_guard enforces a column ALLOWLIST in code.
  SECURITY: the Bearer token is read from an env var / permissioned file at runtime, never
            hard-coded, never written to the log (OPTIONS NOSOURCE around the read).
  Idempotency: upsert by a STABLE EXTERNAL KEY (a Deliverable/Milestone code you control),
            never blind-append -> re-runs converge, never duplicate.
  Reliability: 300 req/min/token -> %ss_http retries 429/5xx with backoff and FAILS LOUD.
====================================================================================*/

%global SS_BASE SS_TOKEN SS_RC SS_STATUS SS_BACKUP SS_ALLOW;

/*==== %ss_init : base URL, token (from env/file, never logged), fail-loud target =====*/
%macro ss_init(tokenenv=SMARTSHEET_TOKEN, tokenfile=, backup=, allow=);
  %let SS_BASE = https://api.smartsheet.com/2.0;   /* pin /2.0 explicitly */
  %let SS_RC = 0; %let SS_STATUS = OK; %let SS_BACKUP = &backup;
  %let SS_ALLOW = %upcase(&allow);                 /* the ops-only column allowlist */
  options noquotelenmax;
  %local _had; %let _had = %sysfunc(getoption(source));
  options nosource nonotes;                        /* keep the token out of the log */
  %if %length(&tokenfile) %then %do;
    data _null_; infile "&tokenfile" length=l; input; call symputx('SS_TOKEN', strip(_infile_)); run;
  %end;
  %else %let SS_TOKEN = %sysget(&tokenenv);
  options &_had notes;
  %ss_assert(cond=%length(&SS_TOKEN)>0, msg=Smartsheet token not found (env &tokenenv / file &tokenfile), abort=Y);
  %put NOTE: [SHEETLINK] init - token loaded (length hidden); allowlist=&SS_ALLOW;
%mend ss_init;

/*==== %ss_assert : FAIL LOUD. A scheduled job must never fail silently. ===============*/
%macro ss_assert(cond=, msg=, abort=N);
  %if not (&cond) %then %do;
    %let SS_RC = 1; %let SS_STATUS = FAILED;
    %put ERROR: [SHEETLINK] ASSERT FAILED: &msg;
    %if %length(&SS_BACKUP) %then %do;
      filename _ssm email to=("&SS_BACKUP") subject="SHEETLINK FAILURE - &msg" importance="High";
      data _null_; file _ssm; put "SHEETLINK Smartsheet job FAILED: &msg"; put "The tracker may be stale - do not assume it is current."; run;
      filename _ssm clear;
    %end;
    %if &abort=Y %then %abort cancel;
  %end;
%mend ss_assert;

/*==== %ss_http : the core call. Bearer auth, JSON, 429/5xx retry+backoff, fail-loud.
       method=GET/POST/PUT/DELETE ; path appended to &SS_BASE ; in= request-body fileref ;
       out= response fileref. Returns the HTTP status in &ss_code.                       */
%macro ss_http(method=GET, path=, in=, out=_ssresp, ctype=application/json, retries=4);
  %global ss_code;
  filename &out temp; filename _sshdr temp;
  %local try wait; %let try=0; %let wait=2;
  %do %until(&try > &retries);
    proc http url="&SS_BASE/&path" method="&method"
        %if %length(&in) %then in=&in ct="&ctype"; out=&out headerout=_sshdr;
      headers "Authorization"="Bearer &SS_TOKEN" "Accept"="application/json";
    run;
    %let ss_code = &SYS_PROCHTTP_STATUS_CODE;
    %if &ss_code = 429 or (&ss_code >= 500 and &ss_code <= 599) %then %do;   /* throttled / transient */
      %put WARNING: [SHEETLINK] HTTP &ss_code on &method &path - backoff &wait.s (try &try);
      data _null_; rc=sleep(&wait,1); run;  %let wait=%eval(&wait*2); %let try=%eval(&try+1);
    %end;
    %else %let try=%eval(&retries+1);   /* done: success or a non-retryable error */
  %end;
  %ss_assert(cond=(&ss_code >= 200 and &ss_code < 300), msg=&method &path returned HTTP &ss_code);
  filename _sshdr clear;
%mend ss_http;

/*==== %ss_colmap : GET the sheet, build a fresh column NAME -> columnId map (&out).
       Rebuilt EVERY run - columnIds are the only stable cell address; names/order drift.*/
%macro ss_colmap(sheet=, out=ss_cols);
  %ss_http(method=GET, path=sheets/&sheet, out=_sssheet);
  libname _ssj JSON fileref=_sssheet;
  /* the JSON engine exposes a COLUMNS table with id + title (verify names vs your response) */
  data &out; set _ssj.columns(keep=id title type); name=upcase(title); run;
  libname _ssj clear;
  %put NOTE: [SHEETLINK] column map for sheet &sheet rebuilt (%obs(&out) columns);
%mend ss_colmap;

/*==== %ss_get_rows : GET the sheet rows + cells -> a long dataset (&out) of
       rowId * columnId * value, plus the key->rowId map keyed on &keycol's column.       */
%macro ss_get_rows(sheet=, out=ss_rows);
  %ss_http(method=GET, path=sheets/&sheet?includeAll=true, out=_sssheet);
  libname _ssj JSON fileref=_sssheet;
  /* ROWS has id; the cells live in a child table keyed by an ordinal back to ROWS.
     Join cells->rows to get rowId, and cells->columns(name) via columnId.                */
  proc sql;
    create table &out as
      select r.id as rowId, c.columnId, c.value
      from _ssj.rows r join _ssj.rows_cells c on r.ordinal_rows = c.ordinal_rows;
  quit;
  libname _ssj clear;
%mend ss_get_rows;

/*==== %ss_get : read ONE cell value back by its key (verification / read-after-write).
       Result is returned in the macro var named by mvar (default ss_value).               */
%macro ss_get(sheet=, key=, keycolname=, col=, mvar=ss_value);
  %global &mvar; %let &mvar=;
  %ss_colmap(sheet=&sheet, out=_ssgc); %ss_get_rows(sheet=&sheet, out=_ssgr);
  %local kid cid;
  proc sql noprint;
    select id into :kid trimmed from _ssgc where name=%upcase("&keycolname");
    select id into :cid trimmed from _ssgc where name=%upcase("&col");
    select cats(value) into :&mvar trimmed from _ssgr
      where columnId=&cid and rowId=(select rowId from _ssgr where columnId=&kid and upcase(cats(value))=%qupcase("&key"));
  quit;
  %put NOTE: [SHEETLINK] ss_get &col for &key = %superq(&mvar);
%mend ss_get;

/*==== %ss_guard : enforce the OPS-ONLY column allowlist in code. The column TITLES a job
       is about to write MUST all be in &SS_ALLOW - else FAIL LOUD (no PHI to the cloud).
       cols and SS_ALLOW are PIPE-delimited (Smartsheet titles contain spaces).           */
%macro ss_guard(cols=);
  %local i v bad n; %let bad=; %let n=%sysfunc(countw(%superq(cols),|));
  %do i=1 %to &n; %let v=%qupcase(%qscan(%superq(cols),&i,|));
    %if %length(&v) and not %sysfunc(indexw(%superq(SS_ALLOW),&v,|)) %then %let bad=&bad.[&v];
  %end;
  %ss_assert(cond=(%length(&bad)=0), msg=BLOCKED non-allowlisted column(s) for Smartsheet: &bad - possible PHI/sensitive leak, abort=Y);
%mend ss_guard;

/*==== %ss_emit : write a Smartsheet rows-array JSON body from a long cells dataset
       (keyval rowId columnId valstr isnum), grouped one object per keyval.
       mode=UPDATE -> {"id":rowId,...} ; mode=ADD -> {"toBottom":true,...}.               */
%macro ss_emit(cells=, body=, mode=UPDATE);
  filename &body temp;
  proc sort data=&cells; by keyval; run;
  data _null_; file &body lrecl=20000; set &cells end=last; by keyval;
    retain rowsep cellsep; length line $9000 esc $8600;     /* wide: a quote-heavy value ~doubles when escaped */
    if _n_=1 then put '[';
    if first.keyval then do;
      if rowsep then put ',';
      %if %upcase(&mode)=UPDATE %then %do; line = cats('{"id":', rowId, ',"cells":['); %end;
      %else %do;                          line = '{"toBottom":true,"cells":[';        %end;
      l = length(line); put line $varying9000. l;           /* exact width - no padding  */
      rowsep = 1; cellsep = 0;
    end;
    esc = tranwrd(strip(valstr),'\','\\'); esc = tranwrd(esc,'"','\"');   /* JSON-escape */
    if isnum then line = cats('{"columnId":', columnId, ',"value":',  strip(valstr), '}');
    else          line = cats('{"columnId":', columnId, ',"value":"', strip(esc),    '"}');
    if cellsep then line = cats(',', line);
    l = length(line); put line $varying9000. l;
    cellsep = 1;
    if last.keyval then put ']}';
    if last then put ']';
  run;
%mend ss_emit;

/*==== %ss_upsert : the flagship. Idempotent update-by-key, add-if-new. NEVER duplicates.
       data : one row per record; a key variable (&keycol) plus value variables, each
              value variable LABELED with its exact Smartsheet column TITLE.
              e.g.  label Status="Status" PctDone="% Done" DueDate="Due";
       Existing keys -> PUT (update in place); new keys -> POST (append). Re-runs converge. */
%macro ss_upsert(sheet=, keycol=, keycolname=, data=, dryrun=N);
  %ss_colmap(sheet=&sheet, out=_ssc);                          /* name(upcase title)->id   */
  %ss_get_rows(sheet=&sheet, out=_ssr);

  /* the key column's id + the current key-value -> rowId map */
  %local keyid; proc sql noprint; select id into :keyid trimmed from _ssc where name=%upcase("&keycolname"); quit;
  proc sql; create table _sskey as select rowId, value as keyval from _ssr where columnId=&keyid; quit;

  /* attach the existing rowId (if the key already lives on the sheet).
     The key should be a TEXT column on the sheet; cats() compares text-exactly and converts
     a numeric key without leading blanks (a zero-padded code must be stored as text both sides). */
  proc sql; create table _ssjob as
    select d.*, k.rowId from &data d left join _sskey k on cats(d.&keycol)=cats(k.keyval); quit;

  /* enumerate the value variables by type (exclude the key + the joined rowId) */
  %local cv nv nvv nlbl lbls;
  proc contents data=_ssjob(drop=rowId) out=_ct(keep=name type label) noprint; run;
  proc sql noprint;
    select name into :cv separated by ' ' from _ct where upcase(name) ne %upcase("&keycol") and type=2;
    select name into :nv separated by ' ' from _ct where upcase(name) ne %upcase("&keycol") and type=1;
    select count(*) into :nvv  trimmed from _ct where upcase(name) ne %upcase("&keycol");
    select count(*) into :nlbl trimmed from _ct where upcase(name) ne %upcase("&keycol") and label ne '';
    select distinct upcase(label) into :lbls separated by '|' from _ct
      where label ne '' and upcase(name) ne %upcase("&keycol");
  quit;

  /* every value variable MUST be labeled with its title (else it would be silently dropped) */
  %ss_assert(cond=(&nvv=&nlbl), msg=Every value variable must be LABELED with its Smartsheet column title, abort=Y);
  /* GUARD: every value-variable label (its Smartsheet title) must be on the ops-only allowlist */
  %ss_guard(cols=&lbls|%upcase(&keycolname));

  /* transpose value vars to long; PROC TRANSPOSE writes each var's label into _LABEL_.
     No empty stubs (a stub's short key length would truncate the real key on SET).         */
  %if %length(&cv) %then %do; proc transpose data=_ssjob out=_lc(rename=(col1=_v));  by &keycol rowId notsorted; var &cv; run; %end;
  %if %length(&nv) %then %do; proc transpose data=_ssjob out=_ln(rename=(col1=_nv)); by &keycol rowId notsorted; var &nv; run; %end;

  data _cells;
    set %if %length(&cv) %then _lc(in=inc); %if %length(&nv) %then _ln(in=inn); ;
    length title $200 valstr $4300;
    %if %length(&cv) and %length(&nv) %then %do; isnum=inn; if inc then valstr=strip(_v); else valstr=strip(put(_nv,best32.)); %end;
    %else %if %length(&cv) %then %do; isnum=0; valstr=strip(_v); %end;
    %else %do; isnum=1; valstr=strip(put(_nv,best32.)); %end;
    title = upcase(_label_);
    if missing(valstr) or valstr='.' then delete;   /* don't push empty cells */
  run;
  /* always (re)assert the key cell, and resolve every title -> columnId */
  data _keycell; set _ssjob; length title $200 valstr $4300; title=%upcase("&keycolname");
    valstr=cats(&keycol); isnum=0; keep &keycol rowId title valstr isnum; run;
  data _allcells; set _cells _keycell; run;
  proc sql; create table _cells2 as
    select c.&keycol as keyval length=200, c.rowId, m.id as columnId, c.valstr, c.isnum
    from _allcells c join _ssc m on c.title=m.name; quit;

  /* split existing (PUT) from new (POST) and send each only if non-empty */
  data _cupd _cnew; set _cells2; if rowId>. then output _cupd; else output _cnew; run;
  %if %upcase(&dryrun)=Y %then %do;   /* preview only: validate a job before you schedule it */
    %put NOTE: [SHEETLINK] DRY RUN sheet &sheet - would update=%obs(_cupd) cells / add=%obs(_cnew) cells (idempotent by &keycolname) - nothing sent;
    %return;
  %end;
  %if %obs(_cupd) %then %do; %ss_emit(cells=_cupd, body=_bupd, mode=UPDATE);
    %ss_http(method=PUT,  path=sheets/&sheet/rows, in=_bupd, out=_rupd); filename _bupd clear; %end;
  %if %obs(_cnew) %then %do; %ss_emit(cells=_cnew, body=_bnew, mode=ADD);
    %ss_http(method=POST, path=sheets/&sheet/rows, in=_bnew, out=_rnew); filename _bnew clear; %end;
  %put NOTE: [SHEETLINK] upsert sheet &sheet done - updated=%obs(_cupd) cells / added=%obs(_cnew) cells (idempotent by &keycolname);
%mend ss_upsert;

/*==== %ss_attach : attach an operational artifact (status PDF/QC summary) to a row.
       Rate-intensive (~10x): use sparingly. Ops-only files only.                         */
%macro ss_attach(sheet=, row=, file=, name=);
  %local fn; %let fn=%sysfunc(coalescec(&name,%scan(&file,-1,/)));
  filename _ssf "&file" recfm=n;
  proc http url="&SS_BASE/sheets/&sheet/rows/&row/attachments" method="POST" in=_ssf out=_ssatt headerout=_ssh
       ct="application/pdf";
    headers "Authorization"="Bearer &SS_TOKEN" "Content-Disposition"="attachment; filename=""&fn""";
  run;
  filename _ssf clear;
  %ss_assert(cond=(&SYS_PROCHTTP_STATUS_CODE >= 200 and &SYS_PROCHTTP_STATUS_CODE < 300), msg=attach &fn returned &SYS_PROCHTTP_STATUS_CODE);
  %put NOTE: [SHEETLINK] attached &fn to row &row;
%mend ss_attach;

/*==== %ss_update_request : the supported human-in-the-loop notification. Emails the
       recipients a link to update the given rows/columns. Ops-only message text.
       sendto = SPACE-separated emails ; rowids / colids = COMMA-separated bare ids.        */
%macro ss_update_request(sheet=, rowids=, colids=, sendto=, subject=, message=);
  filename _ssur temp;
  data _null_; file _ssur lrecl=8000;
    length line $4000 tok $200 subj $600 msg $2000; i=1;
    subj = tranwrd(tranwrd("&subject",'\','\\'),'"','\"');   /* JSON-escape the free text */
    msg  = tranwrd(tranwrd("&message",'\','\\'),'"','\"');
    line='{"sendTo":[';
    do while(scan("&sendto",i,' ') ne '');     /* recipients as {"email":"..."} */
      tok=scan("&sendto",i,' ');
      line=cats(line, ifc(i>1,',',''), '{"email":"', strip(tok), '"}'); i+1;
    end;
    line=cats(line, '],"rowIds":[', "&rowids", '],"columnIds":[', "&colids", '],',
              '"subject":"', strip(subj), '","message":"', strip(msg), '","includeAttachments":false}');
    l=length(line); put line $varying4000. l;
  run;
  %ss_http(method=POST, path=sheets/&sheet/updaterequests, in=_ssur, out=_ssurr);
  filename _ssur clear;
  %put NOTE: [SHEETLINK] update request sent to &sendto;
%mend ss_update_request;

%macro obs(ds); %sysfunc(attrn(%sysfunc(open(&ds)),nlobs)) %mend;
/*==== End ss_macros.sas. See ss_config.sas, tracker_update.sas, ss_companion.R, README. */
