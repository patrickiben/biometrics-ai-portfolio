#!/usr/bin/env python3
"""Open Study Tracker: dependency-free, local operational tracking (MIT)."""

import argparse
import csv
import io
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import sys
import tempfile
from datetime import date, datetime, timedelta, timezone

FIELDS = ("task_id", "title", "status", "owner", "due", "progress", "notes")
STATUSES = ("Not started", "In progress", "At risk", "Blocked", "Done")
DEFAULTS = dict(title="", status="Not started", owner="", due="", progress=0, notes="")
MAX_BYTES = 5 * 1024 * 1024
MAX_ROWS = 10000
TEMPLATE = Path(__file__).with_name("index.html")


class TrackerError(ValueError):
    """An actionable input or storage error."""


class TrackerConflict(TrackerError):
    """A shared edit was based on a row version that is no longer current."""


def now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise TrackerError(f"Duplicate JSON property: {key}")
        result[key] = value
    return result


def read_input(path, kind):
    path = Path(path)
    with path.open("rb") as stream:
        raw = stream.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise TrackerError("Input exceeds 5 MiB.")
    text = raw.decode("utf-8-sig")
    if kind == "csv":
        reader = csv.reader(io.StringIO(text, newline=""), strict=True)
        headers = next(reader, [])
        if not headers or len(headers) != len(set(headers)):
            raise TrackerError("CSV requires unique column headers.")
        if "task_id" not in headers or set(headers) - set(FIELDS):
            raise TrackerError("CSV requires task_id and only documented operational columns.")
        rows = []
        for number, values in enumerate(reader, 2):
            if len(values) != len(headers):
                raise TrackerError(f"CSV row {number}: column count does not match headers.")
            # Empty CSV fields mean no change; JSON supports explicit clearing.
            row = {key: value for key, value in zip(headers, values) if value != "" or key == "task_id"}
            if "progress" in row:
                if not re.fullmatch(r"[0-9]{1,3}", row["progress"]):
                    raise TrackerError(f"CSV row {number}: progress must be an integer from 0 to 100.")
                row["progress"] = int(row["progress"])
            rows.append(row)
            if len(rows) > MAX_ROWS:
                raise TrackerError("An import must contain 1 to 10000 rows.")
    else:
        try:
            document = json.loads(text, object_pairs_hook=unique_object)
        except RecursionError as error:
            raise TrackerError("JSON nesting is too deep.") from error
        if not isinstance(document, dict) or type(document.get("schema_version")) is not int or document["schema_version"] != 1:
            raise TrackerError("JSON requires schema_version: 1 and a rows array.")
        if set(document) - {"schema_version", "rows", "exported_at", "last_import_at", "events"}:
            raise TrackerError("Unknown JSON document property.")
        rows = document.get("rows")
    if not isinstance(rows, list) or not 1 <= len(rows) <= MAX_ROWS:
        raise TrackerError("An import must contain 1 to 10000 rows.")
    seen = set()
    validated = []
    for number, row in enumerate(rows, 1):
        if not isinstance(row, dict) or set(row) - set(FIELDS) - ({"updated_at"} if kind == "json" else set()):
            raise TrackerError(f"Row {number}: unknown column or invalid row object.")
        patch = {key: value for key, value in row.items() if key != "updated_at"}
        validate_row(patch, partial=True)
        if patch["task_id"] in seen:
            raise TrackerError(f"Row {number}: duplicate task_id in this batch.")
        seen.add(patch["task_id"])
        validated.append(patch)
    return validated


