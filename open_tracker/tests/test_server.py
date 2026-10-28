"""Shared-mode authorization, revocation, concurrency and data-boundary tests."""

import json
from contextlib import closing
from pathlib import Path
import re
import sqlite3
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
try:
    from open_tracker import server, tracker
except ModuleNotFoundError as error:
    if error.name not in {"flask", "werkzeug"}:
        raise
    server = None


@unittest.skipIf(server is None, "Shared mode requires requirements-shared.txt")
class SharedTrackerTests(unittest.TestCase):
    PASSWORD = "test-password-1234"
    ROW = dict(task_id="TASK-001", title="Operations review", status="In progress",
               owner="Review lead", due="", progress=20, notes="Operational metadata")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="open-tracker-server-test-")
        self.addCleanup(self.temp.cleanup)
        self.db = str(Path(self.temp.name) / "tracker.sqlite")
        self.app = server.create_app(dict(DATABASE=self.db, SECRET_KEY="test-only-" + "x" * 40,
                                          COOKIE_SECURE=False, TESTING=True))
        self.client = self.app.test_client()
        server.manage_user(self.db, "add-user", "editor", self.PASSWORD, "editor")

    def csrf(self, client=None):
        return (client or self.client).get("/api/session").json["csrf_token"]

    def post(self, path, value, client=None, token=None):
        client = client or self.client
        return client.post(path, json=value, headers={"X-CSRF-Token": token or self.csrf(client)})

    def login(self, username="editor", password=None, client=None):
        return self.post("/api/login", dict(username=username, password=password or self.PASSWORD), client)

    def save(self, row=None, expected=None, client=None):
        return self.post("/api/tasks", dict(row=row or self.ROW, expected_updated_at=expected), client)

    def test_anonymous_snapshot_and_write_are_denied(self):
        self.assertEqual(self.client.get("/api/snapshot").status_code, 401)
        self.assertEqual(self.save().status_code, 401)
        self.assertIsNone(self.client.get("/api/session").json["user"])

    def test_csrf_required_on_login_logout_and_writes(self):
        credentials = dict(username="editor", password=self.PASSWORD)
        self.assertEqual(self.client.post("/api/login", json=credentials).status_code, 403)
        self.csrf()
        self.assertEqual(self.client.post("/api/login", json=credentials,
                                         headers={"X-CSRF-Token": "wrong"}).status_code, 403)
        self.assertEqual(self.client.post("/api/login", json=credentials,
                                         headers={"X-CSRF-Token": "é"}).status_code, 403)
        self.assertEqual(self.login().status_code, 200)
        self.assertEqual(self.client.post("/api/logout", json={}).status_code, 403)
        self.assertEqual(self.client.post("/api/tasks", json={}).status_code, 403)

    def test_login_rotates_csrf_and_cookie_hides_token_from_javascript(self):
        before = self.csrf()
        response = self.login()
        self.assertEqual(response.status_code, 200)
        self.assertNotEqual(before, response.json["csrf_token"])
        self.assertEqual(response.json["user"], dict(username="editor", role="editor"))
        cookie = response.headers["Set-Cookie"]
        self.assertIn("HttpOnly", cookie)
        self.assertIn("SameSite=Lax", cookie)
        self.assertEqual(self.post("/api/logout", {}, token=before).status_code, 403)

    def test_viewer_cannot_write_but_can_read(self):
        server.manage_user(self.db, "add-user", "viewer", self.PASSWORD, "viewer")
        self.assertEqual(self.login("viewer").status_code, 200)
        self.assertEqual(self.client.get("/api/snapshot").status_code, 200)
        self.assertEqual(self.save().status_code, 403)
        self.assertEqual(tracker.snapshot(self.db)["rows"], [])

    def test_editor_save_records_actor_and_does_not_refresh_pipeline_heartbeat(self):
        self.login()
        response = self.save()
        self.assertEqual(response.status_code, 200)
        data = response.json["snapshot"]
        self.assertEqual(data["rows"][0]["task_id"], self.ROW["task_id"])
        self.assertEqual(data["events"][0]["actor"], "editor")
        self.assertIsNone(data["last_import_at"])

    def test_conflicting_edit_and_duplicate_create_return_409_without_overwrite(self):
        self.login()
        first = self.save().json["snapshot"]["rows"][0]
        newer = dict(self.ROW, progress=50)
        self.assertEqual(self.save(newer, first["updated_at"]).status_code, 200)
        self.assertEqual(self.save(dict(self.ROW, progress=80), first["updated_at"]).status_code, 409)
        self.assertEqual(self.save().status_code, 409)
        self.assertEqual(tracker.snapshot(self.db)["rows"][0]["progress"], 50)

    def test_unknown_fields_and_invalid_values_do_not_write(self):
        self.login()
        for row in (dict(self.ROW, unrelated="field"), dict(self.ROW, progress=True),
                    dict(self.ROW, due="2026-02-30"), dict(self.ROW, title=""),
                    dict(self.ROW, title="\ud800")):
            with self.subTest(row=row):
                self.assertEqual(self.save(row).status_code, 400)
        self.assertEqual(self.post("/api/tasks", dict(row=self.ROW)).status_code, 400)
        self.assertEqual(tracker.snapshot(self.db)["rows"], [])

    def test_logout_revokes_replayed_cookie(self):
        self.login()
        captured = self.client.get_cookie("open_tracker_session").value
        self.assertEqual(self.post("/api/logout", {}).status_code, 200)
        self.client.set_cookie("open_tracker_session", captured)
        self.assertEqual(self.client.get("/api/snapshot").status_code, 401)

    def test_password_reset_revokes_all_sessions_and_old_password(self):
        self.login()
        another = self.app.test_client()
        self.login(client=another)
        new_password = "changed-password-5678"
        server.manage_user(self.db, "set-password", "editor", new_password)
        for client in (self.client, another):
            self.assertEqual(client.get("/api/snapshot").status_code, 401)
        self.assertEqual(self.login().status_code, 401)
        self.assertEqual(self.login(password=new_password).status_code, 200)

    def test_disabled_user_loses_access_and_cannot_log_in(self):
        self.login()
        server.manage_user(self.db, "disable-user", "editor")
        self.assertEqual(self.client.get("/api/snapshot").status_code, 401)
        self.assertEqual(self.login().status_code, 401)

    def test_role_change_revokes_old_session_and_new_role_applies(self):
        self.login()
        server.manage_user(self.db, "set-role", "editor", role="viewer")
        self.assertEqual(self.client.get("/api/snapshot").status_code, 401)
        self.assertEqual(self.login().json["user"]["role"], "viewer")
        self.assertEqual(self.save().status_code, 403)

    def test_expired_database_session_rejects_still_valid_cookie(self):
        self.login()
        with closing(sqlite3.connect(self.db)) as db, db:
            db.execute("UPDATE web_sessions SET expires_at=?", (time.time() - 1,))
        self.assertEqual(self.client.get("/api/snapshot").status_code, 401)

    def test_only_session_hash_is_persisted(self):
        self.login()
        with self.client.session_transaction() as cookie:
            token = cookie["token"]
        with closing(sqlite3.connect(self.db)) as db, db:
            stored = db.execute("SELECT token_hash FROM web_sessions").fetchone()[0]
        self.assertNotEqual(token, stored)
        self.assertEqual(stored, server.digest(token))

    def test_login_rate_limit_persists_across_clients(self):
        for _ in range(5):
            self.assertEqual(self.login(password="wrong-password").status_code, 401)
        another = self.app.test_client()
        limited = self.login(client=another)
        self.assertEqual(limited.status_code, 429)
        self.assertEqual(limited.headers["Retry-After"], "900")
        with closing(sqlite3.connect(self.db)) as db, db:
            db.execute("UPDATE login_limits SET started_at=?", (time.time() - 901,))
        self.assertEqual(self.login(client=another).status_code, 200)

    def test_unknown_and_disabled_accounts_have_generic_failure(self):
        unknown = self.login("unknown").json
        server.manage_user(self.db, "disable-user", "editor")
        self.assertEqual(self.login().json, unknown)

    def test_page_strips_embedded_data_and_has_nonce_csp(self):
        # A replaced template could contain a real exported snapshot; no data may leak before login.
        fake = Path(self.temp.name) / "index.html"
        fake.write_text('<html lang="en"><script id="tracker-data" type="application/json">'
                        '{"rows":[{"title":"SECRET TASK"}]}</script><script>window.demo=true;</script></html>')
        with patch.object(tracker, "TEMPLATE", fake):
            response = self.client.get("/")
        page = response.get_data(as_text=True)
        self.assertNotIn("SECRET TASK", page)
        self.assertIn('data-shared="true"', page)
        self.assertIn('"rows": []', page)
        nonce = re.search(r'<script nonce="([^"]+)"', page)[1]
        self.assertIn("'nonce-" + nonce + "'", response.headers["Content-Security-Policy"])
        self.assertIn("no-store", response.headers["Cache-Control"])
        self.assertEqual(response.headers["X-Frame-Options"], "DENY")

    def test_exports_include_no_users_password_hashes_or_sessions(self):
        self.login()
        self.save()
        data = self.client.get("/api/snapshot").json
        self.assertEqual(set(data), {"schema_version", "exported_at", "last_import_at", "rows", "events"})
        text = json.dumps(data)
        for forbidden in ("password_hash", "scrypt:", "token_hash", "web_sessions", "auth_version"):
            self.assertNotIn(forbidden, text)
        destination = Path(self.temp.name) / "snapshot.json"
        tracker.export(self.db, destination, "json")
        exported = json.loads(destination.read_text())
        self.assertEqual(set(exported), set(data))

    def test_secure_cookie_is_default_and_short_secret_is_rejected(self):
        with patch.dict("os.environ", {}, clear=True):
            secure_app = server.create_app(dict(DATABASE=self.db, SECRET_KEY="a" * 40, TESTING=True))
        response = secure_app.test_client().get("/api/session", base_url="https://tracker.example")
        self.assertIn("Secure", response.headers["Set-Cookie"])
        self.assertIn("Strict-Transport-Security", response.headers)
        with self.assertRaises(tracker.TrackerError):
            server.create_app(dict(DATABASE=self.db, SECRET_KEY="too-short"))

    def test_no_generic_file_route_or_cross_origin_access(self):
        response = self.client.get("/server.py", headers={"Origin": "https://elsewhere.example"})
        self.assertEqual(response.status_code, 404)
        self.assertNotIn("Access-Control-Allow-Origin", response.headers)

    def test_internal_errors_return_json_without_sensitive_details(self):
        self.login()
        with patch.object(tracker, "snapshot", side_effect=RuntimeError("sensitive internal detail")):
            with self.assertLogs(self.app.logger, level="ERROR") as log:
                response = self.client.get("/api/snapshot")
        self.assertEqual(response.status_code, 500)
        self.assertIsInstance(response.json["error"], str)
        self.assertNotIn("sensitive internal detail", response.get_data(as_text=True))
        self.assertNotIn("sensitive internal detail", " ".join(log.output))

    def test_insecure_nonloopback_cli_bind_is_rejected(self):
        with patch.dict("os.environ", {"TRACKER_INSECURE_LOCAL": "1"}):
            self.assertEqual(server.main(["--db", self.db, "serve", "--host", "0.0.0.0"]), 1)


if __name__ == "__main__":
    unittest.main()
