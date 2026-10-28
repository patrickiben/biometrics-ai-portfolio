#!/usr/bin/env python3
"""Shared Open Study Tracker: an evaluation prototype with local account access.

This is not a production security certification. The host operator controls the
SQLite file and account CLI; every account can read the complete tracker. No
forwarded headers are trusted. Behind a proxy, login IP limits therefore apply
to the proxy peer, and the proxy must preserve an allowlisted Host header.
"""

import argparse
from datetime import timedelta
import getpass
import hashlib
import hmac
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import sys
import time
from urllib.parse import urlsplit

from flask import Flask, g, jsonify, request, session
from werkzeug.exceptions import HTTPException, BadRequest, Forbidden, Unauthorized, UnsupportedMediaType
from werkzeug.security import check_password_hash, generate_password_hash

try:
    from . import tracker
except ImportError:  # python open_tracker/server.py
    import tracker

ROLES = ("viewer", "editor", "admin")
SESSION_SECONDS = 8 * 60 * 60
RATE_WINDOW = 15 * 60


def connect(path):
    db = sqlite3.connect(path, timeout=30, isolation_level=None)
    db.row_factory = sqlite3.Row
    return db


def initialize(path):
    """Create shared tables beside the existing tracker schema, never in exports."""
    if not Path(path).parent.is_dir():
        raise tracker.TrackerError("Database parent directory must already exist.")
    db = connect(path)
    try:
        db.execute("BEGIN IMMEDIATE")
        tables = db.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
        if not tables and db.execute("PRAGMA user_version").fetchone()[0] == 0:
            tracker.create_schema(db)
        else:
            tracker.check_schema(db)
        db.execute("""CREATE TABLE IF NOT EXISTS users (
            username TEXT PRIMARY KEY, password_hash TEXT NOT NULL,
            role TEXT NOT NULL CHECK(role IN ('viewer','editor','admin')),
            enabled INTEGER NOT NULL DEFAULT 1, auth_version INTEGER NOT NULL DEFAULT 1)""")
        db.execute("""CREATE TABLE IF NOT EXISTS web_sessions (
            token_hash TEXT PRIMARY KEY, username TEXT NOT NULL,
            auth_version INTEGER NOT NULL, expires_at REAL NOT NULL)""")
        db.execute("CREATE INDEX IF NOT EXISTS web_sessions_username ON web_sessions(username)")
        db.execute("""CREATE TABLE IF NOT EXISTS login_limits (
            scope TEXT PRIMARY KEY, failures INTEGER NOT NULL, started_at REAL NOT NULL)""")
        db.execute("COMMIT")
    except Exception:
        if db.in_transaction:
            db.execute("ROLLBACK")
        raise
    finally:
        db.close()


def username_value(value):
    if not isinstance(value, str) or not re.fullmatch(r"[a-z][a-z0-9_.-]{2,63}", value):
        raise tracker.TrackerError("Username must be 3–64 lowercase letters, digits, dots, underscores or hyphens, starting with a letter.")
    return value


def password_value(value):
    if not isinstance(value, str) or not 12 <= len(value) <= 256:
        raise tracker.TrackerError("Password must contain 12–256 characters.")
    try:
        value.encode("utf-8")
    except UnicodeError:
        raise tracker.TrackerError("Password must contain valid Unicode text.") from None
    return value


