/*====================================================================================
  ss_config.sas  -  per-study/per-sheet constants for SHEETLINK. %include before the
  driver. Keeps sheet ids, the key column, recipients, and the OPS-ONLY ALLOWLIST out of
  the code so a new tracker is one file, not a code edit.
====================================================================================*/
%global CFG_SHEET CFG_SUMMARYROW CFG_KEYCOL CFG_KEYCOLNAME CFG_BACKUP CFG_PM
        CFG_ALLOW CFG_TOKEN_ENV CFG_TOKEN_FILE;

%let CFG_TOKEN_ENV  = SMARTSHEET_TOKEN;          /* env var holding the Bearer token   */
%let CFG_TOKEN_FILE = ;                           /* OR a perms-600 file path; leave 1  */

%let CFG_SHEET      = 1234567890123456;           /* the CP-101 Program Tracker sheetId */
%let CFG_SUMMARYROW = 9876543210;                 /* the summary rowId to attach the PDF*/
%let CFG_KEYCOL     = TaskID;                      /* the SAS variable holding the key   */
%let CFG_KEYCOLNAME = Task ID;                     /* the Smartsheet column TITLE        */

%let CFG_BACKUP     = biostat.backup@example.com;  /* fail-loud target                   */
%let CFG_PM         = pm.cp101@example.com;

/* THE OPS-ONLY ALLOWLIST (column titles, UPCASE-insensitive). %ss_guard FAILS LOUD if a
   job tries to write any column not on this list -> the in-code PHI / sensitive boundary. */
%let CFG_ALLOW = TASK ID|STATUS|% DONE|OWNER|DUE|TASK;
