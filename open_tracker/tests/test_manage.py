"""Guided setup state, secret boundaries, mail activation and backup behavior."""

from contextlib import closing, redirect_stdout, redirect_stderr
import io
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import manage
import notifications
import tracker
try:
    import server
except ModuleNotFoundError:
    server = None


class ManageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tracker managed tests ")
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name) / "private workspace"
        self.workspace.mkdir(mode=0o700)
        self.config = manage.new_config()
        self.config["interval"] = 1
        self.output = io.StringIO()
        self.addCleanup(patch.stopall)
        patch.dict(os.environ, {"TRACKER_CONTAINER": "0"}, clear=False).start()
        os.environ.pop("TRACKER_EXPECTED_PUBLIC_URL", None)

    def save(self):
        manage.save_config(self.workspace, self.config)

    def database(self):
        tracker.upsert(self.workspace / "tracker.sqlite", [{"task_id": "SYNTHETIC-007", "title": "Synthetic setup record", "status": "Blocked"}], "test")

    def smtp_config(self):
        self.config["email"].update(mode="smtp", recipients="reviewer@example.test", host="smtp.example.test",
                                    sender="sender@example.test", username="SECRET-USERNAME", password="SECRET-PASSWORD")
        return self.config

    def test_new_workspace_has_stable_private_config_and_preview_defaults(self):
        self.save()
        original = (self.workspace / "config.json").read_bytes()
        self.assertEqual(manage.load_config(self.workspace), self.config)
        self.assertEqual(self.config["email"]["mode"], "preview")
        self.assertEqual(self.config["stale_hours"], 0)
        self.assertGreaterEqual(len(self.config["secret_key"]), 32)
        self.assertEqual((self.workspace / "config.json").read_bytes(), original)
        if os.name != "nt":
            self.assertEqual((self.workspace / "config.json").stat().st_mode & 0o777, 0o600)
            self.assertEqual(self.workspace.stat().st_mode & 0o777, 0o700)

    def test_rejects_repo_and_global_workspace_directories(self):
        for path in (manage.REPOSITORY, manage.REPOSITORY / "out", manage.REPOSITORY.parent, Path.home(), Path("/")):
            with self.subTest(path=path), self.assertRaises(manage.SetupError):
                manage.workspace_path(path)

    def test_workspace_symlink_cannot_bypass_repository_boundary(self):
        link = self.workspace / "linked-repository"
        link.symlink_to(manage.REPOSITORY, target_is_directory=True)
        with self.assertRaises(manage.SetupError):
            manage.workspace_path(link / "private-data")

    def test_rejects_symlink_or_public_configuration(self):
        self.save()
        path = self.workspace / "config.json"
        target = self.workspace / "elsewhere.json"
        path.rename(target)
        path.symlink_to(target)
        with self.assertRaises(manage.SetupError):
            manage.load_config(self.workspace)
        with self.assertRaises(manage.SetupError):
            manage.save_config(self.workspace, self.config)
        path.unlink()
        target.rename(path)
        if os.name != "nt":
            path.chmod(0o644)
            with self.assertRaisesRegex(manage.SetupError, "chmod 600"):
                manage.load_config(self.workspace)

    def test_invalid_or_secret_configuration_is_not_echoed(self):
        self.config["email"]["password"] = "DO-NOT-LOG-ME"
        self.save_invalid_json({**self.config, "email": {**self.config["email"], "port": "DO-NOT-LOG-ME"}})
        with self.assertRaises(manage.SetupError) as caught:
            manage.load_config(self.workspace)
        self.assertNotIn("DO-NOT-LOG-ME", str(caught.exception))

    def save_invalid_json(self, value):
        path = self.workspace / "config.json"
        path.write_text(json.dumps(value))
        path.chmod(0o600)

    def test_failed_atomic_save_preserves_existing_configuration(self):
        self.save()
        before = (self.workspace / "config.json").read_bytes()
        with patch.object(manage.os, "replace", side_effect=OSError("synthetic replacement error")):
            with self.assertRaises(OSError):
                manage.save_config(self.workspace, manage.new_config())
        self.assertEqual((self.workspace / "config.json").read_bytes(), before)
        self.assertEqual(list(self.workspace.glob(".config-*")), [])

    def test_numeric_and_schema_errors_fail_closed(self):
        for field, value in (("version", True), ("interval", 0), ("interval", float("nan")), ("stale_hours", -1)):
            candidate = json.loads(json.dumps(self.config))
            candidate[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(manage.SetupError):
                manage.validate_config(candidate)
        with self.assertRaises(manage.SetupError):
            manage.validate_config({**self.config, "unexpected": True})

    def test_team_origin_is_normalized_and_rejects_unsafe_values(self):
        self.assertEqual(manage.public_url("https://TRACKER.example.test:443/"), "https://tracker.example.test")
        self.assertEqual(manage.public_url("https://tracker.example.test:8443"), "https://tracker.example.test:8443")
        for value in ("http://tracker.example.test", "https://user:pass@example.test", "https://example.test/path", "https://example.test#fragment", "https://example.test?x=y", "https://example.test:0", "https://example.test\n", "https://tracker{bad", "https://foo;bar", "https://-bad.example", "https://bad_.example", "https://bad..example"):
            with self.subTest(value=value), self.assertRaises(manage.SetupError):
                manage.public_url(value)

    def test_container_url_and_hosting_url_must_agree(self):
        with patch.dict(os.environ, TRACKER_CONTAINER="1"):
            with self.assertRaises(manage.SetupError):
                manage.check_expected_url(self.config)
            self.config["public_url"] = "https://tracker.example.test:8443"
            with self.assertRaises(manage.SetupError):
                manage.check_expected_url(self.config)
            self.config["public_url"] = "https://tracker.example.test"
            manage.check_expected_url(self.config)
            with patch.dict(os.environ, TRACKER_EXPECTED_PUBLIC_URL="https://different.example.test"):
                with self.assertRaises(manage.SetupError):
                    manage.check_expected_url(self.config)

    def test_environment_ignores_shell_secrets_and_off_mode_stays_off(self):
        self.database()
        self.config["email"]["mode"] = "off"
        with patch.dict(os.environ, TRACKER_USER_PASSWORD="shell-admin-password", TRACKER_ALERT_TO="unwanted@example.test", TRACKER_INSECURE_LOCAL="0"):
            env = manage.runtime_environment(self.workspace, self.config)
        self.assertNotIn("TRACKER_USER_PASSWORD", env)
        self.assertEqual(env["TRACKER_ALERT_TO"], "")
        self.assertEqual(env["TRACKER_INSECURE_LOCAL"], "1")
        self.assertEqual(env["TRACKER_SECRET_KEY"], self.config["secret_key"])
        self.config["public_url"] = "https://tracker.example.test"
        self.assertNotIn("TRACKER_INSECURE_LOCAL", manage.runtime_environment(self.workspace, self.config))

    def test_runtime_rejects_missing_or_symlink_database(self):
        with self.assertRaises(manage.SetupError):
            manage.runtime_environment(self.workspace, self.config)
        target = self.workspace / "elsewhere.sqlite"
        target.touch()
        (self.workspace / "tracker.sqlite").symlink_to(target)
        with self.assertRaises(manage.SetupError):
            manage.runtime_environment(self.workspace, self.config)

    @unittest.skipIf(server is None, "Shared setup needs requirements-shared.txt")
    def test_guided_setup_empty_by_default_and_rerun_preserves_account(self):
        with patch.object(manage, "require_terminal"), patch.object(manage, "prompt", side_effect=["reviewer", "Synthetic long password", "Synthetic long password", "no"]), redirect_stdout(self.output):
            manage.setup(self.workspace)
        self.assertEqual(tracker.snapshot(self.workspace / "tracker.sqlite")["rows"], [])
        original = manage.load_config(self.workspace)
        with patch.object(manage, "require_terminal"), patch.object(manage, "prompt", side_effect=AssertionError("must not reprompt")), redirect_stdout(self.output):
            manage.setup(self.workspace, "https://tracker.example.test")
        with patch.object(manage, "require_terminal"), patch.dict(os.environ, TRACKER_CONTAINER="1"):
            with self.assertRaises(manage.SetupError):
                manage.setup(self.workspace, "https://tracker.example.test:8443")
        updated = manage.load_config(self.workspace)
        self.assertEqual(updated["secret_key"], original["secret_key"])
        self.assertEqual(updated["public_url"], "https://tracker.example.test")
        with closing(sqlite3.connect(self.workspace / "tracker.sqlite")) as db:
            self.assertEqual(db.execute("SELECT username,role FROM users").fetchall(), [("reviewer", "admin")])

    @unittest.skipIf(server is None, "Shared setup needs requirements-shared.txt")
    def test_demo_is_explicit_and_password_mismatch_creates_no_state(self):
        with patch.object(manage, "require_terminal"), patch.object(manage, "prompt", side_effect=["reviewer", "Synthetic long password", "Wrong long password"]):
            with self.assertRaises(manage.SetupError):
                manage.setup(self.workspace, demo=True)
        self.assertEqual(list(self.workspace.iterdir()), [])
        with patch.object(manage, "require_terminal"), patch.object(manage, "prompt", side_effect=["reviewer", "Synthetic long password", "Synthetic long password"]), redirect_stdout(self.output):
            manage.setup(self.workspace, demo=True)
        self.assertEqual(len(tracker.snapshot(self.workspace / "tracker.sqlite")["rows"]), 4)

    def test_smtp_activation_requires_explicit_enable_and_never_sends_during_configuration(self):
        self.save()
        before = (self.workspace / "config.json").read_bytes()
        answers = ["smtp", "reviewer@example.test", "smtp.example.test", "starttls", "587", "sender@example.test", "smtp-account", "smtp-secret", "no", "no"]
        with patch.object(manage, "require_terminal"), patch.object(manage, "prompt", side_effect=answers), patch.object(notifications, "smtp_send") as send, redirect_stdout(self.output):
            manage.configure_email(self.workspace, self.config)
        self.assertFalse(send.called)
        self.assertEqual((self.workspace / "config.json").read_bytes(), before)
        answers[-1] = "ENABLE"
        with patch.object(manage, "require_terminal"), patch.object(manage, "prompt", side_effect=answers), patch.object(notifications, "smtp_send") as send, redirect_stdout(self.output):
            manage.configure_email(self.workspace, self.config)
        self.assertFalse(send.called)
        saved = manage.load_config(self.workspace)
        self.assertEqual(saved["email"]["mode"], "smtp")
        self.assertNotIn("smtp-secret", self.output.getvalue())

    def test_preview_test_works_without_database_or_network(self):
        with patch.object(notifications, "smtp_send") as send, redirect_stdout(self.output):
            manage.email_test(self.workspace, self.smtp_config())
        self.assertFalse(send.called)
        self.assertFalse((self.workspace / "tracker.sqlite").exists())
        files = list((self.workspace / "mail-preview").glob("*.eml"))
        self.assertEqual(len(files), 1)
        text = files[0].read_text()
        self.assertIn("No email was sent", text)
        self.assertNotIn("SECRET-PASSWORD", text)
        if os.name != "nt":
            self.assertEqual(files[0].stat().st_mode & 0o777, 0o600)

    def test_explicit_test_delivery_is_single_recipient_without_outbox(self):
        with patch.object(notifications, "smtp_send") as send, redirect_stdout(self.output):
            manage.email_test(self.workspace, self.smtp_config(), send=True, recipient="test-reader@example.test")
        self.assertEqual(send.call_count, 1)
        message, config, recipient = send.call_args.args
        self.assertEqual(recipient, "test-reader@example.test")
        self.assertEqual(message["To"], recipient)
        self.assertEqual(config.username, "SECRET-USERNAME")
        self.assertFalse((self.workspace / "tracker.sqlite").exists())
        for recipient in (None, "one@example.test,two@example.test", "x@example.test\nBcc: a@example.test"):
            with self.subTest(recipient=recipient), self.assertRaises(manage.SetupError):
                manage.email_test(self.workspace, self.config, send=True, recipient=recipient)
        self.config["email"]["mode"] = "preview"
        with self.assertRaises(manage.SetupError):
            manage.email_test(self.workspace, self.config, send=True, recipient="reader@example.test")

    def test_transport_error_is_redacted(self):
        with patch.object(notifications, "smtp_send", side_effect=OSError("SECRET-PASSWORD and provider reply")):
            with self.assertRaises(manage.SetupError) as error:
                manage.email_test(self.workspace, self.smtp_config(), send=True, recipient="reader@example.test")
        self.assertNotIn("SECRET-PASSWORD", str(error.exception))
        self.assertIn("OSError", str(error.exception))

    def test_backup_is_consistent_private_and_never_overwrites(self):
        self.database()
        target = self.workspace / "backups" / "snapshot.sqlite"
        with redirect_stdout(self.output):
            manage.backup(self.workspace, target)
        self.assertEqual(tracker.snapshot(target)["rows"], tracker.snapshot(self.workspace / "tracker.sqlite")["rows"])
        before = target.read_bytes()
        with self.assertRaises(FileExistsError):
            manage.backup(self.workspace, target)
        self.assertEqual(target.read_bytes(), before)
        with self.assertRaises(manage.SetupError):
            manage.backup(self.workspace, manage.REPOSITORY / "export.sqlite")
        if os.name != "nt":
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)

    def test_existing_venv_is_reused_without_installation(self):
        executable = self.workspace / ".venv" / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
        executable.parent.mkdir(parents=True)
        executable.touch()
        with patch.object(manage, "requirements_ready", return_value=False), patch.object(manage.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as run, patch.object(manage.os, "execve", side_effect=SystemExit(0)) as execute:
            with self.assertRaises(SystemExit):
                manage.ensure_runtime(self.workspace, ["--workspace", str(self.workspace), "start"])
        self.assertEqual(run.call_count, 1)
        self.assertNotIn("pip", run.call_args.args[0])
        self.assertEqual(execute.call_count, 1)

    def test_doctor_never_installs_missing_dependencies(self):
        with patch.object(manage, "requirements_ready", return_value=False), patch.object(manage.subprocess, "run") as run:
            with self.assertRaises(manage.SetupError):
                manage.ensure_runtime(self.workspace, ["doctor"], install=False)
        self.assertFalse(run.called)


if __name__ == "__main__":
    unittest.main()
