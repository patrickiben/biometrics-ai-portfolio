"""Real setup-launcher boundaries: local HTTP, process cleanup, and mail isolation.

All account/task data are temporary. SMTP endpoints are loopback sinks; these
checks cannot contact a real recipient or mutate a hosted tracker.
"""

from contextlib import closing
from http.cookiejar import CookieJar
import json
import os
from pathlib import Path
import socket
import socketserver
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPCookieProcessor, Request, build_opener, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import manage
import notifications
import server
import tracker


class ConnectionSink(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self):
        self.connections = 0
        super().__init__(("127.0.0.1", 0), ConnectionHandler)


class ConnectionHandler(socketserver.BaseRequestHandler):
    def handle(self):
        self.server.connections += 1


class SMTPSink(socketserver.StreamRequestHandler):
    def handle(self):
        self.connection.settimeout(5)
        self.wfile.write(b"220 localhost setup test sink\r\n")
        recipients = []
        while True:
            command = self.rfile.readline(8192)
            if not command:
                return
            verb = command.split(b" ", 1)[0].strip().upper()
            if verb in (b"EHLO", b"HELO"):
                self.wfile.write(b"250 localhost\r\n")
            elif verb == b"MAIL":
                self.wfile.write(b"250 OK\r\n")
            elif verb == b"RCPT":
                recipients.append(command.decode().strip())
                self.wfile.write(b"250 OK\r\n")
            elif verb == b"DATA":
                self.wfile.write(b"354 End with dot\r\n")
                lines = []
                while True:
                    line = self.rfile.readline(65536)
                    if not line:
                        return
                    if line == b".\r\n":
                        break
                    lines.append(line)
                self.server.messages.append((recipients, b"".join(lines)))
                self.wfile.write(b"250 Accepted\r\n")
            elif verb == b"QUIT":
                self.wfile.write(b"221 Bye\r\n")
                return
            else:
                self.wfile.write(b"502 Unsupported\r\n")


