#!/usr/bin/env bash
# =====================================================================================
# tm_watchdog.sh  -  the INDEPENDENT dead-man's switch for the TRIALMON monitor.
# Schedule this on a DIFFERENT host / account than the monitor, AFTER the daily run,
# e.g.  cron:  15 7 * * 1-5  /opt/watch/tm_watchdog.sh   (15 min after the 06:00 job).
# It reads the heartbeat the monitor writes and SCREAMS if the job did not run, ran
# late, or reported a problem. "No news" is never "good news" -- a silent monitor is
# itself an alert condition.
# =====================================================================================
set -euo pipefail

HEARTBEAT="/opt/trialmon/cp101/out/heartbeat.txt"   # the file %tm_heartbeat writes
MAX_AGE_MIN=120                                      # alert if the heartbeat is older than this
ALERT_TO="biostat.backup@example.com"
STUDY="CP101"

fail() {  # email + nonzero exit
  printf 'Subject: [WATCHDOG] %s monitor heartbeat problem\n\n%s\n' "$STUDY" "$1" \
    | /usr/sbin/sendmail "$ALERT_TO" || true
  echo "WATCHDOG ALERT: $1" >&2
  exit 1
}

# 1. the heartbeat file must exist
[ -f "$HEARTBEAT" ] || fail "No heartbeat file at $HEARTBEAT -- the monitor job did NOT run. Treat as RED; do not assume GREEN."

# 2. it must be recent (the job ran today, on time)
age_min=$(( ( $(date +%s) - $(stat -c %Y "$HEARTBEAT" 2>/dev/null || stat -f %m "$HEARTBEAT") ) / 60 ))
[ "$age_min" -le "$MAX_AGE_MIN" ] || fail "Heartbeat is ${age_min} min old (> ${MAX_AGE_MIN}). The monitor did not run on schedule."

# 3. its contents must say the run was clean and on fresh data
line="$(cat "$HEARTBEAT")"
case "$line" in
  *FAILED*)          fail "Monitor reported FAILED: $line" ;;
  *"SYSCC=0"*"FRESH=1"*) echo "OK: $line" ;;            # ran clean on fresh data
  *FRESH=0*)         fail "Monitor ran but data is STALE/MISSING (FRESH=0): $line" ;;
  *)                 fail "Monitor heartbeat indicates a non-zero return code: $line" ;;
esac
# A clean exit (0) means: the monitor is alive, on time, and ran on fresh data.
