/*====================================================================================
  tracker_update.sas  -  the nightly SHEETLINK driver. Schedule this (cron / Task
  Scheduler / SAS batch) AFTER your validated nightly extract refreshes. It pushes the
  ops-only status of the CP-101 program tracker to Smartsheet, idempotently, then lets
  Smartsheet's own configured workflow send the notifications.
  ------------------------------------------------------------------------------------
  Flow : config -> macros -> init -> build ops-only data (LABELED) -> upsert -> (attach
         a status PDF) -> heartbeat.  No PHI. No participant-level data. Fail loud.
====================================================================================*/
%let ROOT = /sasdata/cp101/sheetlink;          /* adjust to your install */
%include "&ROOT/ss_config.sas";
%include "&ROOT/ss_macros.sas";

/* 1) connect: token from env (never hard-coded/logged), fail-loud target, allowlist */
%ss_init(tokenenv=&CFG_TOKEN_ENV, tokenfile=&CFG_TOKEN_FILE, backup=&CFG_BACKUP, allow=&CFG_ALLOW);

/* 2) BUILD THE OPS-ONLY SNAPSHOT from your validated derived data.
      One row per tracked task; the key (&CFG_KEYCOL) is a stable code YOU own.
      Each value variable is LABELED with its exact Smartsheet column title.
      >>> Only operational columns. No PHI, no participant-level, no reported clinical numbers. */
data tracker;
  length TaskID $40 Status $20 Owner $40 Due $10;
  /* example: derive these from your milestone / deliverable / QC-status tables */
  TaskID="CP101-DBL";   Status="At Risk";  PctDone=0.60; Owner="Biostat"; Due="2026-06-20"; output;
  TaskID="CP101-ADaM";  Status="On Track"; PctDone=0.85; Owner="Biostat"; Due="2026-06-28"; output;
  TaskID="CP101-TLF";   Status="Watch";    PctDone=0.40; Owner="Biostat"; Due="2026-07-05"; output;
  label Status="Status" PctDone="% Done" Owner="Owner" Due="Due";   /* labels = Smartsheet TITLES */
run;

/* 3) IDEMPOTENT upsert by TaskID: existing rows update in place, new rows append.
      Re-runnable any number of times a night with no duplicates. */
%ss_upsert(sheet=&CFG_SHEET, keycol=TaskID, keycolname=&CFG_KEYCOLNAME, data=tracker);

/* 4) (optional) attach last night's one-page status PDF to the summary row.
      Rate-intensive - do it once per run, not per row. Ops-only document. */
%if %sysfunc(fileexist(&ROOT/out/cp101_status.pdf)) %then %do;
  %ss_attach(sheet=&CFG_SHEET, row=&CFG_SUMMARYROW, file=&ROOT/out/cp101_status.pdf, name=CP101_status.pdf);
%end;

/* 5) NOTIFICATIONS are NOT sent from code. Configure them ONCE in Smartsheet:
        Automation -> "When Status changes to At Risk -> Alert the PM".
      SAS just writes the truthful cell; Smartsheet decides who to tell. (Pattern A.)
      For a targeted human-in-the-loop ask, you MAY send an update request: */
/* %ss_update_request(sheet=&CFG_SHEET, rowids=&CFG_SUMMARYROW, colids=...,
                      sendto=&CFG_PM, subject=CP101 weekly check,
                      message=Please confirm the DB-lock date.); */

/* 6) heartbeat: prove the job ran (so silence is unambiguously a failure, not a no-op) */
%ss_assert(cond=(&SS_RC=0), msg=SHEETLINK finished with errors - see log);
%put NOTE: [SHEETLINK] tracker_update complete, status=&SS_STATUS;