def manage_user(path, command, username, password=None, role="editor"):
    username_value(username)
    if role not in ROLES:
        raise tracker.TrackerError("Unknown account role.")
    hashed = generate_password_hash(password_value(password), method="scrypt") if command in ("add-user", "set-password") else None
    initialize(path)
    db = connect(path)
    try:
        db.execute("BEGIN IMMEDIATE")
        user = db.execute("SELECT username FROM users WHERE username=?", (username,)).fetchone()
        if command == "add-user":
            if user:
                raise tracker.TrackerError("Account already exists. Use set-password or set-role.")
            db.execute("INSERT INTO users(username,password_hash,role) VALUES (?,?,?)", (username, hashed, role))
        else:
            if not user:
                raise tracker.TrackerError("Account does not exist.")
            if command == "set-password":
                db.execute("UPDATE users SET password_hash=?,auth_version=auth_version+1 WHERE username=?", (hashed, username))
            elif command == "disable-user":
                db.execute("UPDATE users SET enabled=0,auth_version=auth_version+1 WHERE username=?", (username,))
            elif command == "enable-user":
                db.execute("UPDATE users SET enabled=1,auth_version=auth_version+1 WHERE username=?", (username,))
            elif command == "set-role":
                db.execute("UPDATE users SET role=?,auth_version=auth_version+1 WHERE username=?", (role, username))
            else:
                raise tracker.TrackerError("Unknown account command.")
            db.execute("DELETE FROM web_sessions WHERE username=?", (username,))
        db.execute("COMMIT")
    except Exception:
        if db.in_transaction:
            db.execute("ROLLBACK")
        raise
    finally:
        db.close()


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def loopback(value):
    try:
        parsed = ipaddress.ip_address(value)
        return parsed.is_loopback or bool(getattr(parsed, "ipv4_mapped", None) and parsed.ipv4_mapped.is_loopback)
    except ValueError:
        return False


def origin_parts(value):
    """Normalize an Origin without trusting proxy headers or URL credentials."""
    try:
        parsed = urlsplit(value)
        if (parsed.scheme not in ("http", "https") or not parsed.hostname
                or parsed.username or parsed.password or parsed.path or parsed.query or parsed.fragment
                or any(c.isspace() or ord(c) < 32 for c in value)):
            return None
        return parsed.scheme, parsed.hostname.lower(), parsed.port or (443 if parsed.scheme == "https" else 80)
    except ValueError:
        return None


def host_name(value):
    """Extract one exact DNS/IP host, including bracketed IPv6, without a port."""
    try:
        parsed = urlsplit("http://" + value)
        if (not parsed.hostname or parsed.username or parsed.password or parsed.path or parsed.query or parsed.fragment
                or any(c.isspace() or ord(c) < 32 for c in value)
                or parsed.port is not None and not 1 <= parsed.port <= 65535):
            return None
        return parsed.hostname.encode("idna").decode("ascii").lower()
    except (ValueError, UnicodeError):
        return None


