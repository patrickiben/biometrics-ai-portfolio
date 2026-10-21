#!/usr/bin/env bash
# =====================================================================================
# tm_inventory.sh  -  feed real "last run" status into the Coverage & Continuity Toolkit.
# Reads the heartbeat file each monitor writes (%tm_heartbeat in tm_macros.sas, or
# tm_heartbeat() in tm_companion.R) and prints a status CSV:  id,last_run,last_status
# Import that CSV on the toolkit's Scenario tab. A CSV with no "name" column is treated
# as a status update: it refreshes last_run / last_status on matching job IDs only.
#
#   usage:  tm_inventory.sh jobs.list > heartbeat_status.csv
#   jobs.list, one job per line ("#" comments and blank lines ignored):
#     DEMO101-SAFETY    /opt/trialmon/demo101/out/heartbeat.txt
#     DEMO202-REFRESH   /opt/trialmon/demo202/out/heartbeat.txt
#
# last_run    = the heartbeat file's modification date (YYYY-MM-DD)
# last_status = the status word in the heartbeat (GREEN / AMBER / RED / ERROR), FAILED if
#               the heartbeat says FAILED, MISSING if there is no heartbeat file at all.
# Read-only: it never touches the monitor, the heartbeat, or the scheduler.
# =====================================================================================
set -euo pipefail

[ $# -eq 1 ] && [ -r "$1" ] || { echo "usage: $0 jobs.list" >&2; exit 2; }

echo "id,last_run,last_status"
while read -r id hb _; do
  case "$id" in ''|\#*) continue ;; esac
  if [ ! -f "$hb" ]; then
    echo "$id,,MISSING"
    continue
  fi
  mtime=$(stat -c %Y "$hb" 2>/dev/null || stat -f %m "$hb")
  day=$(date -d "@$mtime" +%F 2>/dev/null || date -r "$mtime" +%F)
  line=$(head -n 1 "$hb")
  case "$line" in
    *FAILED*) status=FAILED ;;
    *)        status=$(printf '%s\n' "$line" | awk '{print $2}')
              case "$status" in GREEN|AMBER|RED|ERROR) ;; *) status= ;; esac ;;
  esac
  echo "$id,$day,$status"
done < "$1"