def free_port():
    with closing(socket.socket()) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class SetupProcessTests(unittest.TestCase):
    """Exercise the public command, not a substituted application factory."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tracker setup integration ")
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name) / "private workspace"
        self.workspace.mkdir(mode=0o700)
        self.db = self.workspace / "tracker.sqlite"
        self.password = "Synthetic integration password 2026"
        server.manage_user(self.db, "add-user", "reviewer", self.password, "admin")
        self.config = {
            "version": 1,
            "secret_key": "synthetic-signing-key-" + "x" * 48,
            "public_url": "",
            "email": {"mode": "preview", "recipients": "reviewer@example.test",
                      "host": "", "port": 587, "security": "starttls", "sender": "",
                      "username": "", "password": ""},
            "stale_hours": 0,
            "interval": 1,
        }
        manage.save_config(self.workspace, self.config)
        self.processes = []
        self.addCleanup(self.stop_all)
        self.cookie_jar = CookieJar()
        self.client = build_opener(HTTPCookieProcessor(self.cookie_jar))
        self.port = free_port()
        self.base = f"http://127.0.0.1:{self.port}"

    def command(self, *args):
        return [sys.executable, str(Path(manage.__file__).resolve()),
                "--workspace", str(self.workspace), *args]

    def process(self, *args, env=None):
        log = open(self.workspace / f"process-{len(self.processes)}.log", "w+")
        self.addCleanup(log.close)
        proc = subprocess.Popen(self.command(*args), stdin=subprocess.DEVNULL,
                                stdout=log, stderr=subprocess.STDOUT,
                                env=dict(os.environ, **(env or {})))
        self.processes.append((proc, log))
        return proc, log

    def start(self, *, env=None, host="127.0.0.1"):
        proc, log = self.process("start", "--host", host, "--port", str(self.port), env=env)
        deadline = time.monotonic() + 25
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                log.seek(0)
                self.fail("Launcher exited before serving: " + log.read())
            try:
                probe = Request(self.base + "/api/session", headers={"Host": urlsplit(self.config["public_url"]).netloc} if self.config["public_url"] else {})
                with urlopen(probe, timeout=.4) as response:
                    if response.status == 200:
                        return proc
            except (OSError, URLError):
                time.sleep(.1)
        self.fail("Launcher did not bind the local HTTP port within 25 seconds")

    def stop(self, proc):
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=8)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
                self.fail("Launcher did not cleanly handle termination")

    def stop_all(self):
        for proc, _log in self.processes:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=5)

    def request(self, path, data=None, csrf=None):
        headers = {"Origin": self.base}
        if data is not None:
            headers["Content-Type"] = "application/json"
        if csrf:
            headers["X-CSRF-Token"] = csrf
        req = Request(self.base + path,
                      data=None if data is None else json.dumps(data).encode(), headers=headers)
        try:
            with self.client.open(req, timeout=5) as response:
                return response.status, json.load(response)
        except HTTPError as error:
            return error.code, json.load(error)

    def login(self):
        _status, session = self.request("/api/session")
        code, result = self.request("/api/login", {"username": "reviewer", "password": self.password},
                                    session["csrf_token"])
        self.assertEqual(code, 200)
        return result["csrf_token"]

    def create_task(self, csrf):
        row = dict(task_id="SYNTHETIC-001", title="Synthetic setup check", owner="Example role",
                   status="Blocked", due="2099-12-31", progress=10, notes="Synthetic private note")
        code, result = self.request("/api/tasks", {"row": row, "expected_updated_at": None}, csrf)
        self.assertEqual(code, 200, result)
        return result

    def sink(self):
        sink = ConnectionSink()
        thread = threading.Thread(target=sink.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(sink.server_close)
        self.addCleanup(sink.shutdown)
        return sink

    def test_restart_retains_account_task_secret_and_session(self):
        proc = self.start()
        self.create_task(self.login())
        first_config = (self.workspace / "config.json").read_bytes()
        self.stop(proc)
        proc = self.start()
        self.assertEqual(self.request("/api/session")[1]["user"]["username"], "reviewer")
        code, snap = self.request("/api/snapshot")
        self.assertEqual(code, 200)
        self.assertEqual(snap["rows"][0]["task_id"], "SYNTHETIC-001")
        self.assertEqual((self.workspace / "config.json").read_bytes(), first_config)
        self.stop(proc)
        with closing(socket.socket()) as sock:
            self.assertNotEqual(sock.connect_ex(("127.0.0.1", self.port)), 0)

    def test_preview_worker_runs_automatically_without_smtp(self):
        sink = self.sink()
        self.config["email"].update(host="127.0.0.1", port=sink.server_address[1])
        manage.save_config(self.workspace, self.config)
        proc = self.start()
        self.create_task(self.login())
        deadline = time.monotonic() + 8
        files = []
        while time.monotonic() < deadline and not files:
            files = list((self.workspace / "mail-preview").glob("*.eml"))
            time.sleep(.1)
        self.assertTrue(files, "Automatic worker did not create a local email preview")
        content = files[0].read_text()
        self.assertIn("SYNTHETIC-001", content)
        self.assertNotIn("Synthetic private note", content)
        self.assertEqual(sink.connections, 0, "Preview mode contacted SMTP")
        self.stop(proc)

    def test_off_mode_ignores_ambient_email_and_server_environment(self):
        sink = self.sink()
        self.config["email"]["mode"] = "off"
        manage.save_config(self.workspace, self.config)
        env = {"TRACKER_ALERT_TO": "someone@example.test", "TRACKER_SMTP_HOST": "127.0.0.1",
               "TRACKER_SMTP_PORT": str(sink.server_address[1]), "TRACKER_SMTP_SECURITY": "plain",
               "TRACKER_SMTP_FROM": "sender@example.test", "TRACKER_INSECURE_LOCAL": "0",
               "TRACKER_ALLOWED_HOSTS": "wrong.example.test", "TRACKER_SECRET_KEY": "wrong"}
        proc = self.start(env=env)
        self.create_task(self.login())
        time.sleep(1.4)
        self.assertEqual(sink.connections, 0)
        self.assertFalse(list((self.workspace / "mail-preview").glob("*.eml")))
        self.stop(proc)

    def test_occupied_port_fails_without_starting_background_worker(self):
        with closing(socket.socket()) as sock:
            sock.bind(("127.0.0.1", self.port))
            sock.listen()
            proc, log = self.process("start", "--port", str(self.port))
            code = proc.wait(timeout=12)
            self.assertNotEqual(code, 0)
            log.seek(0)
            output = log.read()
            self.assertIn("port", output.lower())
            self.assertNotIn(self.config["secret_key"], output)
            self.assertFalse(list((self.workspace / "mail-preview").glob("*.eml")))

    def test_local_mode_rejects_nonloopback_listener(self):
        result = subprocess.run(self.command("start", "--host", "0.0.0.0", "--port", str(self.port)),
                                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=12)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("loopback", (result.stdout + result.stderr).lower())

    def test_email_test_defaults_to_preview_even_when_smtp_is_configured(self):
        sink = self.sink()
        self.config["email"].update(mode="smtp", host="127.0.0.1", port=sink.server_address[1],
                                    security="plain", sender="sender@example.test")
        manage.save_config(self.workspace, self.config)
        result = subprocess.run(self.command("email-test"), capture_output=True, text=True, timeout=12)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(sink.connections, 0)
        self.assertEqual(len(list((self.workspace / "mail-preview").glob("*.eml"))), 1)
        denied = subprocess.run(self.command("email-test", "--send"), capture_output=True, text=True, timeout=12)
        self.assertNotEqual(denied.returncode, 0)
        self.assertEqual(sink.connections, 0)

    def test_explicit_email_test_targets_one_address_without_flushing_alert_queue(self):
        sink = socketserver.ThreadingTCPServer(("127.0.0.1", 0), SMTPSink)
        sink.daemon_threads = True
        sink.messages = []
        threading.Thread(target=sink.serve_forever, daemon=True).start()
        self.addCleanup(sink.server_close)
        self.addCleanup(sink.shutdown)
        self.config["email"].update(mode="smtp", host="127.0.0.1", port=sink.server_address[1],
                                    security="plain", sender="sender@example.test")
        manage.save_config(self.workspace, self.config)
        tracker.upsert(self.db, [dict(task_id="DO-NOT-EMAIL", title="Private synthetic row", status="Blocked")], "test")
        with closing(notifications.connect(self.db)) as db:
            notifications.queue_notifications(db, notifications.Config.from_env(manage.email_environment(self.config)), time.time(), stale_hours=0)
            before = db.execute("SELECT state,attempts FROM notification_outbox").fetchall()
            self.assertEqual([tuple(x) for x in before], [("pending", 0)])
        result = subprocess.run(self.command("email-test", "--send", "--to", "test-only@example.test"),
                                capture_output=True, text=True, timeout=12)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(sink.messages), 1)
        recipients, message = sink.messages[0]
        self.assertEqual([x.lower() for x in recipients], ["rcpt to:<test-only@example.test>"])
        self.assertNotIn(b"DO-NOT-EMAIL", message)
        self.assertNotIn(b"Private synthetic row", message)
        with closing(sqlite3.connect(self.db)) as db:
            self.assertEqual(db.execute("SELECT state,attempts FROM notification_outbox").fetchall(), [("pending", 0)])

    def test_team_mode_works_through_preserved_host_with_secure_origin(self):
        self.config["public_url"] = "https://tracker.example.test"
        self.config["email"]["mode"] = "off"
        manage.save_config(self.workspace, self.config)
        proc = self.start(host="0.0.0.0")
        headers = {"Host": "tracker.example.test"}
        with urlopen(Request(self.base + "/api/session", headers=headers), timeout=5) as response:
            cookie = response.headers["Set-Cookie"]
            csrf = json.load(response)["csrf_token"]
        self.assertIn("Secure", cookie)
        self.assertIn("HttpOnly", cookie)
        headers.update({"Cookie": cookie.split(";", 1)[0], "Origin": self.config["public_url"],
                        "Content-Type": "application/json", "X-CSRF-Token": csrf})
        data = json.dumps({"username": "reviewer", "password": self.password}).encode()
        with urlopen(Request(self.base + "/api/login", data=data, headers=headers), timeout=5) as response:
            self.assertEqual(json.load(response)["user"]["username"], "reviewer")
        # A direct HTTP upstream is intentional; the real proxy terminates TLS.
        # Untrusted forwarded headers never relax origin/Host validation.
        headers.update({"Origin": "https://elsewhere.example.test", "X-Forwarded-Host": "elsewhere.example.test"})
        with self.assertRaises(HTTPError) as bad_origin:
            urlopen(Request(self.base + "/api/login", data=data, headers=headers), timeout=5)
        self.assertEqual(bad_origin.exception.code, 403)
        bad_origin.exception.close()
        with self.assertRaises(HTTPError) as bad_host:
            urlopen(self.base + "/api/session", timeout=5)
        self.assertEqual(bad_host.exception.code, 400)
        bad_host.exception.close()
        self.stop(proc)

    def test_doctor_reports_configuration_without_disclosing_credentials(self):
        self.config["email"].update(mode="smtp", host="smtp.example.test", sender="sender@example.test",
                                    username="SYNTHETIC-SMTP-USERNAME", password="SYNTHETIC-SMTP-PASSWORD")
        manage.save_config(self.workspace, self.config)
        result = subprocess.run(self.command("doctor"), stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, timeout=12)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output = result.stdout + result.stderr
        for secret in (self.config["secret_key"], self.config["email"]["username"], self.config["email"]["password"]):
            self.assertNotIn(secret, output)
        self.assertIn("smtp", output.lower())


if __name__ == "__main__":
    unittest.main()