def validate_row(row, partial=False):
    if "task_id" not in row:
        raise TrackerError("Every row requires task_id.")
    for key, limit in (("task_id", 80), ("title", 160), ("owner", 120), ("notes", 1000)):
        if key not in row and partial:
            continue
        value = row.get(key)
        if not isinstance(value, str) or len(value) > limit or any(ord(c) < 32 and c not in "\n\r\t" for c in value):
            raise TrackerError(f"{key} must be text of at most {limit} characters without control codes.")
        if any(0xD800 <= ord(c) <= 0xDFFF for c in value):
            raise TrackerError(f"{key} must contain valid Unicode text.")
        if key in ("task_id", "title") and not value.strip():
            raise TrackerError(f"{key} must not be blank.")
        if key == "task_id" and (value != value.strip() or any(c in value for c in "\n\r\t")):
            raise TrackerError("task_id must not contain surrounding whitespace or line breaks.")
    if "status" in row and row["status"] not in STATUSES:
        raise TrackerError("status must be one of: " + ", ".join(STATUSES))
    if "progress" in row and (type(row["progress"]) is not int or not 0 <= row["progress"] <= 100):
        raise TrackerError("progress must be an integer from 0 to 100.")
    if "due" in row:
        due = row["due"]
        if not isinstance(due, str):
            raise TrackerError("due must be YYYY-MM-DD or an empty string.")
        if due:
            if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", due):
                raise TrackerError("due must be YYYY-MM-DD or an empty string.")
            try:
                date.fromisoformat(due)
            except ValueError as error:
                raise TrackerError("due must be a real calendar date.") from error


def connect_readonly(path, allow_empty=False):
    path = Path(path).resolve()
    if not path.is_file():
        raise TrackerError("Database does not exist. Run upsert with your first CSV or JSON file.")
    db = sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, isolation_level=None)
    db.row_factory = sqlite3.Row
    try:
        empty = db.execute("PRAGMA user_version").fetchone()[0] == 0 and not db.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchone()
        if not (allow_empty and empty):
            check_schema(db)
    except Exception:
        db.close()
        raise
    return db


def check_schema(db):
    if db.execute("PRAGMA user_version").fetchone()[0] != 1:
        raise TrackerError("Unsupported database schema; expected Open Study Tracker version 1.")
    tables = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    if not {"tasks", "events", "metadata"} <= tables:
        raise TrackerError("Database is not an Open Study Tracker database.")


