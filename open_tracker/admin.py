"""Authenticated setup and administration routes for managed tracker instances."""
from contextlib import closing, contextmanager
from datetime import datetime, timezone
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import tempfile
import threading

from flask import g, jsonify, send_file
from werkzeug.exceptions import Conflict, Forbidden, Unauthorized
from werkzeug.security import generate_password_hash

try:
    from . import manage, server, tracker
except ImportError:
    import manage, server, tracker


def register(app, database, current_user, body):
    workspace = Path(app.config["WORKSPACE"])
    configuration_lock = threading.RLock()

    def configured():
        return (workspace / "config.json").is_file()

    def require_admin(db):
        user = current_user(db)
        if user is None:
            raise Unauthorized("Sign in as an administrator to change setup.")
        if user["role"] != "admin":
            raise Forbidden("Only administrators can change setup and accounts.")
        return user

    @contextmanager
    def administrator_transaction():
        # Re-check the session and role after acquiring the writer lock, so a
        # concurrent revocation cannot authorize a later settings/account write.
        with configuration_lock:
            db = database()
            db.execute("BEGIN IMMEDIATE")
            try:
                user = require_admin(db)
                yield db, user
                db.execute("COMMIT")
            except Exception:
                if db.in_transaction:
                    db.execute("ROLLBACK")
                raise

    def users(db):
        return [dict(row) for row in db.execute("SELECT username,role,enabled FROM users ORDER BY username")]

    def page():
        content = (Path(__file__).parent / "admin.html").read_text(encoding="utf-8")
        content = re.sub(r"<html\b", '<html data-managed="true"', content, count=1, flags=re.I)
        g.nonce = secrets.token_urlsafe(24)
        content = re.sub(r"<script\b", lambda _: '<script nonce="' + g.nonce + '"', content, flags=re.I)
        return app.response_class(content, mimetype="text/html")

    app.add_url_rule("/setup", "setup_page", page, methods=["GET"])
    app.add_url_rule("/admin", "admin_page", page, methods=["GET"])

    @app.errorhandler(manage.SetupError)
    def setup_error(error):
        return jsonify(error=str(error)), 400

    @app.get("/healthz")
    def healthz():
        info = {"status": "ok"}
        if not app.config["COOKIE_SECURE"] and app.config.get("DESKTOP_INSTANCE"):
            info["desktop_instance"] = app.config["DESKTOP_INSTANCE"]
        return jsonify(info)

    @app.get("/api/setup/state")
    def setup_state():
        return jsonify(configured=configured(), token_required=True,
                       public_url=app.config.get("PUBLIC_URL", ""), local=not app.config["COOKIE_SECURE"])

    @app.post("/api/setup")
    def first_setup():
        data = body(("setup_token", "username", "password", "password_confirm", "demo"))
        supplied = data["setup_token"]
        expected = app.config.get("SETUP_TOKEN")
        if (not isinstance(supplied, str) or len(supplied) > 512 or not supplied.isascii() or not isinstance(expected, str)
                or not hmac.compare_digest(supplied.encode("utf-8"), expected.encode("utf-8"))):
            raise Forbidden("The setup key is missing or incorrect. Use the key from your launcher or hosting dashboard.")
        if type(data["demo"]) is not bool:
            raise tracker.TrackerError("Choose whether to load fictional example tasks.")
        username = server.username_value(data["username"])
        password = server.password_value(data["password"])
        if password != data["password_confirm"]:
            raise tracker.TrackerError("Passwords do not match.")
        hashed = generate_password_hash(password, method="scrypt")
        with configuration_lock:
            db = database()
            db.execute("BEGIN IMMEDIATE")
            created_config = False
            try:
                # The database check prevents reclaiming an existing workspace
                # if someone removed its configuration file.
                if configured() or db.execute("SELECT 1 FROM users LIMIT 1").fetchone():
                    raise Conflict("This workspace is already configured. Sign in with an existing account.")
                config = manage.new_config(app.config.get("PUBLIC_URL", ""))
                config["secret_key"] = app.config["SECRET_KEY"]
                manage.check_expected_url(config)
                db.execute("INSERT INTO users(username,password_hash,role) VALUES (?,?,?)", (username, hashed, "admin"))
                if data["demo"]:
                    # Apply the already validated fixture in this same first-claim
                    # transaction; no half-created admin/demo state is committed.
                    rows = tracker.read_input(Path(__file__).parent / "examples/status.csv", "csv")
                    now = tracker.now()
                    for row in rows:
                        complete = dict(task_id=row["task_id"], title=row["title"], status="Not started", owner="", due="", progress=0, notes="")
                        complete.update(row)
                        db.execute("INSERT INTO tasks(task_id,title,status,owner,due,progress,notes,updated_at) VALUES (?,?,?,?,?,?,?,?)",
                                   tuple(complete[key] for key in tracker.FIELDS) + (now,))
                        changes = {key: {"before": None, "after": complete[key]} for key in tracker.FIELDS}
                        db.execute("INSERT INTO events(task_id,changed_at,actor,changes) VALUES (?,?,?,?)",
                                   (complete["task_id"], now, "synthetic-demo", json.dumps(changes)))
                    db.execute("INSERT OR REPLACE INTO metadata(key,value) VALUES ('last_import_at',?)", (now,))
                manage.save_config(workspace, config)
                created_config = True
                db.execute("COMMIT")
            except Exception:
                if db.in_transaction:
                    db.execute("ROLLBACK")
                if created_config:
                    (workspace / "config.json").unlink(missing_ok=True)
                raise
            if os.name != "nt":
                (workspace / "tracker.sqlite").chmod(0o600)
            app.config["SETUP_TOKEN"] = None
        return jsonify(configured=True)

    @app.get("/api/admin/state")
    def state():
        with administrator_transaction() as (db, user):
            config = manage.load_config(workspace)
            mail = dict(config["email"])
            mail["password_configured"] = bool(mail.pop("password"))
            health = {"database": "ok" if db.execute("PRAGMA quick_check").fetchone()[0] == "ok" else "error",
                      "dependencies": "ok" if manage.requirements_ready() else "error"}
            return jsonify(user=dict(user, admin_ui=True), public_url=config["public_url"], local=not bool(config["public_url"]),
                           email=mail, stale_hours=config["stale_hours"], interval=config["interval"],
                           worker=dict(app.extensions.get("tracker_worker", {"status": "starting", "last_poll": None, "error": None})),
                           users=users(db), health=health, can_stop=bool(app.config.get("DESKTOP_INSTANCE")) and not app.config["COOKIE_SECURE"])

    @app.post("/api/admin/users")
    def change_user():
        require_admin(database())
        data = body(("command", "username", "role", "password"))
        command = data["command"]
        if command not in ("add-user", "set-password", "set-role", "disable-user", "enable-user"):
            raise tracker.TrackerError("Unknown account action.")
        username = server.username_value(data["username"])
        role = data["role"]
        if command in ("add-user", "set-role"):
            if role not in server.ROLES:
                raise tracker.TrackerError("Choose viewer, editor or admin.")
        elif role is not None:
            raise tracker.TrackerError("This account action does not accept a role.")
        if command in ("add-user", "set-password"):
            hashed = generate_password_hash(server.password_value(data["password"]), method="scrypt")
        elif data["password"] is not None:
            raise tracker.TrackerError("This account action does not accept a password.")
        with administrator_transaction() as (db, actor):
            current = db.execute("SELECT username,role,enabled FROM users WHERE username=?", (username,)).fetchone()
            if command == "add-user":
                if current:
                    raise Conflict("That account already exists.")
                db.execute("INSERT INTO users(username,password_hash,role) VALUES (?,?,?)", (username, hashed, role))
            else:
                if current is None:
                    raise tracker.TrackerError("That account does not exist.")
                removing_admin = command == "disable-user" or command == "set-role" and role != "admin"
                if removing_admin and username == actor["username"]:
                    raise Conflict("Keep your own administrator access. Ask another administrator to make this change.")
                if removing_admin and current["role"] == "admin" and current["enabled"] and db.execute("SELECT COUNT(*) FROM users WHERE enabled=1 AND role='admin'").fetchone()[0] <= 1:
                    raise Conflict("At least one enabled administrator is required.")
                if command == "set-password":
                    db.execute("UPDATE users SET password_hash=?,auth_version=auth_version+1 WHERE username=?", (hashed, username))
                elif command == "set-role":
                    db.execute("UPDATE users SET role=?,auth_version=auth_version+1 WHERE username=?", (role, username))
                else:
                    db.execute("UPDATE users SET enabled=?,auth_version=auth_version+1 WHERE username=?", (int(command == "enable-user"), username))
                db.execute("DELETE FROM web_sessions WHERE username=?", (username,))
            return jsonify(users=users(db), signed_out=command == "set-password" and username == actor["username"])

    @app.post("/api/admin/email")
    def save_email():
        data = body(("email", "stale_hours", "confirm_live"))
        incoming = data["email"]
        fields = {"mode", "recipients", "host", "port", "security", "sender", "username", "password"}
        if not isinstance(incoming, dict) or set(incoming) != fields or type(data["confirm_live"]) is not bool:
            raise tracker.TrackerError("Email settings contain missing or unknown fields.")
        if (any(not isinstance(incoming[key], str) for key in fields - {"port", "password"})
                or type(incoming["port"]) is not int
                or incoming["password"] is not None and not isinstance(incoming["password"], str)):
            raise tracker.TrackerError("Email settings require text fields, an integer port and a text or unchanged password.")
        if incoming["mode"] == "smtp" and not data["confirm_live"]:
            raise tracker.TrackerError("Confirm live delivery before enabling SMTP.")
        if incoming["mode"] == "smtp" and incoming["security"] not in ("starttls", "ssl"):
            raise tracker.TrackerError("Live email requires STARTTLS or implicit TLS.")
        with administrator_transaction():
            config = manage.load_config(workspace)
            candidate = json.loads(json.dumps(config))
            mail = dict(incoming)
            if mail["password"] is None:
                mail["password"] = config["email"]["password"]
            # Pausing or previewing keeps the saved transport settings. Neither
            # mode connects to SMTP, and resuming still requires live consent.
            if mail["mode"] == "preview" and isinstance(mail["recipients"], str) and not mail["recipients"].strip():
                mail["recipients"] = "reviewer@example.test"
            candidate["email"] = mail
            candidate["stale_hours"] = data["stale_hours"]
            manage.save_config(workspace, candidate)
        return jsonify(saved=True, mode=mail["mode"], applies_automatically=True)

    @app.post("/api/admin/email-test")
    def email_test():
        data = body(("send", "to", "confirm_send"))
        if type(data["send"]) is not bool or type(data["confirm_send"]) is not bool:
            raise tracker.TrackerError("Choose preview or explicitly confirmed test delivery.")
        # Hold the authorization transaction through dispatch: concurrent account
        # revocation cannot race a newly-authorized test email.
        with administrator_transaction():
            config = manage.load_config(workspace)
            if data["send"]:
                if not data["confirm_send"]:
                    raise tracker.TrackerError("Confirm this single-recipient test send.")
                if not isinstance(data["to"], str) or not data["to"] or len(data["to"]) > 254:
                    raise tracker.TrackerError("Enter one email address for the test message.")
                manage.email_test(workspace, config, send=True, recipient=data["to"])
                return jsonify(sent=True, message="SMTP accepted the test. Check the recipient inbox.")
            if data["to"] not in (None, ""):
                raise tracker.TrackerError("Preview does not accept a live recipient.")
            return jsonify(preview="From: tracker-preview@localhost\nTo: reviewer@example.test\nSubject: Open Study Tracker: email setup test\n\nThis is a local preview. No email was sent.\nConfigured notification mode: " + config["email"]["mode"] + "\nReal alerts contain operational task IDs and status, without task notes.\n")

    @app.get("/api/admin/backup")
    def backup():
        # Authorize in the same read transaction used as the backup's source.
        # A write transaction would block sqlite3.backup on this connection.
        db = database()
        db.execute("BEGIN")
        descriptor = None
        filename = None
        streaming = False
        try:
            require_admin(db)
            descriptor, filename = tempfile.mkstemp(prefix="tracker-backup-", suffix=".sqlite", dir=workspace)
            os.close(descriptor)
            descriptor = None
            with closing(sqlite3.connect(filename)) as destination:
                db.backup(destination)
            response = send_file(filename, mimetype="application/vnd.sqlite3", as_attachment=True, conditional=False, etag=False,
                                 download_name="tracker-backup-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + ".sqlite")
            # Keep the response streamed instead of loading an entire database
            # into RAM. ClosingIterator runs cleanup on completion/disconnect.
            response.direct_passthrough = False
            response.call_on_close(lambda: Path(filename).unlink(missing_ok=True))
            streaming = True
            return response
        finally:
            if db.in_transaction:
                db.execute("ROLLBACK")
            if descriptor is not None:
                os.close(descriptor)
            if filename and not streaming:
                Path(filename).unlink(missing_ok=True)

    @app.post("/api/admin/stop")
    def stop_desktop():
        data = body(("confirm",))
        with administrator_transaction():
            if app.config["COOKIE_SECURE"] or not app.config.get("DESKTOP_INSTANCE"):
                raise Forbidden("Stopping is available only for a local desktop workspace.")
            if data["confirm"] is not True:
                raise tracker.TrackerError("Confirm that you want to stop this local workspace.")
            callback = app.extensions.get("tracker_stop")
            if callback is None:
                raise Conflict("The local launcher cannot stop this instance.")
            threading.Timer(0.5, callback).start()
        return jsonify(stopping=True)