def create_app(config=None):
    app = Flask(__name__, static_folder=None)
    app.config.update(
        DATABASE=os.environ.get("TRACKER_DB", "tracker.sqlite"),
        SECRET_KEY=os.environ.get("TRACKER_SECRET_KEY"),
        COOKIE_SECURE=os.environ.get("TRACKER_INSECURE_LOCAL") != "1",
        MAX_CONTENT_LENGTH=64 * 1024,
        SESSION_COOKIE_NAME="open_tracker_session",
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Lax",
        PERMANENT_SESSION_LIFETIME=timedelta(seconds=SESSION_SECONDS),
        SESSION_REFRESH_EACH_REQUEST=False,
        TRUSTED_HOSTS=[value.strip() for value in os.environ.get("TRACKER_ALLOWED_HOSTS", "localhost,127.0.0.1,[::1]").split(",") if value.strip()],
    )
    if config:
        app.config.update(config)
    secret = app.config.get("SECRET_KEY")
    if not isinstance(secret, str) or len(secret) < 32:
        raise tracker.TrackerError("Set TRACKER_SECRET_KEY to a random secret of at least 32 characters.")
    hosts = app.config.get("TRUSTED_HOSTS")
    if not isinstance(hosts, (list, tuple)) or not hosts or any(
        not isinstance(host, str) or not host or re.search(r"[\s/@?#\\]", host) or host.startswith(".")
        for host in hosts
    ):
        raise tracker.TrackerError("TRACKER_ALLOWED_HOSTS must list exact hostnames, without schemes, paths or wildcard suffixes.")
    allowed_hosts = {host_name(host) for host in hosts}
    if None in allowed_hosts:
        raise tracker.TrackerError("TRACKER_ALLOWED_HOSTS contains an invalid hostname.")
    # Werkzeug 3.1's trusted-host comparison splits IPv6 references at the first
    # colon. Apply an exact normalized allowlist below, including IPv6 literals.
    app.config["TRUSTED_HOSTS"] = None
    app.config["SESSION_COOKIE_SECURE"] = bool(app.config["COOKIE_SECURE"])
    initialize(app.config["DATABASE"])
    dummy_hash = generate_password_hash(secrets.token_urlsafe(32), method="scrypt")

    def database():
        if "db" not in g:
            g.db = connect(app.config["DATABASE"])
        return g.db

    @app.teardown_appcontext
    def close_database(_error):
        db = g.pop("db", None)
        if db is not None:
            db.close()

    def csrf():
        if "csrf" not in session:
            session["csrf"] = secrets.token_urlsafe(32)
        return session["csrf"]

    def current_user(db=None):
        token = session.get("token")
        if not isinstance(token, str):
            return None
        row = (db if db is not None else database()).execute("""SELECT u.username,u.role FROM web_sessions s
            JOIN users u ON u.username=s.username
            WHERE s.token_hash=? AND s.expires_at>? AND u.enabled=1
              AND s.auth_version=u.auth_version""", (digest(token), time.time())).fetchone()
        return dict(row) if row else None

    def require_read(db):
        user = current_user(db)
        if user is None:
            raise Unauthorized("Sign in to view this tracker.")
        return user

    def require_write(db):
        user = require_read(db)
        if user["role"] not in ("editor", "admin"):
            raise Forbidden("Your account has read-only access.")
        return user

    def revoke_session():
        token = session.get("token")
        if isinstance(token, str):
            database().execute("DELETE FROM web_sessions WHERE token_hash=?", (digest(token),))

    @app.before_request
    def request_guard():
        if host_name(request.headers.get("Host", "")) not in allowed_hosts:
            raise BadRequest("This Host header is not allowed.")
        # The CLI bind restriction is also enforced at the application boundary
        # for WSGI imports. A proxy's claimed client IP cannot relax local mode.
        if not app.config["COOKIE_SECURE"] and not loopback(request.remote_addr or ""):
            return jsonify(error="Insecure evaluation mode accepts loopback peers only."), 403
        if request.method in ("POST", "PUT", "PATCH", "DELETE"):
            origin = request.headers.get("Origin")
            expected_origin = ("https" if app.config["COOKIE_SECURE"] else request.scheme) + "://" + request.host
            if origin is not None and (origin_parts(origin) is None or origin_parts(origin) != origin_parts(expected_origin)):
                return jsonify(error="Cross-origin requests are not allowed."), 403
            expected, supplied = session.get("csrf"), request.headers.get("X-CSRF-Token", "")
            if not isinstance(expected, str) or not hmac.compare_digest(expected.encode("utf-8"), supplied.encode("utf-8")):
                return jsonify(error="CSRF verification failed. Reload the page and try again."), 403

    @app.after_request
    def security_headers(response):
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
        nonce = getattr(g, "nonce", None)
        scripts = f"'nonce-{nonce}'" if nonce else "'none'"
        response.headers["Content-Security-Policy"] = (
            f"default-src 'none'; script-src {scripts}; style-src 'self' 'unsafe-inline'; "
            "img-src 'self' data:; connect-src 'self'; font-src 'self'; "
            "base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'"
        )
        if app.config["COOKIE_SECURE"]:
            response.headers["Strict-Transport-Security"] = "max-age=31536000"
        return response

    @app.errorhandler(HTTPException)
    def http_error(error):
        return jsonify(error=error.description), error.code

    @app.errorhandler(tracker.TrackerConflict)
    def conflict_error(error):
        return jsonify(error=str(error)), 409

    @app.errorhandler(tracker.TrackerError)
    def input_error(error):
        return jsonify(error=str(error)), 400

    @app.errorhandler(sqlite3.Error)
    def storage_error(_error):
        return jsonify(error="Storage is unavailable. Try again or contact the tracker administrator."), 503

    @app.errorhandler(Exception)
    def unexpected_error(error):
        # Never log request bodies, credentials or exception messages containing row values.
        app.logger.error("Unexpected tracker server error (%s)", type(error).__name__)
        return jsonify(error="The server could not complete this request. Contact the tracker administrator."), 500

    def body(keys):
        if not request.is_json:
            raise UnsupportedMediaType("Use application/json for this request.")
        try:
            # Match file-import semantics: duplicate keys and NaN/Infinity are
            # ambiguous/nonstandard input, including inside a task object.
            def reject_constant(_value):
                raise ValueError("Non-finite JSON constant")
            data = json.loads(request.get_data().decode("utf-8"),
                              object_pairs_hook=tracker.unique_object, parse_constant=reject_constant)
        except (ValueError, UnicodeError, RecursionError):
            raise BadRequest("Send valid UTF-8 JSON with unique properties and finite values.") from None
        if not isinstance(data, dict) or set(data) != set(keys):
            raise tracker.TrackerError("Request contains missing or unknown fields.")
        return data

    @app.get("/")
    def index():
        page = tracker.TEMPLATE.read_text(encoding="utf-8")
        empty = json.dumps(dict(schema_version=1, exported_at=None, last_import_at=None, rows=[], events=[]))
        pattern = r'(<script\b[^>]*\bid=["\x27]tracker-data["\x27][^>]*>).*?(</script\s*>)'
        page, count = re.subn(pattern, lambda m: m[1] + empty + m[2], page, flags=re.S | re.I)
        if count != 1:
            raise tracker.TrackerError("Browser template is missing its data marker.")
        page = re.sub(r"<html\b([^>]*)>", lambda m: '<html data-shared="true"' + m[1] + '>', page, count=1, flags=re.I)
        g.nonce = secrets.token_urlsafe(24)
        page = re.sub(r"<script\b", lambda _: '<script nonce="' + g.nonce + '"', page, flags=re.I)
        page = page.replace('href="README.md"', 'href="https://github.com/patrickiben/biometrics-ai-portfolio/tree/main/open_tracker#readme"')
        page = page.replace('href="SHARED.md"', 'href="https://github.com/patrickiben/biometrics-ai-portfolio/blob/main/open_tracker/SHARED.md"')
        page = page.replace('href="../Operations.html"', 'href="https://patrickiben.github.io/biometrics-ai-portfolio/Operations.html"')
        page = page.replace('href="../LICENSE"', 'href="https://github.com/patrickiben/biometrics-ai-portfolio/blob/main/LICENSE"')
        return app.response_class(page, mimetype="text/html")

    @app.get("/api/session")
    def session_info():
        return jsonify(user=current_user(), csrf_token=csrf())

    @app.post("/api/login")
    def login():
        data = body(("username", "password"))
        username, password = data["username"], data["password"]
        if not isinstance(username, str) or not isinstance(password, str) or len(username) > 64 or len(password) > 256:
            return jsonify(error="Invalid username or password."), 401
        try:
            username.encode("utf-8")
            password.encode("utf-8")
        except UnicodeEncodeError:
            return jsonify(error="Invalid username or password."), 401
        username = username.lower().strip()
        ip = request.remote_addr or "unknown"
        scopes = [("pair:" + digest(username + "\0" + ip), 5), ("ip:" + digest(ip), 20)]
        db = database()
        timestamp = time.time()
        db.execute("BEGIN IMMEDIATE")
        try:
            db.execute("DELETE FROM login_limits WHERE started_at<=?", (timestamp - RATE_WINDOW,))
            for scope, limit in scopes:
                row = db.execute("SELECT failures FROM login_limits WHERE scope=?", (scope,)).fetchone()
                if row and row[0] >= limit:
                    db.execute("COMMIT")
                    response = jsonify(error="Too many login attempts. Try again in 15 minutes.")
                    response.headers["Retry-After"] = str(RATE_WINDOW)
                    return response, 429
            user = db.execute("SELECT * FROM users WHERE username=?", (username,)).fetchone()
            valid_password = check_password_hash(user["password_hash"] if user else dummy_hash, password)
            if not user or not valid_password or not user["enabled"]:
                for scope, _limit in scopes:
                    db.execute("""INSERT INTO login_limits(scope,failures,started_at) VALUES (?,1,?)
                        ON CONFLICT(scope) DO UPDATE SET failures=failures+1""", (scope, timestamp))
                db.execute("COMMIT")
                return jsonify(error="Invalid username or password."), 401
            revoke_session()
            token = secrets.token_urlsafe(48)
            db.execute("DELETE FROM web_sessions WHERE expires_at<=?", (timestamp,))
            db.execute("INSERT INTO web_sessions VALUES (?,?,?,?)", (digest(token), username, user["auth_version"], timestamp + SESSION_SECONDS))
            db.execute("DELETE FROM login_limits WHERE scope=?", (scopes[0][0],))
            db.execute("COMMIT")
        except Exception:
            if db.in_transaction:
                db.execute("ROLLBACK")
            raise
        session.clear()
        session.permanent = True
        session["token"] = token
        return jsonify(user=dict(username=username, role=user["role"]), csrf_token=csrf())

    @app.post("/api/logout")
    def logout():
        body(())
        revoke_session()
        session.clear()
        return jsonify(user=None, csrf_token=csrf())

    @app.get("/api/snapshot")
    def snapshot():
        return jsonify(tracker.snapshot(app.config["DATABASE"], transaction_guard=require_read))

    @app.post("/api/tasks")
    def save_task():
        user = current_user()
        if user is None:
            return jsonify(error="Sign in to edit this tracker."), 401
        if user["role"] not in ("editor", "admin"):
            return jsonify(error="Your account has read-only access."), 403
        data = body(("row", "expected_updated_at"))
        row, expected = data["row"], data["expected_updated_at"]
        if not isinstance(row, dict) or set(row) not in (set(tracker.FIELDS), set(tracker.FIELDS) | {"updated_at"}):
            raise tracker.TrackerError("Send one complete task with only documented fields.")
        if expected is not None and (not isinstance(expected, str) or not expected or len(expected) > 64):
            raise tracker.TrackerError("expected_updated_at must be a saved version timestamp, or null for a new task.")
        patch = {key: row[key] for key in tracker.FIELDS}
        tracker.validate_row(patch)
        tracker.upsert(app.config["DATABASE"], [patch], actor=user["username"],
                       expected_versions={patch["task_id"]: expected}, refresh_heartbeat=False,
                       transaction_guard=require_write)
        return jsonify(snapshot=tracker.snapshot(app.config["DATABASE"], transaction_guard=require_read), user=user)

    return app