def create_schema(db):
    db.execute("CREATE TABLE tasks (task_id TEXT PRIMARY KEY, title TEXT NOT NULL, status TEXT NOT NULL, owner TEXT NOT NULL, due TEXT NOT NULL, progress INTEGER NOT NULL, notes TEXT NOT NULL, updated_at TEXT NOT NULL)")
    db.execute("CREATE TABLE events (id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL, changed_at TEXT NOT NULL, actor TEXT NOT NULL, changes TEXT NOT NULL)")
    db.execute("CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    db.execute("PRAGMA user_version=1")


def upsert(path, patches, actor, dry_run=False, expected_versions=None, refresh_heartbeat=True,
           transaction_guard=None):
    if not isinstance(actor, str) or not actor.strip() or len(actor) > 120 or any(ord(c) < 32 or 0xD800 <= ord(c) <= 0xDFFF for c in actor):
        raise TrackerError("actor must be nonblank text of at most 120 characters without control codes.")
    path = Path(path)
    new = not path.exists()
    if dry_run:
        db = sqlite3.connect(":memory:", isolation_level=None)
        if not new:
            source = connect_readonly(path, allow_empty=True)
            try:
                source.backup(db)
            finally:
                source.close()
    else:
        if not path.parent.is_dir():
            raise TrackerError("Database parent directory must already exist.")
        db = sqlite3.connect(path, timeout=30, isolation_level=None)
    db.row_factory = sqlite3.Row
    try:
        db.execute("BEGIN IMMEDIATE")
        # Inspect under the write lock: two first-time importers can start together.
        # An empty database can also remain after an interrupted initial transaction.
        version = db.execute("PRAGMA user_version").fetchone()[0]
        tables = db.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
        if version == 0 and not tables:
            create_schema(db)
        else:
            check_schema(db)
        if transaction_guard is not None:
            transaction_guard(db)
        counts = dict(created=0, updated=0, unchanged=0, dry_run=dry_run)
        timestamp = now()
        for patch in patches:
            if not isinstance(patch, dict) or set(patch) - set(FIELDS):
                raise TrackerError("Unknown column or invalid row object.")
            validate_row(patch, partial=True)
            existing = db.execute("SELECT * FROM tasks WHERE task_id=?", (patch["task_id"],)).fetchone()
            old = dict(existing) if existing else None
            if expected_versions is not None:
                if patch["task_id"] not in expected_versions:
                    raise TrackerError("Every shared edit requires an expected row version.")
                expected = expected_versions[patch["task_id"]]
                actual = old["updated_at"] if old else None
                if expected != actual:
                    raise TrackerConflict("This deliverable changed since you opened it. Refresh and review the newer row before saving.")
            merged = {key: old[key] for key in FIELDS} if old else dict(DEFAULTS, task_id=patch["task_id"])
            merged.update(patch)
            validate_row(merged)
            changes = {key: {"before": old[key] if old else None, "after": merged[key]}
                       for key in FIELDS if not old or old[key] != merged[key]}
            if not changes:
                counts["unchanged"] += 1
                continue
            row_timestamp = timestamp
            if old:
                # Row versions must advance even if the system clock repeats or
                # moves backward. Otherwise a stale browser edit could be accepted.
                previous = datetime.fromisoformat(old["updated_at"].replace("Z", "+00:00"))
                current = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
                if previous.tzinfo is None:
                    raise TrackerError("Stored row version lacks a timezone.")
                if current <= previous:
                    row_timestamp = (previous + timedelta(microseconds=1)).astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
            if old:
                db.execute("UPDATE tasks SET title=?, status=?, owner=?, due=?, progress=?, notes=?, updated_at=? WHERE task_id=?",
                           tuple(merged[key] for key in FIELDS[1:]) + (row_timestamp, merged["task_id"]))
                counts["updated"] += 1
            else:
                db.execute("INSERT INTO tasks VALUES (?, ?, ?, ?, ?, ?, ?, ?)", tuple(merged[key] for key in FIELDS) + (row_timestamp,))
                counts["created"] += 1
            db.execute("INSERT INTO events (task_id,changed_at,actor,changes) VALUES (?,?,?,?)",
                       (merged["task_id"], row_timestamp, actor, json.dumps(changes, ensure_ascii=False)))
        if refresh_heartbeat:
            db.execute("INSERT INTO metadata (key,value) VALUES ('last_import_at',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (timestamp,))
        db.execute("ROLLBACK" if dry_run else "COMMIT")
        return counts
    except Exception:
        if db.in_transaction:
            db.execute("ROLLBACK")
        raise
    finally:
        db.close()
        # Do not unlink an empty initial database here: another writer may already
        # have opened that inode. A later valid import initializes it safely above.


def snapshot(path, transaction_guard=None):
    db = connect_readonly(path)
    try:
        db.execute("BEGIN")
        if transaction_guard is not None:
            transaction_guard(db)
        rows = [dict(row) for row in db.execute("SELECT * FROM tasks ORDER BY task_id")]
        events = []
        for event in db.execute("SELECT * FROM events ORDER BY id"):
            event = dict(event)
            event["changes"] = json.loads(event["changes"])
            events.append(event)
        last = db.execute("SELECT value FROM metadata WHERE key='last_import_at'").fetchone()
        return dict(schema_version=1, exported_at=now(), last_import_at=last[0] if last else None, rows=rows, events=events)
    finally:
        db.close()


def atomic_write(path, content, database):
    path = Path(path).resolve()
    database_path = Path(database).resolve()
    protected = {database_path, *(Path(str(database_path) + suffix) for suffix in ("-wal", "-shm", "-journal")),
                 TEMPLATE.resolve(), Path(__file__).resolve(),
                 Path(__file__).with_name("server.py").resolve(), Path(__file__).with_name("notifications.py").resolve()}
    if path in protected:
        raise TrackerError("Export destination must not overwrite the database or program files.")
    fd, temporary = tempfile.mkstemp(prefix=".tracker-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def export(path, destination, kind):
    data = snapshot(path)
    payload = json.dumps(data, ensure_ascii=False, indent=2)
    if kind == "html":
        template = TEMPLATE.read_text(encoding="utf-8")
        # Script contents are raw text in HTML even when type is application/json.
        safe = payload.replace("&", "\\u0026").replace("<", "\\u003c").replace(">", "\\u003e").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
        pattern = r'(<script\b[^>]*\bid=[\"\x27]tracker-data[\"\x27][^>]*>).*?(</script\s*>)'
        payload, count = re.subn(pattern, lambda match: match[1] + safe + match[2], template, flags=re.S | re.I)
        if count != 1:
            raise TrackerError("HTML template must contain exactly one tracker-data script.")
        # Exports may be moved anywhere: link documentation to the source repository.
        payload = payload.replace('href="README.md"', 'href="https://github.com/patrickiben/biometrics-ai-portfolio/tree/main/open_tracker#readme"')
        payload = payload.replace('href="../Operations.html"', 'href="https://patrickiben.github.io/biometrics-ai-portfolio/Operations.html"')
        payload = payload.replace('href="../LICENSE"', 'href="https://github.com/patrickiben/biometrics-ai-portfolio/blob/main/LICENSE"')
        payload = payload.replace('href="SHARED.md"', 'href="https://github.com/patrickiben/biometrics-ai-portfolio/blob/main/open_tracker/SHARED.md"')
    atomic_write(destination, payload + "\n", path)
    return dict(rows=len(data["rows"]), destination=str(destination), format=kind)


def check(path, stale_hours):
    if not math.isfinite(stale_hours) or stale_hours < 0:
        raise TrackerError("stale-hours must be a finite nonnegative number.")
    data = snapshot(path)
    current = datetime.now(timezone.utc)
    issues = []
    last = data["last_import_at"]
    if not last or (current - datetime.fromisoformat(last.replace("Z", "+00:00"))).total_seconds() > stale_hours * 3600:
        issues.append(dict(task_id=None, reason="stale", message="No recent successful import."))
    for row in data["rows"]:
        if row["status"] in ("At risk", "Blocked"):
            issues.append(dict(task_id=row["task_id"], reason="status", message=row["status"]))
        if row["due"] and row["status"] != "Done" and date.fromisoformat(row["due"]) < current.date():
            issues.append(dict(task_id=row["task_id"], reason="overdue", message="Due date has passed (UTC)."))
    return dict(last_import_at=last, checked_at=now(), issues=issues)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", required=True, help="Path to a local SQLite database")
    commands = parser.add_subparsers(dest="command", required=True)
    write = commands.add_parser("upsert", help="Validate and atomically update rows by task_id")
    source = write.add_mutually_exclusive_group(required=True)
    source.add_argument("--csv", type=Path)
    source.add_argument("--json", type=Path)
    write.add_argument("--actor", default="local")
    write.add_argument("--dry-run", action="store_true")
    out = commands.add_parser("export", help="Export an offline JSON or HTML snapshot")
    destination = out.add_mutually_exclusive_group(required=True)
    destination.add_argument("--json", type=Path)
    destination.add_argument("--html", type=Path)
    monitor = commands.add_parser("check", help="Exit 2 if stale, overdue, at risk or blocked; 0 if clear")
    monitor.add_argument("--stale-hours", type=float, default=24)
    args = parser.parse_args(argv)
    try:
        if args.command == "upsert":
            kind = "csv" if args.csv else "json"
            result = upsert(args.db, read_input(getattr(args, kind), kind), args.actor, args.dry_run)
        elif args.command == "export":
            kind = "json" if args.json else "html"
            result = export(args.db, getattr(args, kind), kind)
        else:
            result = check(args.db, args.stale_hours)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 2 if args.command == "check" and result["issues"] else 0
    except (TrackerError, OSError, sqlite3.Error, ValueError, csv.Error) as error:
        print(f"Open Study Tracker: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
