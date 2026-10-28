/* Synthetic operational CSV producer. Not executed here (SAS unavailable).
   Set OUTDIR to an existing local folder before running. Your scheduler then runs:
   python3 /path/to/open_tracker/tracker.py --db /path/to/tracker.sqlite
       upsert --csv /path/to/status.csv --actor sas-job
   Check the producer and importer exit codes before exporting a snapshot. */
%let OUTDIR=/path/to/output;

data work.tracker_status;
  length task_id $80 title $160 status $20 owner $120 due $10 notes $1000;
  task_id="DEMO-ADAM"; title="ADaM specification review";
  status="In progress"; owner="Programming"; due="2026-11-06"; progress=70;
  notes="Synthetic example from the SAS CSV producer."; output;
  task_id="007"; title="Transfer readiness check";
  status="At risk"; owner="Data management"; due="2026-11-02"; progress=25;
  notes="Synthetic example: transfer date needs confirmation."; output;
run;

proc export data=work.tracker_status
  outfile="&OUTDIR./status.csv" dbms=csv replace;
  putnames=yes;
run;
