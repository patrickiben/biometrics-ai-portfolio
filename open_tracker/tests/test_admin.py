"""Browser setup/admin security and state transitions, with synthetic accounts."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
try:
    from open_tracker import manage, server, tracker, web_setup
except ModuleNotFoundError as error:
    if error.name not in {"flask", "werkzeug"}:
        raise
    web_setup = None


@unittest.skipIf(web_setup is None, "Browser administration needs requirements-shared.txt")
class BrowserAdminTests(unittest.TestCase):
    PASSWORD = "Synthetic admin password 2026"
    TOKEN = "synthetic-bootstrap-token-" + "a" * 40

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tracker browser admin ")
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name)
        self.app = web_setup.create_web_app(self.workspace, setup_token=self.TOKEN, env={})
        self.app.config["TESTING"] = True
        self.client = self.app.test_client()

    def csrf(self, client=None):
        return (client or self.client).get("/api/session").json["csrf_token"]

    def post(self, path, data, client=None, **kwargs):
        client = client or self.client
        return client.post(path, json=data, headers={"X-CSRF-Token": self.csrf(client)}, **kwargs)

    def setup(self, demo=False):
        return self.post("/api/setup", dict(setup_token=self.TOKEN, username="admin", password=self.PASSWORD,
                                           password_confirm=self.PASSWORD, demo=demo))

    def login(self, username="admin", client=None):
        return self.post("/api/login", dict(username=username, password=self.PASSWORD), client)

    def ready(self):
        self.assertEqual(self.setup().status_code, 200)
        self.assertEqual(self.login().status_code, 200)

    def account(self, command, username, role=None, password=None, client=None):
        return self.post("/api/admin/users", dict(command=command, username=username, role=role, password=password), client)

    def email_data(self, **overrides):
        mail = dict(mode="smtp", recipients="recipient@example.test", host="smtp.example.test", port=587,
                    security="starttls", sender="sender@example.test", username="smtp-user", password="synthetic-mail-password")
        mail.update(overrides)
        return dict(email=mail, stale_hours=0, confirm_live=True)

    def test_first_setup_requires_token_csrf_and_origin(self):
        data = dict(setup_token=self.TOKEN, username="admin", password=self.PASSWORD,
                    password_confirm=self.PASSWORD, demo=False)
        self.assertEqual(self.client.post("/api/setup", json=data).status_code, 403)
        self.assertEqual(self.post("/api/setup", dict(data, setup_token="wrong")).status_code, 403)
        csrf = self.csrf()
        response = self.client.post("/api/setup", json=data, headers={"X-CSRF-Token": csrf, "Origin": "https://other.test"})
        self.assertEqual(response.status_code, 403)
        self.assertFalse((self.workspace / "config.json").exists())
        self.assertEqual(self.setup().status_code, 200)
        self.assertIn(self.setup().status_code, (403, 409))

    def test_empty_setup_persists_secret_private_settings_and_hashed_password(self):
        self.assertFalse(self.client.get("/api/setup/state").json["configured"])
        self.assertEqual(self.setup().status_code, 200)
        config = manage.load_config(self.workspace)
        self.assertEqual(config["secret_key"], self.app.config["SECRET_KEY"])
        self.assertEqual(config["email"]["mode"], "preview")
        self.assertEqual(self.login().json["user"]["admin_ui"], True)
        self.assertEqual(self.client.get("/api/snapshot").json["rows"], [])
        with closing(sqlite3.connect(self.workspace / "tracker.sqlite")) as db:
            row = db.execute("SELECT role,password_hash FROM users").fetchone()
        self.assertEqual(row[0], "admin")
        self.assertTrue(row[1].startswith("scrypt:"))
        self.assertNotIn(self.PASSWORD, row[1])
        (self.workspace / "config.json").unlink()
        with self.assertRaises(manage.SetupError):
            web_setup.create_web_app(self.workspace, setup_token=self.TOKEN, env={})

    def test_demo_is_optional_and_records_synthetic_history(self):
        self.assertEqual(self.setup(demo=True).status_code, 200)
        self.login()
        snap = self.client.get("/api/snapshot").json
        self.assertEqual(len(snap["rows"]), 4)
        self.assertEqual(len(snap["events"]), 4)
        self.assertTrue(all(e["actor"] == "synthetic-demo" for e in snap["events"]))
        self.assertIsNotNone(snap["last_import_at"])

    def test_setup_failure_rolls_back_account_and_configuration(self):
        with patch.object(manage, "save_config", side_effect=manage.SetupError("Synthetic write failure")):
            self.assertEqual(self.setup().status_code, 400)
        with closing(sqlite3.connect(self.workspace / "tracker.sqlite")) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM users").fetchone()[0], 0)
        self.assertFalse((self.workspace / "config.json").exists())
        self.assertEqual(self.setup().status_code, 200)

    def test_concurrent_first_claims_create_exactly_one_administrator(self):
        second_app = web_setup.create_web_app(self.workspace, setup_token=self.TOKEN, env={})
        clients = [self.client, second_app.test_client()]
        def claim(item):
            index, client = item
            return self.post("/api/setup", dict(setup_token=self.TOKEN, username=f"admin{index}", password=self.PASSWORD,
                                                password_confirm=self.PASSWORD, demo=False), client)
        with ThreadPoolExecutor(max_workers=2) as pool:
            responses = list(pool.map(claim, enumerate(clients)))
        self.assertEqual(sorted(r.status_code for r in responses), [200, 409])
        with closing(sqlite3.connect(self.workspace / "tracker.sqlite")) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM users").fetchone()[0], 1)
        self.assertTrue((self.workspace / "config.json").is_file())

    def test_only_admins_read_or_change_settings_and_accounts(self):
        self.assertEqual(self.client.get("/api/admin/state").status_code, 401)
        self.ready()
        for role in ("viewer", "editor"):
            self.assertEqual(self.account("add-user", role, role, self.PASSWORD).status_code, 200)
            other = self.app.test_client()
            self.login(role, other)
            self.assertEqual(other.get("/api/admin/state").status_code, 403)
            self.assertEqual(other.get("/api/admin/backup").status_code, 403)
            self.assertEqual(self.account("add-user", "hacker", "admin", self.PASSWORD, other).status_code, 403)
            self.assertEqual(self.post("/api/admin/email", self.email_data(), other).status_code, 403)

    def test_account_management_revokes_sessions_and_prevents_self_lockout(self):
        self.ready()
        self.assertEqual(self.account("disable-user", "admin").status_code, 409)
        self.assertEqual(self.account("set-role", "admin", role="editor").status_code, 409)
        self.assertEqual(self.account("add-user", "reviewer", "editor", self.PASSWORD).status_code, 200)
        other = self.app.test_client()
        self.login("reviewer", other)
        self.assertEqual(self.account("set-role", "reviewer", role="viewer").status_code, 200)
        self.assertIsNone(other.get("/api/session").json["user"])
        self.assertEqual(self.account("disable-user", "reviewer").status_code, 200)
        self.assertEqual(self.login("reviewer", other).status_code, 401)
        self.assertEqual(self.account("enable-user", "reviewer").status_code, 200)
        self.assertEqual(self.login("reviewer", other).status_code, 200)
        response = self.account("set-password", "admin", password="New synthetic password 2026")
        self.assertTrue(response.json["signed_out"])
        self.assertEqual(self.client.get("/api/admin/state").status_code, 401)

    def test_concurrent_admin_removal_cannot_remove_every_admin(self):
        self.ready()
        self.account("add-user", "second", "admin", self.PASSWORD)
        second = self.app.test_client()
        self.login("second", second)
        with ThreadPoolExecutor(max_workers=2) as pool:
            responses = list(pool.map(lambda pair: self.account("disable-user", pair[1], client=pair[0]),
                                      [(self.client, "second"), (second, "admin")]))
        self.assertEqual(sum(r.status_code == 200 for r in responses), 1)
        with closing(sqlite3.connect(self.workspace / "tracker.sqlite")) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM users WHERE enabled=1 AND role='admin'").fetchone()[0], 1)

    def test_smtp_settings_require_confirmation_tls_and_hide_password(self):
        self.ready()
        data = self.email_data()
        self.assertEqual(self.post("/api/admin/email", dict(data, confirm_live=False)).status_code, 400)
        self.assertEqual(self.post("/api/admin/email", self.email_data(security="plain", host="127.0.0.1")).status_code, 400)
        self.assertEqual(self.post("/api/admin/email", data).status_code, 200)
        state = self.client.get("/api/admin/state")
        self.assertTrue(state.json["email"]["password_configured"])
        self.assertNotIn("password", state.json["email"])
        self.assertNotIn("synthetic-mail-password", state.get_data(as_text=True))
        self.assertNotIn(manage.load_config(self.workspace)["secret_key"], state.get_data(as_text=True))
        self.assertEqual(self.post("/api/admin/email", self.email_data(password=None, recipients="other@example.test")).status_code, 200)
        self.assertEqual(manage.load_config(self.workspace)["email"]["password"], "synthetic-mail-password")
        self.assertEqual(self.post("/api/admin/email", self.email_data(password=None, mode="off")).status_code, 200)
        self.assertEqual(manage.load_config(self.workspace)["email"]["password"], "synthetic-mail-password")

    def test_email_preview_never_sends_and_test_send_requires_one_explicit_recipient(self):
        self.ready()
        self.post("/api/admin/email", self.email_data())
        with patch("open_tracker.notifications.smtp_send") as send:
            response = self.post("/api/admin/email-test", dict(send=False, to=None, confirm_send=False))
            self.assertIn("No email was sent", response.json["preview"])
            send.assert_not_called()
            self.assertEqual(self.post("/api/admin/email-test", dict(send=True, to="recipient@example.test", confirm_send=False)).status_code, 400)
            self.assertEqual(self.post("/api/admin/email-test", dict(send=True, to="one@example.test,two@example.test", confirm_send=True)).status_code, 400)
            self.assertEqual(self.post("/api/admin/email-test", dict(send=True, to="test-only@example.test", confirm_send=True)).status_code, 200)
            self.assertEqual(send.call_count, 1)
            self.assertEqual(send.call_args.args[2], "test-only@example.test")
        with closing(sqlite3.connect(self.workspace / "tracker.sqlite")) as db:
            self.assertIsNone(db.execute("SELECT name FROM sqlite_master WHERE name='notification_outbox'").fetchone())

    def test_clear_saved_password_retains_provider_settings_until_live_reactivation(self):
        self.ready()
        with patch("open_tracker.notifications.smtp_send") as send:
            for mode in ("off", "preview"):
                with self.subTest(mode=mode):
                    self.assertEqual(self.post("/api/admin/email", self.email_data()).status_code, 200)
                    cleared = self.email_data(mode=mode, password="")
                    self.assertEqual(self.post("/api/admin/email", cleared).status_code, 200)
                    saved = manage.load_config(self.workspace)
                    self.assertEqual(saved["email"], cleared["email"])
                    self.assertEqual(saved["email"]["username"], "smtp-user")
                    self.assertFalse(self.client.get("/api/admin/state").json["email"]["password_configured"])
                    env = manage.email_environment(saved)
                    self.assertEqual(env["TRACKER_SMTP_USERNAME"], "")
                    self.assertEqual(env["TRACKER_SMTP_PASSWORD"], "")
                    before = (self.workspace / "config.json").read_bytes()
                    self.assertEqual(self.post("/api/admin/email", self.email_data(password=None)).status_code, 400)
                    self.assertEqual((self.workspace / "config.json").read_bytes(), before)
                    self.assertEqual(self.post("/api/admin/email-test", dict(send=True, to="test@example.test", confirm_send=True)).status_code, 400)
            send.assert_not_called()

    def test_malformed_email_types_return_validation_errors_without_mutation(self):
        self.ready()
        before = (self.workspace / "config.json").read_bytes()
        for key, value in (("mode", []), ("recipients", None), ("host", {}), ("port", "587"),
                           ("port", True), ("username", []), ("password", ["secret"])):
            with self.subTest(field=key, value=value):
                self.assertEqual(self.post("/api/admin/email", self.email_data(**{key: value})).status_code, 400)
                self.assertEqual((self.workspace / "config.json").read_bytes(), before)
        self.post("/api/admin/email", self.email_data())
        with patch("open_tracker.notifications.smtp_send") as send:
            for recipient in (None, ["recipient@example.test"], {"to": "recipient@example.test"}, True):
                with self.subTest(recipient=recipient):
                    self.assertEqual(self.post("/api/admin/email-test", dict(send=True, to=recipient, confirm_send=True)).status_code, 400)
            send.assert_not_called()

    def test_backup_is_authenticated_sqlite_and_excludes_mail_settings(self):
        self.ready()
        self.post("/api/admin/email", self.email_data())
        response = self.client.get("/api/admin/backup")
        self.assertEqual(response.status_code, 200)
        self.assertIn("attachment", response.headers["Content-Disposition"])
        self.assertTrue(response.data.startswith(b"SQLite format 3"))
        self.assertNotIn(b"synthetic-mail-password", response.data)
        response.close()
        self.assertFalse(list(self.workspace.glob("tracker-backup-*")))

    def test_local_stop_is_desktop_only_and_needs_confirmation(self):
        self.ready()
        self.assertEqual(self.post("/api/admin/stop", dict(confirm=True)).status_code, 403)
        callback = lambda: None
        self.app.config["DESKTOP_INSTANCE"] = "synthetic-desktop-instance"
        self.app.extensions["tracker_stop"] = callback
        self.assertTrue(self.client.get("/api/admin/state").json["can_stop"])
        self.assertEqual(self.post("/api/admin/stop", dict(confirm=False)).status_code, 400)
        with patch("open_tracker.admin.threading.Timer") as timer:
            self.assertEqual(self.post("/api/admin/stop", dict(confirm=True)).status_code, 200)
            timer.assert_called_once_with(.5, callback)


if __name__ == "__main__":
    unittest.main()
