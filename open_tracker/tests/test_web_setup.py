"""Managed browser runtime boundaries and automatic notification reconfiguration."""
from pathlib import Path
from contextlib import closing
import http.cookiejar
import http.client
import json
import os
import socket
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from urllib.request import Request, build_opener, HTTPCookieProcessor

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
try:
    from open_tracker import manage, server, web_setup
except ModuleNotFoundError as error:
    if error.name not in {"flask", "werkzeug"}:
        raise
    web_setup = None


@unittest.skipIf(web_setup is None, "Browser setup needs requirements-shared.txt")
class BrowserRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tracker web runtime ")
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name)

    def test_first_run_requires_setup_key_and_rejects_reclaim(self):
        for token in (None, "short", "x" * 32 + "\n"):
            with self.subTest(token=bool(token)), self.assertRaises(manage.SetupError):
                web_setup.create_web_app(self.workspace, "https://tracker.example.test", token, env={})
        server.manage_user(self.workspace / "tracker.sqlite", "add-user", "existing", "Synthetic long password", "admin")
        with self.assertRaises(manage.SetupError):
            web_setup.create_web_app(self.workspace, setup_token="a" * 48, env={})

    def test_hosted_setup_enforces_host_origin_and_secure_cookie(self):
        app = web_setup.create_web_app(self.workspace, "https://tracker.example.test", "a" * 48, env={})
        client = app.test_client()
        self.assertEqual(client.get("/healthz").status_code, 400)
        response = client.get("/api/session", base_url="https://tracker.example.test")
        self.assertEqual(response.status_code, 200)
        self.assertIn("Secure", response.headers["Set-Cookie"])
        data = dict(setup_token="a" * 48, username="admin", password="Synthetic password 2026", password_confirm="Synthetic password 2026", demo=False)
        headers = {"X-CSRF-Token": response.json["csrf_token"], "Origin": "https://other.test"}
        self.assertEqual(client.post("/api/setup", json=data, headers=headers, base_url="https://tracker.example.test").status_code, 403)
        headers["Origin"] = "https://tracker.example.test"
        self.assertEqual(client.post("/api/setup", json=data, headers=headers, base_url="https://tracker.example.test").status_code, 200)
        self.assertEqual(client.get("/healthz", base_url="https://tracker.example.test").json, {"status": "ok"})

    def test_existing_configuration_preserves_secret_and_rejects_host_switch(self):
        server.manage_user(self.workspace / "tracker.sqlite", "add-user", "admin", "Synthetic password 2026", "admin")
        config = manage.new_config("https://tracker.example.test")
        manage.save_config(self.workspace, config)
        app = web_setup.create_web_app(self.workspace, env={})
        self.assertEqual(app.config["SECRET_KEY"], config["secret_key"])
        self.assertIsNone(app.config["SETUP_TOKEN"])
        with self.assertRaises(manage.SetupError):
            web_setup.create_web_app(self.workspace, "https://different.example.test", env={})

    def test_local_health_identifies_only_its_desktop_instance(self):
        app = web_setup.create_web_app(self.workspace, setup_token="a" * 48, env={"TRACKER_DESKTOP_INSTANCE": "synthetic-id"})
        self.assertEqual(app.test_client().get("/healthz").json["desktop_instance"], "synthetic-id")
        self.assertEqual(app.test_client().get("/healthz", environ_overrides={"REMOTE_ADDR": "192.0.2.1"}).status_code, 403)

    def test_container_url_constraints_fail_before_listener_or_bootstrap_database(self):
        with patch.dict(os.environ, {"TRACKER_CONTAINER": "1"}):
            with self.assertRaises(manage.SetupError):
                web_setup.create_web_app(self.workspace, "https://tracker.example.test:8443", "a" * 48, env={})
        self.assertFalse((self.workspace / "tracker.sqlite").exists())
        with patch.dict(os.environ, {"TRACKER_EXPECTED_PUBLIC_URL": "https://intended.example.test"}):
            with self.assertRaises(manage.SetupError):
                web_setup.create_web_app(self.workspace, "https://different.example.test", "a" * 48, env={})
        self.assertFalse((self.workspace / "tracker.sqlite").exists())

    def test_worker_reloads_settings_without_restart_and_ignores_ambient_smtp(self):
        server.manage_user(self.workspace / "tracker.sqlite", "add-user", "admin", "Synthetic password 2026", "admin")
        config = manage.new_config()
        config["interval"] = 60
        manage.save_config(self.workspace, config)
        app = web_setup.create_web_app(self.workspace, env={})
        results = []
        first = threading.Event()
        def fake_run(path, transport, preview, stale):
            results.append((transport, preview, stale))
            first.set()
            return dict(enabled=True, queued=0, sent=0, previewed=0, failed=0, pending=0)
        with patch.dict(os.environ, {"TRACKER_SMTP_HOST": "ambient.invalid", "TRACKER_ALERT_TO": "ambient@example.test"}), patch.object(web_setup.notifications, "run_once", side_effect=fake_run):
            worker = web_setup.NotificationWorker(app)
            worker.start()
            try:
                self.assertTrue(first.wait(5))
                self.assertEqual(results[0][0].host, "")
                self.assertEqual(results[0][0].recipients, ("reviewer@example.test",))
                self.assertIsNotNone(results[0][1])
                config["email"]["mode"] = "off"
                manage.save_config(self.workspace, config)
                deadline = time.monotonic() + 5
                while worker.status["status"] != "off" and time.monotonic() < deadline:
                    time.sleep(.05)
                self.assertEqual(worker.status["status"], "off")
                config["email"]["mode"] = "preview"
                config["stale_hours"] = 24
                manage.save_config(self.workspace, config)
                deadline = time.monotonic() + 5
                while len(results) < 2 and time.monotonic() < deadline:
                    time.sleep(.05)
                self.assertEqual(len(results), 2)
                self.assertEqual(results[-1][2], 24)
            finally:
                worker.stop()
            self.assertFalse(worker.thread.is_alive())

    def check_process_setup_and_stop(self, host):
        with closing(socket.socket()) as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        env = {k: v for k, v in os.environ.items() if not k.startswith("TRACKER_") and k != "RENDER_EXTERNAL_URL"}
        env.update(TRACKER_SETUP_TOKEN="synthetic-key-" + "x" * 40, TRACKER_DESKTOP_INSTANCE="synthetic-instance", PORT="not-used-with-explicit-port")
        log = (self.workspace / "process.log").open("w+")
        process = subprocess.Popen([sys.executable, str(Path(web_setup.__file__)), "--workspace", str(self.workspace), "--port", str(port), "--host", host],
                                   stdout=log, stderr=subprocess.STDOUT, env=env)
        keepalive = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
        try:
            client = build_opener(HTTPCookieProcessor(http.cookiejar.CookieJar()))
            base = f"http://127.0.0.1:{port}"
            ready = False
            for _ in range(100):
                try:
                    with client.open(base + "/healthz", timeout=.2) as response:
                        self.assertEqual(json.load(response)["desktop_instance"], "synthetic-instance")
                    ready = True
                    break
                except OSError:
                    if process.poll() is not None:
                        break
                    time.sleep(.05)
            self.assertTrue(ready, "Web listener did not become ready")
            # Browsers retain idle HTTP connections. They must not keep the
            # process alive after the administrator clicks Close workspace.
            keepalive.request("GET", "/healthz")
            persistent = keepalive.getresponse()
            persistent.read()
            self.assertFalse(persistent.will_close)
            def post(path, data):
                with client.open(base + "/api/session") as response:
                    csrf = json.load(response)["csrf_token"]
                request = Request(base + path, json.dumps(data).encode(), {"Content-Type": "application/json", "X-CSRF-Token": csrf})
                with client.open(request) as response:
                    return json.load(response)
            password = "Synthetic process password 2026"
            self.assertTrue(post("/api/setup", dict(setup_token=env["TRACKER_SETUP_TOKEN"], username="admin", password=password, password_confirm=password, demo=True))["configured"])
            self.assertTrue(post("/api/login", dict(username="admin", password=password))["user"]["admin_ui"])
            self.assertTrue(post("/api/admin/stop", dict(confirm=True))["stopping"])
            self.assertEqual(process.wait(timeout=10), 0)
            log.seek(0)
            text = log.read()
            self.assertNotIn(password, text)
            self.assertNotIn(env["TRACKER_SETUP_TOKEN"], text)
            with socket.socket() as probe:
                self.assertNotEqual(probe.connect_ex(("127.0.0.1", port)), 0)
        finally:
            keepalive.close()
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
            log.close()

    def test_desktop_process_setup_and_click_stop_leave_no_server(self):
        self.check_process_setup_and_stop("127.0.0.1")

    def test_localhost_process_stops_every_ipv4_and_ipv6_listener(self):
        self.check_process_setup_and_stop("localhost")


if __name__ == "__main__":
    unittest.main()
