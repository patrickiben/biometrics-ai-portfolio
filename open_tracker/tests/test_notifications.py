"""SMTP/outbox tests; all network sends are replaced by a fake SMTP object."""

from contextlib import closing
from email import policy
from email.parser import BytesParser
import json
from pathlib import Path
import smtplib
import socketserver
import sqlite3
import ssl
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import notifications as mail
import tracker

REAL_SMTP = smtplib.SMTP


class FakeSMTP:
    instances = []
    refused = set()
    fail = False

    def __init__(self, host, port, **kwargs):
        self.host, self.port, self.kwargs = host, port, kwargs
        self.calls = []
        self.messages = []
        self.__class__.instances.append(self)

    def ehlo(self):
        self.calls.append("ehlo")

    def starttls(self, context):
        self.context = context
        self.calls.append("starttls")

    def login(self, username, password):
        self.calls.append("login")

    def send_message(self, message, from_addr, to_addrs):
        self.calls.append("send")
        self.messages.append((message, from_addr, to_addrs))
        if self.fail:
            raise smtplib.SMTPAuthenticationError(535, b"SECRET server reply must not be saved")
        return {recipient: (550, b"refused") for recipient in to_addrs if recipient in self.refused}

    def close(self):
        self.calls.append("close")


class NotificationsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tracker-mail-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.db = self.root / "tracker.sqlite3"
        self.preview = self.root / "preview"
        tracker.upsert(self.db, [{"task_id": "A", "title": "Synthetic title", "status": "In progress", "notes": "PRIVATE FREE TEXT"}], "test")
        self.clock = time.time()
        self.env = {
            "TRACKER_ALERT_TO": "reviewer@example.invalid",
            "TRACKER_SMTP_HOST": "smtp.example.invalid",
            "TRACKER_SMTP_FROM": "tracker@example.invalid",
        }
        self.config = mail.Config.from_env(self.env)
        FakeSMTP.instances, FakeSMTP.refused, FakeSMTP.fail = [], set(), False
        self.smtp = patch.object(mail.smtplib, "SMTP", FakeSMTP)
        self.ssl_smtp = patch.object(mail.smtplib, "SMTP_SSL", FakeSMTP)
        self.smtp.start()
        self.ssl_smtp.start()
        self.addCleanup(self.smtp.stop)
        self.addCleanup(self.ssl_smtp.stop)

    def update(self, **values):
        tracker.upsert(self.db, [dict(task_id="A", **values)], "test")

    def run_worker(self, config=None, *, preview=False, clock=None, stale_hours=0):
        return mail.run_once(self.db, config or self.config, self.preview if preview else None, stale_hours, self.clock if clock is None else clock)

    def outbox(self):
        with closing(sqlite3.connect(self.db)) as db, db:
            db.row_factory = sqlite3.Row
            return [dict(row) for row in db.execute("SELECT * FROM notification_outbox ORDER BY id")]

    def test_disabled_worker_does_not_create_tables_or_consume_events(self):
        self.update(status="At risk")
        result = self.run_worker(mail.Config.from_env({}))
        self.assertFalse(result["enabled"])
        with closing(sqlite3.connect(self.db)) as db, db:
            self.assertFalse(db.execute("SELECT name FROM sqlite_master WHERE name LIKE 'notification_%'").fetchall())
        result = self.run_worker()
        self.assertEqual(result["sent"], 1)

    def test_entering_risk_sends_once_and_ignores_unrelated_edits(self):
        self.update(status="At risk")
        self.assertEqual(self.run_worker()["sent"], 1)
        self.update(notes="A different private note")
        self.assertEqual(self.run_worker()["sent"], 0)
        self.update(status="At risk")  # No core event at all.
        self.assertEqual(self.run_worker()["sent"], 0)
        self.assertEqual(len(self.outbox()), 1)
        self.update(status="Blocked")
        self.assertEqual(self.run_worker()["sent"], 1)

    def test_initial_risk_creation_is_a_transition(self):
        tracker.upsert(self.db, [{"task_id": "B", "title": "Synthetic", "status": "Blocked"}], "test")
        self.assertEqual(self.run_worker()["sent"], 1)
        self.assertEqual(self.outbox()[0]["task_id"], "B")

    def test_first_enablement_skips_resolved_and_superseded_history(self):
        self.update(status="At risk")
        self.update(status="In progress")
        self.assertEqual(self.run_worker()["sent"], 0)
        self.update(status="At risk")
        self.update(status="Blocked")
        self.assertEqual(self.run_worker()["sent"], 1)
        self.assertEqual(self.outbox()[0]["expected_status"], "Blocked")

    def test_preview_has_no_smtp_and_can_later_be_delivered(self):
        self.update(status="Blocked")
        result = self.run_worker(preview=True)
        self.assertEqual((result["previewed"], result["sent"]), (1, 0))
        self.assertFalse(FakeSMTP.instances)
        self.assertEqual(self.outbox()[0]["state"], "previewed")
        self.assertEqual(self.outbox()[0]["attempts"], 0)
        files = list(self.preview.glob("*.eml"))
        self.assertEqual(len(files), 1)
        initial_bytes = files[0].read_bytes()
        self.assertEqual(self.run_worker(preview=True)["previewed"], 0)
        self.assertEqual(files[0].read_bytes(), initial_bytes)
        preview = BytesParser(policy=policy.default).parsebytes(initial_bytes)
        self.assertNotIn("PRIVATE FREE TEXT", preview.get_content())
        self.assertNotIn("Synthetic title", preview.get_content())
        self.assertIn('Task "A" entered Blocked', preview.get_content())
        self.assertEqual(self.run_worker()["sent"], 1)
        actual = FakeSMTP.instances[0].messages[0][0]
        self.assertEqual(actual["Message-ID"], preview["Message-ID"])
        self.assertIsNotNone(self.outbox()[0]["sent_at"])

    def test_failed_delivery_retries_with_backoff_and_stable_message_id(self):
        self.update(status="At risk")
        FakeSMTP.fail = True
        self.assertEqual(self.run_worker()["failed"], 1)
        first = self.outbox()[0]
        self.assertEqual(first["state"], "pending")
        self.assertEqual(first["attempts"], 1)
        self.assertEqual(first["last_error"], "SMTPAuthenticationError")
        self.assertNotIn("SECRET", json.dumps(first))
        self.assertGreater(first["next_attempt_at"], self.clock)
        self.assertEqual(self.run_worker()["failed"], 0)
        FakeSMTP.fail = False
        self.assertEqual(self.run_worker(clock=first["next_attempt_at"] + 1)["sent"], 1)
        final = self.outbox()[0]
        self.assertEqual(final["attempts"], 2)
        self.assertEqual(first["message_id"], final["message_id"])
        self.assertEqual(final["state"], "sent")

    def test_recipients_have_separate_delivery_and_retry_state(self):
        config = mail.Config.from_env(dict(self.env, TRACKER_ALERT_TO="ok@example.invalid,bad@example.invalid"))
        FakeSMTP.refused = {"bad@example.invalid"}
        self.update(status="At risk")
        result = self.run_worker(config)
        self.assertEqual((result["sent"], result["failed"]), (1, 1))
        rows = {row["recipient"]: row for row in self.outbox()}
        self.assertEqual(rows["ok@example.invalid"]["state"], "sent")
        self.assertEqual(rows["bad@example.invalid"]["state"], "pending")
        self.assertTrue(all(len(instance.messages[0][2]) == 1 for instance in FakeSMTP.instances))
        FakeSMTP.refused = set()
        self.assertEqual(self.run_worker(config, clock=self.clock + 61)["sent"], 1)
        self.assertEqual([row["attempts"] for row in self.outbox()], [1, 2])

    def test_removed_recipient_is_not_sent_queued_email(self):
        self.update(status="At risk")
        self.run_worker(preview=True)
        other = mail.Config.from_env(dict(self.env, TRACKER_ALERT_TO="different@example.invalid"))
        self.assertEqual(self.run_worker(other)["sent"], 0)
        self.assertEqual(self.outbox()[0]["state"], "cancelled")

    def test_two_workers_cannot_claim_same_unexpired_delivery(self):
        self.update(status="At risk")
        one, two = mail.connect(self.db), mail.connect(self.db)
        self.addCleanup(one.close)
        self.addCleanup(two.close)
        mail.queue_notifications(one, self.config, self.clock, 0)
        first = mail.claim(one, self.config.recipients, self.clock)
        self.assertIsNotNone(first)
        self.assertIsNone(mail.claim(two, self.config.recipients, self.clock + 1))
        recovered = mail.claim(two, self.config.recipients, self.clock + 301)
        self.assertEqual(recovered["id"], first["id"])
        self.assertNotEqual(recovered["lease_token"], first["lease_token"])

    def test_resolved_status_cancels_queued_retry(self):
        self.update(status="At risk")
        FakeSMTP.fail = True
        self.run_worker()
        self.update(status="Done")
        FakeSMTP.fail = False
        self.assertEqual(self.run_worker(clock=self.clock + 100)["sent"], 0)
        self.assertEqual(self.outbox()[0]["state"], "cancelled")

    def test_daily_digest_dedupes_unchanged_exceptions(self):
        self.update(due="2000-01-01")
        self.assertEqual(self.run_worker()["sent"], 1)
        self.assertEqual(self.outbox()[0]["kind"], "digest")
        self.assertEqual(self.run_worker(clock=self.clock + 1)["sent"], 0)
        self.assertEqual(self.run_worker(clock=self.clock + 86400)["sent"], 1)
        self.assertEqual(len(self.outbox()), 2)

    def test_stale_digest_can_be_disabled(self):
        with closing(sqlite3.connect(self.db)) as db, db:
            db.execute("UPDATE metadata SET value='2000-01-01T00:00:00Z' WHERE key='last_import_at'")
        self.assertEqual(self.run_worker(stale_hours=0)["sent"], 0)
        self.assertEqual(self.run_worker(stale_hours=24)["sent"], 1)
        self.assertIn("stale", self.outbox()[0]["body"])

    def test_empty_shared_database_does_not_send_stale_alert(self):
        with closing(sqlite3.connect(self.db)) as db, db:
            db.execute("DELETE FROM tasks")
            db.execute("DELETE FROM events")
            db.execute("DELETE FROM metadata")
        self.assertEqual(self.run_worker(stale_hours=24)["sent"], 0)

    def test_cancelled_digest_revives_when_same_exceptions_return(self):
        self.update(due="2000-01-01")
        self.run_worker(preview=True)
        original = self.outbox()[0]
        self.update(due="2000-01-02")
        self.run_worker(preview=True, clock=self.clock + 1)
        self.update(due="2000-01-01")
        result = self.run_worker(clock=self.clock + 2)
        self.assertEqual(result["sent"], 1)
        revived = self.outbox()[0]
        self.assertEqual(revived["state"], "sent")
        self.assertEqual(revived["message_id"], original["message_id"])
        self.assertEqual(self.outbox()[1]["state"], "cancelled")

    def test_removed_then_readded_recipient_receives_current_unsent_digest(self):
        self.update(due="2000-01-01")
        self.run_worker(preview=True)
        other = mail.Config.from_env(dict(self.env, TRACKER_ALERT_TO="different@example.invalid"))
        self.run_worker(other, preview=True, clock=self.clock + 1)
        self.assertEqual(self.outbox()[0]["state"], "cancelled")
        self.assertEqual(self.run_worker(clock=self.clock + 2)["sent"], 1)
        self.assertEqual(self.outbox()[0]["state"], "sent")

    def test_previously_sent_digest_is_not_replayed_when_conditions_return(self):
        self.update(due="2000-01-01")
        self.assertEqual(self.run_worker()["sent"], 1)
        self.update(due="2999-01-01")
        self.assertEqual(self.run_worker(clock=self.clock + 1)["sent"], 0)
        self.update(due="2000-01-01")
        self.assertEqual(self.run_worker(clock=self.clock + 2)["sent"], 0)
        self.assertEqual(len(self.outbox()), 1)

    def test_expired_lease_does_not_revive_superseded_same_status_event(self):
        self.update(status="At risk")
        with closing(mail.connect(self.db)) as db:
            mail.queue_notifications(db, self.config, self.clock, 0)
            leased = mail.claim(db, self.config.recipients, self.clock)
            self.update(status="Blocked")
            mail.queue_notifications(db, self.config, self.clock + 1, 0)
            self.update(status="At risk")
            mail.queue_notifications(db, self.config, self.clock + 2, 0)
        result = self.run_worker(clock=self.clock + 301)
        self.assertEqual(result["sent"], 1)
        self.assertEqual(self.outbox()[0]["id"], leased["id"])
        self.assertEqual(self.outbox()[0]["state"], "cancelled")
        self.assertEqual(self.outbox()[-1]["state"], "sent")

    def test_failed_inflight_send_cannot_resurrect_cancelled_delivery(self):
        self.update(status="At risk")
        def fail_after_resolution(*_args):
            self.update(status="Done")
            with closing(mail.connect(self.db)) as other:
                mail.queue_notifications(other, self.config, self.clock + 1, 0)
            raise smtplib.SMTPServerDisconnected("fake transport failure")
        with patch.object(mail, "smtp_send", side_effect=fail_after_resolution):
            result = self.run_worker()
        self.assertEqual(result["failed"], 1)
        self.assertEqual(self.outbox()[0]["state"], "cancelled")
        self.assertEqual(self.run_worker(clock=self.clock + 400)["sent"], 0)

    def test_digest_revival_preserves_failed_delivery_backoff(self):
        self.update(due="2000-01-01")
        FakeSMTP.fail = True
        self.run_worker()
        first = self.outbox()[0]
        self.update(due="2999-01-01")
        self.run_worker(clock=self.clock + 1)
        self.update(due="2000-01-01")
        FakeSMTP.fail = False
        self.assertEqual(self.run_worker(clock=self.clock + 2)["sent"], 0)
        self.assertEqual(self.outbox()[0]["next_attempt_at"], first["next_attempt_at"])
        self.assertEqual(self.run_worker(clock=first["next_attempt_at"] + 1)["sent"], 1)

    def test_crash_after_acceptance_retries_same_message_id_after_lease(self):
        self.update(status="At risk")
        accepted = []
        def accept_then_crash(message, *_args):
            accepted.append(message["Message-ID"])
            raise KeyboardInterrupt()
        with patch.object(mail, "smtp_send", side_effect=accept_then_crash):
            with self.assertRaises(KeyboardInterrupt):
                self.run_worker()
        self.assertEqual(self.outbox()[0]["state"], "pending")
        self.assertEqual(self.run_worker(clock=self.clock + 299)["sent"], 0)
        def accept(message, *_args):
            accepted.append(message["Message-ID"])
        with patch.object(mail, "smtp_send", side_effect=accept):
            self.assertEqual(self.run_worker(clock=self.clock + 301)["sent"], 1)
        self.assertEqual(accepted, [accepted[0], accepted[0]])
        self.assertEqual(self.outbox()[0]["attempts"], 2)

    def test_next_utc_day_replaces_unsent_previous_day_digest(self):
        from datetime import datetime, timezone
        before_midnight = datetime(2026, 10, 28, 23, 59, 59, tzinfo=timezone.utc).timestamp()
        self.update(due="2000-01-01")
        self.run_worker(preview=True, clock=before_midnight)
        self.assertEqual(self.run_worker(clock=before_midnight + 2)["sent"], 1)
        rows = self.outbox()
        self.assertEqual([row["state"] for row in rows], ["cancelled", "sent"])
        self.assertIn("2026-10-29 (UTC)", rows[1]["body"])

    def test_large_backlog_drains_in_bounded_polls_without_duplicates(self):
        tasks = [dict(task_id=f"TASK-{i:03d}", title="Synthetic", status="At risk") for i in range(120)]
        tracker.upsert(self.db, tasks, "synthetic test")
        config = mail.Config.from_env(dict(self.env, TRACKER_ALERT_TO="one@example.invalid,two@example.invalid"))
        accepted = []
        with patch.object(mail, "smtp_send", side_effect=lambda message, *_args: accepted.append(message["Message-ID"])):
            results = [self.run_worker(config, clock=self.clock + i) for i in range(3)]
        self.assertEqual([result["sent"] for result in results], [100, 100, 40])
        self.assertEqual([result["pending"] for result in results], [140, 40, 0])
        self.assertEqual(len(set(accepted)), 240)

    def test_concurrent_workers_deliver_each_pending_message_once(self):
        tasks = [dict(task_id=f"CONCURRENT-{i}", title="Synthetic", status="At risk") for i in range(8)]
        tracker.upsert(self.db, tasks, "synthetic test")
        barrier = threading.Barrier(2)
        accepted, results, errors = [], [], []
        def smtp(message, *_args):
            accepted.append(message["Message-ID"])
            time.sleep(0.002)
        def worker():
            try:
                barrier.wait(timeout=5)
                results.append(self.run_worker())
            except BaseException as error:
                errors.append(error)
        with patch.object(mail, "smtp_send", side_effect=smtp):
            workers = [threading.Thread(target=worker) for _ in range(2)]
            for worker in workers:
                worker.start()
            for worker in workers:
                worker.join(timeout=10)
        self.assertFalse(any(worker.is_alive() for worker in workers))
        self.assertFalse(errors)
        self.assertEqual(sum(result["sent"] for result in results), 8)
        self.assertEqual(len(accepted), len(set(accepted)))
        self.assertTrue(all(row["state"] == "sent" for row in self.outbox()))

    def test_corrupt_data_cli_error_does_not_print_stored_text_or_traceback(self):
        self.update(status="At risk")
        with closing(sqlite3.connect(self.db)) as db, db:
            db.execute("UPDATE metadata SET value='SECRET-MALFORMED-TIMESTAMP' WHERE key='last_import_at'")
        with patch.dict(mail.os.environ, self.env, clear=True), patch("sys.stderr") as error_output:
            code = mail.main(["--db", str(self.db), "--once"])
        printed = "".join(call.args[0] for call in error_output.write.call_args_list)
        self.assertEqual(code, 1)
        self.assertIn("import timestamp", printed)
        self.assertNotIn("SECRET", printed)
        self.assertNotIn("Traceback", printed)
        self.assertFalse(FakeSMTP.instances)

    def test_smtp_close_error_after_acceptance_is_not_retried(self):
        self.update(status="At risk")
        with patch.object(FakeSMTP, "close", side_effect=OSError("fake close failure")):
            result = self.run_worker()
        self.assertEqual((result["sent"], result["failed"]), (1, 0))
        self.assertEqual(self.outbox()[0]["state"], "sent")

    def test_malformed_stored_values_abort_without_consuming_events(self):
        cases = [
            ("UPDATE tasks SET due='2026-02-30'", "due date"),
            ("UPDATE metadata SET value='not a date' WHERE key='last_import_at'", "import timestamp"),
            ("UPDATE metadata SET value='2026-10-28T12:00:00' WHERE key='last_import_at'", "import timestamp"),
            ("UPDATE events SET changes='[]' WHERE id=(SELECT MAX(id) FROM events)", "event history"),
        ]
        for index, (sql, message) in enumerate(cases):
            with self.subTest(sql=sql):
                fresh = self.root / f"corrupt-{index}.sqlite"
                tracker.upsert(fresh, [dict(task_id="A", title="Synthetic", status="At risk")], "test")
                with closing(sqlite3.connect(fresh)) as db, db:
                    db.execute(sql)
                with self.assertRaisesRegex(tracker.TrackerError, message):
                    mail.run_once(fresh, self.config, stale_hours=24, now=self.clock)
                with closing(sqlite3.connect(fresh)) as db:
                    self.assertEqual(db.execute("SELECT value FROM notification_meta WHERE key='event_cursor'").fetchone()[0], "0")
                    self.assertEqual(db.execute("SELECT COUNT(*) FROM notification_outbox").fetchone()[0], 0)
                fresh.unlink()
        self.assertFalse(FakeSMTP.instances)

    def test_starttls_verifies_certificates_before_login(self):
        config = mail.Config.from_env(dict(self.env, TRACKER_SMTP_USERNAME="user", TRACKER_SMTP_PASSWORD="not-a-real-password"))
        self.update(status="At risk")
        self.run_worker(config)
        smtp = FakeSMTP.instances[0]
        self.assertEqual(smtp.calls, ["ehlo", "starttls", "ehlo", "login", "send", "close"])
        self.assertTrue(smtp.context.check_hostname)
        self.assertEqual(smtp.context.verify_mode, ssl.CERT_REQUIRED)
        self.assertNotIn("not-a-real-password", repr(config))

    def test_ssl_uses_verifying_context(self):
        config = mail.Config.from_env(dict(self.env, TRACKER_SMTP_SECURITY="ssl"))
        self.assertEqual(config.port, 465)
        self.update(status="At risk")
        self.run_worker(config)
        smtp = FakeSMTP.instances[0]
        self.assertNotIn("starttls", smtp.calls)
        self.assertTrue(smtp.kwargs["context"].check_hostname)
        self.assertEqual(smtp.kwargs["context"].verify_mode, ssl.CERT_REQUIRED)

    def test_invalid_config_and_header_injection_fail_closed(self):
        invalid = [
            {"TRACKER_ALERT_TO": "reviewer@example.invalid\nBcc:other@example.invalid"},
            {"TRACKER_SMTP_FROM": "tracker@example.invalid\r\n"},
            {"TRACKER_ALERT_TO": "A Person <reviewer@example.invalid>"},
            {"TRACKER_ALERT_TO": "a@example.invalid,"},
            {"TRACKER_SMTP_SECURITY": "none"},
            {"TRACKER_SMTP_SECURITY": "plain"},
            {"TRACKER_SMTP_PORT": "0"},
            {"TRACKER_SMTP_PORT": "not-a-port"},
            {"TRACKER_SMTP_HOST": "https://smtp.example.invalid"},
            {"TRACKER_SMTP_HOST": ""},
            {"TRACKER_SMTP_USERNAME": "user"},
            {"TRACKER_PUBLIC_URL": "javascript:alert(1)"},
            {"TRACKER_PUBLIC_URL": "https://user:password@example.invalid"},
            {"TRACKER_PUBLIC_URL": "https://exa mple.invalid"},
            {"TRACKER_PUBLIC_URL": "https://example.invalid\r\nBcc:x"},
        ]
        for changes in invalid:
            with self.subTest(changes=changes):
                with self.assertRaises(mail.ConfigError):
                    mail.Config.from_env(dict(self.env, **changes))
        self.assertFalse(FakeSMTP.instances)

    def test_explicit_loopback_plain_demo_and_preview_config(self):
        config = mail.Config.from_env(dict(self.env, TRACKER_SMTP_HOST="127.0.0.1", TRACKER_SMTP_SECURITY="plain", TRACKER_SMTP_PORT="1025"))
        self.assertEqual(config.security, "plain")
        preview = mail.Config.from_env({"TRACKER_ALERT_TO": "reviewer@example.invalid"}, preview=True)
        self.assertEqual(preview.sender, "tracker-preview@localhost")
        self.assertFalse(preview.host)

    def test_core_snapshots_exclude_outbox_and_smtp_config(self):
        self.update(status="Blocked")
        self.run_worker(preview=True)
        snapshot = json.dumps(tracker.snapshot(self.db))
        self.assertNotIn("reviewer@example.invalid", snapshot)
        self.assertNotIn("message_id", snapshot)
        self.assertNotIn("notification_outbox", snapshot)

    def test_cli_preview_returns_counts_without_smtp(self):
        self.update(status="Blocked")
        with patch.dict(mail.os.environ, {"TRACKER_ALERT_TO": "reviewer@example.invalid"}, clear=True):
            with patch("sys.stdout") as output:
                code = mail.main(["--db", str(self.db), "--once", "--preview-dir", str(self.preview), "--stale-hours", "0"])
        self.assertEqual(code, 0)
        self.assertFalse(FakeSMTP.instances)
        printed = "".join(call.args[0] for call in output.write.call_args_list)
        self.assertEqual(json.loads(printed)["previewed"], 1)

    def test_cli_delivery_failure_returns_one(self):
        self.update(status="Blocked")
        FakeSMTP.fail = True
        with patch.dict(mail.os.environ, self.env, clear=True):
            with patch("sys.stdout"):
                code = mail.main(["--db", str(self.db), "--once", "--stale-hours", "0"])
        self.assertEqual(code, 1)

    def test_real_smtplib_delivers_to_loopback_sink(self):
        """A real SMTP exchange, confined to an ephemeral loopback socket."""
        captured = []

        class Sink(socketserver.StreamRequestHandler):
            def handle(self):
                self.connection.settimeout(5)
                self.wfile.write(b"220 localhost Open Study Tracker test sink\r\n")
                sender, recipients = "", []
                while True:
                    command = self.rfile.readline(8192)
                    if not command:
                        return
                    verb = command.split(b" ", 1)[0].strip().upper()
                    if verb in (b"EHLO", b"HELO"):
                        self.wfile.write(b"250-localhost\r\n250 SIZE 1048576\r\n")
                    elif verb == b"MAIL":
                        sender = command.decode("ascii").strip()
                        self.wfile.write(b"250 sender accepted\r\n")
                    elif verb == b"RCPT":
                        recipients.append(command.decode("ascii").strip())
                        self.wfile.write(b"250 recipient accepted\r\n")
                    elif verb == b"DATA":
                        self.wfile.write(b"354 finish with dot\r\n")
                        lines = []
                        while True:
                            line = self.rfile.readline(65536)
                            if not line:
                                return
                            if line == b".\r\n":
                                break
                            lines.append(line[1:] if line.startswith(b"..") else line)
                        captured.append((sender, recipients, b"".join(lines)))
                        self.wfile.write(b"250 message accepted\r\n")
                    elif verb == b"QUIT":
                        self.wfile.write(b"221 bye\r\n")
                        return
                    else:
                        self.wfile.write(b"502 command not supported\r\n")

        server = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Sink)
        thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01})
        thread.start()
        try:
            config = mail.Config.from_env(dict(self.env, TRACKER_SMTP_HOST="127.0.0.1", TRACKER_SMTP_PORT=str(server.server_address[1]), TRACKER_SMTP_SECURITY="plain"))
            self.update(status="Blocked")
            with patch.object(mail.smtplib, "SMTP", REAL_SMTP):
                result = self.run_worker(config)
            self.assertEqual((result["sent"], result["failed"]), (1, 0))
            self.assertEqual(len(captured), 1)
            sender, recipients, raw = captured[0]
            self.assertIn("<tracker@example.invalid>", sender)
            self.assertEqual([entry.lower() for entry in recipients], ["rcpt to:<reviewer@example.invalid>"])
            message = BytesParser(policy=policy.default).parsebytes(raw)
            row = self.outbox()[0]
            self.assertEqual(message["Message-ID"], row["message_id"])
            self.assertEqual(message["To"], "reviewer@example.invalid")
            self.assertIn('Task "A" entered Blocked', message.get_content())
            self.assertNotIn("PRIVATE FREE TEXT", message.get_content())
            self.assertEqual(row["state"], "sent")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)
            self.assertFalse(thread.is_alive())


if __name__ == "__main__":
    unittest.main()
