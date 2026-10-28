#!/usr/bin/env python3
"""Durable SMTP notifications for Open Study Tracker (Python standard library).

Delivery is at least once: a crash after SMTP acceptance but before the SQLite
receipt can produce a duplicate. Retries retain the same Message-ID. Previews
never contact SMTP and remain eligible for later real delivery.

No recipients means disabled, including no event-cursor changes. On first
enablement, resolved/superseded transitions are skipped. Subsequent recipient
changes apply to future transitions/digests; consumed transitions are not
replayed for a newly added recipient. Each recipient has independent delivery
state. SMTP acceptance means accepted by the server, not inbox delivery.

Digest keys include the UTC date and current overdue/stale content. Unchanged
conditions produce one digest per day; changed exceptions may produce another.
A stale threshold of zero disables that check; empty trackers are not stale.
Each poll processes at most 100 deliveries. Five-minute leases permit recovery
after worker failure, with exponential retry delay capped at one hour. Durable
outbox rows contain addresses and operational identifiers; protect the database.
"""

import argparse
from dataclasses import dataclass, field
from datetime import datetime, timezone, date
from email.message import EmailMessage
from email.policy import SMTP as SMTP_POLICY
from email.utils import format_datetime
import hashlib
import ipaddress
import json
import math
import os
from pathlib import Path
import re
import smtplib
import sqlite3
import ssl
import sys
import tempfile
import time
from urllib.parse import urlsplit
import uuid

try:
    from . import tracker
except ImportError:
    import tracker


class ConfigError(ValueError):
    """An actionable configuration error; never includes secret values."""


def clean(value, label, maximum=2048):
    if len(value) > maximum or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ConfigError(f"{label} contains control characters or exceeds its length limit.")
    return value


def address(value, label):
    value = clean(value, label, 254).strip()
    # Deliberately accept bare ASCII mailboxes only, not display-name syntax.
    if not re.fullmatch(r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]{1,64}@[A-Za-z0-9.-]+", value):
        raise ConfigError(f"{label} must contain bare ASCII email addresses.")
    local, domain = value.rsplit("@", 1)
    if local.startswith(".") or local.endswith(".") or ".." in local or any(
        not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", part)
        for part in domain.split(".")
    ):
        raise ConfigError(f"{label} contains an invalid email address.")
    return local + "@" + domain.lower()


@dataclass(frozen=True)
class Config:
    recipients: tuple = ()
    host: str = ""
    port: int = 587
    security: str = "starttls"
    sender: str = ""
    username: str = field(default="", repr=False)
    password: str = field(default="", repr=False)
    public_url: str = ""

    @property
    def enabled(self):
        return bool(self.recipients)

    @classmethod
    def from_env(cls, env=None, preview=False):
        env = os.environ if env is None else env
        raw = clean(env.get("TRACKER_ALERT_TO", ""), "TRACKER_ALERT_TO", 13000)
        recipients = tuple(dict.fromkeys(address(item, "TRACKER_ALERT_TO") for item in raw.split(","))) if raw.strip() else ()
        if len(recipients) > 50:
            raise ConfigError("TRACKER_ALERT_TO supports at most 50 recipients.")
        security = env.get("TRACKER_SMTP_SECURITY", "starttls").strip().lower()
        if security not in ("starttls", "ssl", "plain"):
            raise ConfigError("TRACKER_SMTP_SECURITY must be starttls, ssl, or plain.")
        host = clean(env.get("TRACKER_SMTP_HOST", ""), "TRACKER_SMTP_HOST", 253).strip()
        if host and (re.search(r"[\s/@?#\\]", host) or not host.isascii()):
            raise ConfigError("TRACKER_SMTP_HOST must be an ASCII hostname or IP address.")
        try:
            port = int(env.get("TRACKER_SMTP_PORT", "465" if security == "ssl" else "587"))
        except ValueError as error:
            raise ConfigError("TRACKER_SMTP_PORT must be an integer from 1 to 65535.") from error
        if not 1 <= port <= 65535:
            raise ConfigError("TRACKER_SMTP_PORT must be an integer from 1 to 65535.")
        username = clean(env.get("TRACKER_SMTP_USERNAME", ""), "TRACKER_SMTP_USERNAME")
        password = env.get("TRACKER_SMTP_PASSWORD", "")
        if bool(username) != bool(password):
            raise ConfigError("Set both TRACKER_SMTP_USERNAME and TRACKER_SMTP_PASSWORD, or neither.")
        if security == "plain":
            try:
                loopback = host.lower() == "localhost" or ipaddress.ip_address(host).is_loopback
            except ValueError:
                loopback = host.lower() == "localhost"
            if not loopback or username:
                raise ConfigError("Plain SMTP is only for an explicitly configured loopback demo without authentication.")
        sender_value = env.get("TRACKER_SMTP_FROM", "")
        sender = address(sender_value, "TRACKER_SMTP_FROM") if sender_value else ("tracker-preview@localhost" if preview else "")
        public_url = clean(env.get("TRACKER_PUBLIC_URL", ""), "TRACKER_PUBLIC_URL").strip()
        if public_url:
            try:
                parsed = urlsplit(public_url)
                if parsed.scheme not in ("https", "http") or not parsed.hostname or re.search(r"\s", public_url) or parsed.username or parsed.password or parsed.fragment or parsed.port == 0:
                    raise ValueError()
            except ValueError as error:
                raise ConfigError("TRACKER_PUBLIC_URL must be an HTTP(S) URL without credentials or fragment.") from error
        if recipients and not preview and (not sender or not host):
            raise ConfigError("Enabled email delivery requires TRACKER_SMTP_HOST and TRACKER_SMTP_FROM.")
        return cls(recipients, host, port, security, sender, username, password, public_url)