def read_password():
    supplied = os.environ.get("TRACKER_USER_PASSWORD")
    if supplied is not None:
        return password_value(supplied)
    first = getpass.getpass("Password: ")
    second = getpass.getpass("Confirm password: ")
    if first != second:
        raise tracker.TrackerError("Passwords do not match.")
    return password_value(first)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", default=os.environ.get("TRACKER_DB", "tracker.sqlite"))
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("add-user", "set-password", "disable-user", "enable-user", "set-role"):
        child = commands.add_parser(command)
        child.add_argument("--username", required=True)
        if command in ("add-user", "set-role"):
            child.add_argument("--role", choices=ROLES, default="editor")
    commands.add_parser("list-users")
    serve = commands.add_parser("serve")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8080)
    args = parser.parse_args(argv)
    try:
        if args.command == "serve":
            if os.environ.get("TRACKER_INSECURE_LOCAL") == "1" and args.host not in ("127.0.0.1", "::1", "localhost"):
                raise tracker.TrackerError("Insecure local mode may bind only to loopback. Use HTTPS with secure cookies for a shared deployment.")
            from waitress import serve as waitress_serve
            app = create_app({"DATABASE": args.db})
            print(f"Open Study Tracker listening on {args.host}:{args.port}", flush=True)
            waitress_serve(app, host=args.host, port=args.port, clear_untrusted_proxy_headers=True)
        elif args.command == "list-users":
            initialize(args.db)
            db = connect(args.db)
            try:
                print(json.dumps([dict(row) for row in db.execute("SELECT username,role,enabled FROM users ORDER BY username")], indent=2))
            finally:
                db.close()
        else:
            password = read_password() if args.command in ("add-user", "set-password") else None
            manage_user(args.db, args.command, args.username, password, getattr(args, "role", "editor"))
            print(f"{args.command}: {args.username}")
        return 0
    except (tracker.TrackerError, sqlite3.Error, OSError) as error:
        print(f"Open Study Tracker: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
