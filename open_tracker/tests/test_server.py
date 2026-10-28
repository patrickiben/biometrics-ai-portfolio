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
            secure_app = server.create_app(dict(DATABASE=self.db, SECRET_KEY="a" * 40, TRUSTED_HOSTS=["tracker.example"], TESTING=True))
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

    def test_revocation_during_write_cannot_commit(self):
        original = tracker.upsert
        for index, command in enumerate(("disable-user", "set-role", "set-password")):
            username = f"race{index}"
            server.manage_user(self.db, "add-user", username, self.PASSWORD, "editor")
            self.assertEqual(self.login(username).status_code, 200)

            def revoke_then_write(*args, **kwargs):
                server.manage_user(self.db, command, username,
                                   "changed-password-9876" if command == "set-password" else None,
                                   "viewer" if command == "set-role" else "editor")
                return original(*args, **kwargs)

            with self.subTest(command=command), patch.object(tracker, "upsert", side_effect=revoke_then_write):
                response = self.save(dict(self.ROW, task_id=f"RACE-{index}"))
            self.assertEqual(response.status_code, 401)
        self.assertEqual(tracker.snapshot(self.db)["rows"], [])

    def test_revocation_during_snapshot_cannot_expose_rows(self):
        tracker.upsert(self.db, [dict(self.ROW, title="Private operational title")], "test")
        self.login()
        original = tracker.snapshot

        def revoke_then_read(*args, **kwargs):
            server.manage_user(self.db, "disable-user", "editor")
            return original(*args, **kwargs)

        with patch.object(tracker, "snapshot", side_effect=revoke_then_read):
            response = self.client.get("/api/snapshot")
        self.assertEqual(response.status_code, 401)
        self.assertNotIn("Private operational title", response.get_data(as_text=True))

    def test_web_json_rejects_duplicate_properties_and_nonfinite_constants(self):
        token = self.csrf()
        for raw in (
            '{"username":"unknown","username":"editor","password":"' + self.PASSWORD + '"}',
            '{"username":NaN,"password":"x"}',
            '{"username":"editor","password":Infinity}',
        ):
            with self.subTest(raw=raw):
                response = self.client.post("/api/login", data=raw, content_type="application/json", headers={"X-CSRF-Token": self.csrf()})
                self.assertEqual(response.status_code, 400)
        self.login()
        raw = json.dumps(dict(row=self.ROW, expected_updated_at=None)).replace('"progress": 20', '"progress": 20, "progress": 90')
        response = self.client.post("/api/tasks", data=raw, content_type="application/json", headers={"X-CSRF-Token": self.csrf()})
        self.assertEqual(response.status_code, 400)
        self.assertEqual(tracker.snapshot(self.db)["rows"], [])

    def test_malformed_deep_large_and_nonjson_bodies_fail_without_writes(self):
        self.login()
        headers = {"X-CSRF-Token": self.csrf()}
        for raw in ('{', '[' * 1500 + '0' + ']' * 1500, '\xff'):
            with self.subTest(raw=raw[:20]):
                response = self.client.post("/api/tasks", data=raw.encode("latin-1"), content_type="application/json", headers=headers)
                self.assertEqual(response.status_code, 400)
        response = self.client.post("/api/tasks", data="x" * 70000, content_type="application/json", headers=headers)
        self.assertEqual(response.status_code, 413)
        response = self.client.post("/api/tasks", data="{}", content_type="text/plain", headers=headers)
        self.assertEqual(response.status_code, 415)
        self.assertEqual(tracker.snapshot(self.db)["rows"], [])

    def test_arbitrary_host_and_nonloopback_insecure_peer_are_rejected(self):
        self.assertEqual(self.client.get("/api/session", headers={"Host": "attacker.example"}).status_code, 400)
        response = self.client.get("/api/session", environ_overrides={"REMOTE_ADDR": "203.0.113.7"})
        self.assertEqual(response.status_code, 403)
        response = self.client.get("/api/session", environ_overrides={"REMOTE_ADDR": "203.0.113.7"},
                                   headers={"X-Forwarded-For": "127.0.0.1", "Forwarded": "for=127.0.0.1;host=localhost"})
        self.assertEqual(response.status_code, 403)

    def test_cross_origin_unsafe_requests_rejected_even_with_valid_token(self):
        token = self.csrf()
        for origin in ("https://attacker.example", "null", "http://localhost.attacker.example", "http://localhost:8001"):
            with self.subTest(origin=origin):
                response = self.client.post("/api/login", json=dict(username="editor", password=self.PASSWORD),
                                             headers={"X-CSRF-Token": self.csrf(), "Origin": origin})
                self.assertEqual(response.status_code, 403)
        response = self.client.post("/api/login", json=dict(username="editor", password=self.PASSWORD),
                                     headers={"X-CSRF-Token": self.csrf(), "Origin": "http://localhost"})
        self.assertEqual(response.status_code, 200)

    def test_untrusted_forwarded_headers_do_not_bypass_login_throttle(self):
        token = self.csrf()
        for index in range(6):
            response = self.client.post("/api/login", json=dict(username="editor", password="wrong-password"),
                headers={"X-CSRF-Token": token, "X-Forwarded-For": f"198.51.100.{index + 1}", "X-Real-IP": f"198.51.100.{index + 1}"})
            self.assertEqual(response.status_code, 401 if index < 5 else 429)

    def test_tampered_cookie_and_anonymous_file_routes_expose_nothing(self):
        self.login()
        cookie = self.client.get_cookie("open_tracker_session").value
        self.client.set_cookie("open_tracker_session", cookie + "tampered")
        self.assertEqual(self.client.get("/api/snapshot").status_code, 401)
        for path in ("/tracker.sqlite", "/.env", "/api/users", "/api/export", "/../server.py", "/open_tracker/server.py"):
            with self.subTest(path=path):
                response = self.client.get(path)
                self.assertEqual(response.status_code, 404)
                self.assertNotIn("password_hash", response.get_data(as_text=True))

    def test_role_is_rechecked_under_write_lock_even_without_session_revocation(self):
        self.login()
        original = tracker.upsert

        def downgrade_then_write(*args, **kwargs):
            with closing(sqlite3.connect(self.db)) as db, db:
                db.execute("UPDATE users SET role='viewer' WHERE username='editor'")
            return original(*args, **kwargs)

        with patch.object(tracker, "upsert", side_effect=downgrade_then_write):
            self.assertEqual(self.save().status_code, 403)
        self.assertEqual(tracker.snapshot(self.db)["rows"], [])

    def test_https_origin_works_through_proxy_without_trusting_forwarded_headers(self):
        app = server.create_app(dict(DATABASE=self.db, SECRET_KEY="proxy-test-" + "z" * 40,
                                     COOKIE_SECURE=True, TRUSTED_HOSTS=["tracker.example"], TESTING=True))
        client = app.test_client()
        token = client.get("/api/session", base_url="https://tracker.example").json["csrf_token"]
        # The proxy preserves Host and terminates TLS; its upstream WSGI scheme
        # may be HTTP. The application derives the expected origin from its
        # secure-cookie setting rather than untrusted X-Forwarded-* values.
        response = client.post("/api/login", base_url="https://tracker.example",
            environ_overrides={"wsgi.url_scheme": "http"},
            json=dict(username="editor", password=self.PASSWORD),
            headers={"X-CSRF-Token": token, "Origin": "https://tracker.example:443", "X-Forwarded-Host": "attacker.example"})
        self.assertEqual(response.status_code, 200)
        self.assertIn("Secure", response.headers["Set-Cookie"])

    def test_ipv6_loopback_and_invalid_host_configuration(self):
        response = self.client.get("/api/session", base_url="http://[::1]:8080", environ_overrides={"REMOTE_ADDR": "::1"})
        self.assertEqual(response.status_code, 200)
        for hosts in ([], [".example.com"], ["https://example.com"], ["example.com/path"]):
            with self.subTest(hosts=hosts), self.assertRaises(tracker.TrackerError):
                server.create_app(dict(DATABASE=self.db, SECRET_KEY="test-" + "z" * 40, TRUSTED_HOSTS=hosts))

    def test_invalid_unicode_cli_password_fails_without_account(self):
        with self.assertRaises(tracker.TrackerError):
            server.manage_user(self.db, "add-user", "invalid", "a" * 20 + "\ud800")
        with closing(sqlite3.connect(self.db)) as db:
            self.assertIsNone(db.execute("SELECT username FROM users WHERE username='invalid'").fetchone())


if __name__ == "__main__":
    unittest.main()