def connect(path):
    path = Path(path).resolve()
    if not path.is_file():
        raise tracker.TrackerError("Database does not exist; initialize the tracker first.")
    db = sqlite3.connect(path.as_uri() + "?mode=rw", uri=True, timeout=30, isolation_level=None)
    db.row_factory = sqlite3.Row
    try:
        tracker.check_schema(db)
        db.execute("BEGIN IMMEDIATE")
        db.execute("CREATE TABLE IF NOT EXISTS notification_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        db.execute("CREATE TABLE IF NOT EXISTS notification_outbox (id INTEGER PRIMARY KEY, dedupe_key TEXT NOT NULL, recipient TEXT NOT NULL, kind TEXT NOT NULL, task_id TEXT, expected_status TEXT, subject TEXT NOT NULL, body TEXT NOT NULL, message_id TEXT NOT NULL, created_at REAL NOT NULL, state TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0, next_attempt_at REAL NOT NULL DEFAULT 0, lease_token TEXT, lease_until REAL NOT NULL DEFAULT 0, last_error TEXT, previewed_at REAL, sent_at REAL, UNIQUE(dedupe_key,recipient))")
        db.execute("CREATE INDEX IF NOT EXISTS notification_ready ON notification_outbox(state,next_attempt_at,lease_until)")
        db.execute("INSERT OR IGNORE INTO notification_meta VALUES ('instance_id',?)", (str(uuid.uuid4()),))
        db.execute("INSERT OR IGNORE INTO notification_meta VALUES ('event_cursor','0')")
        db.execute("COMMIT")
        return db
    except Exception:
        if db.in_transaction:
            db.execute("ROLLBACK")
        db.close()
        raise


def queue_notifications(db, config, timestamp, stale_hours=24):
    """Atomically queue current transitions/daily digests and advance the cursor.

    On first enablement, only the latest unconsumed status transition per task
    is considered, and it must still match the current task. Disabled workers
    never call this function. Daily digests contain overdue/stale items only.
    """
    if not math.isfinite(stale_hours) or stale_hours < 0:
        raise ConfigError("stale-hours must be finite and nonnegative; 0 disables stale-import alerts.")
    if not config.enabled:
        return 0
    db.execute("BEGIN IMMEDIATE")
    try:
        instance = db.execute("SELECT value FROM notification_meta WHERE key='instance_id'").fetchone()[0]
        cursor = int(db.execute("SELECT value FROM notification_meta WHERE key='event_cursor'").fetchone()[0])
        events = db.execute("SELECT * FROM events WHERE id>? ORDER BY id", (cursor,)).fetchall()
        rows = {row["task_id"]: dict(row) for row in db.execute("SELECT task_id,status,due FROM tasks")}
        latest = {}
        for event in events:
            change = json.loads(event["changes"]).get("status")
            if change and change["before"] != change["after"]:
                latest[event["task_id"]] = (event, change["after"])
        queued = 0

        def insert(key, kind, body, task_id=None, status=None):
            count = 0
            if config.public_url:
                body += "\nOpen tracker: " + config.public_url + "\n"
            for recipient in config.recipients:
                digest = hashlib.sha256((instance + "\0" + key + "\0" + recipient).encode()).hexdigest()
                result = db.execute("INSERT OR IGNORE INTO notification_outbox (dedupe_key,recipient,kind,task_id,expected_status,subject,body,message_id,created_at) VALUES (?,?,?,?,?,?,?,?,?)",
                    (key, recipient, kind, task_id, status, "Open Study Tracker: " + ("status alert" if kind == "status" else "daily exceptions"), body, f"<{digest}@open-study-tracker.local>", timestamp))
                count += result.rowcount
            return count

        for task_id, (event, status) in latest.items():
            # New transitions supersede unsent status messages, including previews.
            db.execute("UPDATE notification_outbox SET state='cancelled',last_error='Superseded' WHERE task_id=? AND kind='status' AND state IN ('pending','previewed') AND lease_until<=?", (task_id, timestamp))
            if status in ("At risk", "Blocked") and rows.get(task_id, {}).get("status") == status:
                body = f"Task {json.dumps(task_id, ensure_ascii=False)} entered {status}.\nRecorded at {event['changed_at']}.\n\nOperational status only; review the tracker for details.\n"
                queued += insert(f"event:{event['id']}", "status", body, task_id, status)
        if events:
            db.execute("UPDATE notification_meta SET value=? WHERE key='event_cursor'", (str(events[-1]["id"]),))

        today = datetime.fromtimestamp(timestamp, timezone.utc).date()
        lines = []
        for task_id, row in sorted(rows.items()):
            if row["due"] and row["status"] != "Done" and date.fromisoformat(row["due"]) < today:
                lines.append(f"Task {json.dumps(task_id, ensure_ascii=False)}: overdue ({row['due']}); {row['status']}.")
        last = db.execute("SELECT value FROM metadata WHERE key='last_import_at'").fetchone()
        if rows and stale_hours and (not last or timestamp - datetime.fromisoformat(last[0].replace("Z", "+00:00")).timestamp() > stale_hours * 3600):
            lines.append(f"Tracker import is stale (threshold {stale_hours:g} hours).")
        if lines:
            # One content-specific digest per UTC day. Changed exceptions can
            # produce another digest; unchanged runs on that day cannot.
            content = "\n".join(lines)
            content_key = hashlib.sha256(content.encode()).hexdigest()
            digest_key = f"digest:{today}:{content_key}"
            queued += insert(digest_key, "digest", f"Exceptions as of {today} (UTC):\n\n{content}\n")
        else:
            digest_key = ""
        db.execute("UPDATE notification_outbox SET state='cancelled',last_error='Superseded' WHERE kind='digest' AND dedupe_key!=? AND state IN ('pending','previewed') AND lease_until<=?", (digest_key, timestamp))
        placeholders = ",".join("?" for _ in config.recipients)
        db.execute(f"UPDATE notification_outbox SET state='cancelled',last_error='RecipientRemoved' WHERE recipient NOT IN ({placeholders}) AND state IN ('pending','previewed') AND lease_until<=?", (*config.recipients, timestamp))
        db.execute("COMMIT")
        return queued
    except Exception:
        db.execute("ROLLBACK")
        raise


def claim(db, recipients, timestamp, preview=False):
    """Lease one delivery for five minutes; an expired lease can be retried."""
    db.execute("BEGIN IMMEDIATE")
    try:
        states = ("pending",) if preview else ("pending", "previewed")
        sql = "SELECT * FROM notification_outbox WHERE state IN ({}) AND recipient IN ({}) AND next_attempt_at<=? AND lease_until<=? ORDER BY id LIMIT 1".format(",".join("?" for _ in states), ",".join("?" for _ in recipients))
        while True:
            row = db.execute(sql, (*states, *recipients, timestamp, timestamp)).fetchone()
            if not row:
                db.execute("COMMIT")
                return None
            if row["kind"] == "status":
                current = db.execute("SELECT status FROM tasks WHERE task_id=?", (row["task_id"],)).fetchone()
                if not current or current[0] != row["expected_status"]:
                    db.execute("UPDATE notification_outbox SET state='cancelled',last_error='StatusChanged' WHERE id=?", (row["id"],))
                    continue
            token = uuid.uuid4().hex
            db.execute("UPDATE notification_outbox SET lease_token=?,lease_until=?,attempts=attempts+? WHERE id=?", (token, timestamp + 300, 0 if preview else 1, row["id"]))
            db.execute("COMMIT")
            return dict(row, lease_token=token, attempts=row["attempts"] + (0 if preview else 1))
    except Exception:
        if db.in_transaction:
            db.execute("ROLLBACK")
        raise


def message_for(row, config):
    message = EmailMessage(policy=SMTP_POLICY)
    message["From"] = config.sender
    message["To"] = row["recipient"]
    message["Subject"] = row["subject"]
    message["Message-ID"] = row["message_id"]
    message["Date"] = format_datetime(datetime.fromtimestamp(row["created_at"], timezone.utc))
    message.set_content(row["body"])
    return message


def smtp_send(message, config, recipient):
    context = ssl.create_default_context()
    if config.security == "ssl":
        smtp = smtplib.SMTP_SSL(config.host, config.port, timeout=15, context=context)
    else:
        smtp = smtplib.SMTP(config.host, config.port, timeout=15)
    try:
        smtp.ehlo()
        if config.security == "starttls":
            smtp.starttls(context=context)
            smtp.ehlo()
        if config.username:
            smtp.login(config.username, config.password)
        refused = smtp.send_message(message, from_addr=config.sender, to_addrs=[recipient])
        if refused:
            raise smtplib.SMTPRecipientsRefused(refused)
    finally:
        # Do not retry an accepted message solely because the QUIT exchange fails.
        smtp.close()


def write_preview(directory, row, message):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    destination = directory / (hashlib.sha256(row["message_id"].encode()).hexdigest() + ".eml")
    fd, temporary = tempfile.mkstemp(prefix=".preview-", dir=directory)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(message.as_bytes())
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def run_once(db_path, config, preview_dir=None, stale_hours=24, now=None):
    """Queue and process ready rows. Never logs SMTP credentials/server text."""
    if not math.isfinite(stale_hours) or stale_hours < 0:
        raise ConfigError("stale-hours must be finite and nonnegative; 0 disables stale-import alerts.")
    counts = dict(enabled=config.enabled, queued=0, sent=0, previewed=0, failed=0, pending=0)
    if not config.enabled:
        return counts
    timestamp = time.time() if now is None else now
    db = connect(db_path)
    try:
        counts["queued"] = queue_notifications(db, config, timestamp, stale_hours)
        # Bound each poll; subsequent loop iterations continue any backlog.
        for _ in range(100):
            clock = time.time() if now is None else now
            row = claim(db, config.recipients, clock, preview=preview_dir is not None)
            if not row:
                break
            try:
                message = message_for(row, config)
                if preview_dir is not None:
                    write_preview(preview_dir, row, message)
                    state, field_name = "previewed", "previewed_at"
                else:
                    smtp_send(message, config, row["recipient"])
                    state, field_name = "sent", "sent_at"
                db.execute(f"UPDATE notification_outbox SET state=?,{field_name}=?,lease_token=NULL,lease_until=0,last_error=NULL WHERE id=? AND lease_token=?", (state, clock, row["id"], row["lease_token"]))
                counts[state] += 1
            except Exception as error:
                # Class names are safe diagnostics; SMTP replies may contain
                # credentials, addresses, or other server-controlled text.
                delay = min(3600, 30 * 2 ** min(row["attempts"], 7))
                db.execute("UPDATE notification_outbox SET state='pending',next_attempt_at=?,lease_token=NULL,lease_until=0,last_error=? WHERE id=? AND lease_token=?", (clock + delay, type(error).__name__, row["id"], row["lease_token"]))
                counts["failed"] += 1
        counts["pending"] = db.execute("SELECT COUNT(*) FROM notification_outbox WHERE state IN ('pending','previewed')").fetchone()[0]
        return counts
    finally:
        db.close()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", required=True)
    parser.add_argument("--once", action="store_true", help="Process one poll and exit (otherwise poll continuously)")
    parser.add_argument("--interval", type=float, default=60, help="Loop interval in seconds, at least 1")
    parser.add_argument("--stale-hours", type=float, default=24, help="Import staleness threshold; 0 disables stale-import alerts")
    parser.add_argument("--preview-dir", type=Path, help="Write .eml files locally; never contact SMTP")
    args = parser.parse_args(argv)
    try:
        if not math.isfinite(args.interval) or args.interval < 1:
            raise ConfigError("interval must be a finite number of at least 1 second.")
        config = Config.from_env(preview=args.preview_dir is not None)
        while True:
            result = run_once(args.db, config, args.preview_dir, args.stale_hours)
            print(json.dumps(result), flush=True)
            if args.once or not config.enabled:
                return 1 if result["failed"] else 0
            time.sleep(args.interval)
    except KeyboardInterrupt:
        return 0
    except (ConfigError, tracker.TrackerError) as error:
        print(f"Open Study Tracker notifications: {error}", file=sys.stderr)
        return 1
    except (OSError, sqlite3.Error, ValueError) as error:
        print(f"Open Study Tracker notifications: {type(error).__name__}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
