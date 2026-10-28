import base64
import http.client
import json
from pathlib import Path
import shutil
import tempfile
import threading
import time
import unittest
from urllib.parse import urlencode
from unittest.mock import patch

from toolkit_launcher import runtime, server
from toolkit_launcher.tests.helpers import make_source, wait_for_job


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="toolkit API spaces ")
        self.folder = Path(self.temp.name)
        self.source = make_source(self.folder / "download")
        self.workspace = runtime.Workspace(self.folder / "private", self.source)
        self.httpd = server.create_server(self.workspace, token="test-token-" + "x" * 40)
        self.worker = threading.Thread(target=self.httpd.serve_forever, kwargs={"poll_interval": .02}, daemon=True)
        self.worker.start()
        status, data, _ = self.request("POST", "/api/projects", {"name": "API project"})
        self.assertEqual(status, 200)
        self.ident = data["id"]
        self.root = self.workspace.project(self.ident)

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.worker.join(2)
        self.workspace.close()
        self.temp.cleanup()

    def request(self, method, path, data=None, headers=None, token=True, raw=None):
        body = raw if raw is not None else json.dumps(data).encode() if data is not None else None
        request_headers = {"X-Toolkit-Token": self.httpd.token} if token else {}
        if body is not None:
            request_headers["Content-Type"] = "application/json"
        request_headers.update(headers or {})
        connection = http.client.HTTPConnection("127.0.0.1", self.httpd.server_port, timeout=10)
        try:
            connection.request(method, path, body=body, headers=request_headers)
            response = connection.getresponse()
            content = response.read()
            values = dict(response.getheaders())
            if "application/json" in response.getheader("Content-Type", ""):
                content = json.loads(content)
            return response.status, content, values
        finally:
            connection.close()

    def test_host_origin_token_and_browser_security_headers(self):
        self.assertEqual(self.request("GET", "/api/state", token=False)[0], 403)
        self.assertEqual(self.request("GET", "/api/state", headers={"X-Toolkit-Token": "wrong"})[0], 403)
        self.assertEqual(self.request("GET", "/api/state", headers={"Host": "attacker.invalid"})[0], 403)
        self.assertEqual(self.request("GET", "/api/state", headers={"Origin": "https://attacker.invalid"})[0], 403)
        origin = f"http://127.0.0.1:{self.httpd.server_port}"
        status, data, headers = self.request("GET", "/api/state", headers={"Origin": origin})
        self.assertEqual(status, 200)
        self.assertIn("sandbox.run", data["actions"])
        self.assertIn("interpretation", data["configuration"])
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(headers["X-Frame-Options"], "DENY")
        status, content, headers = self.request("GET", "/", token=False)
        self.assertEqual(status, 200)
        self.assertNotIn(self.httpd.token.encode(), content)
        self.assertIn("frame-ancestors 'none'", headers["Content-Security-Policy"])

    def test_malformed_requests_are_400_without_mutation(self):
        initial = len(self.workspace.projects())
        cases = [("/api/projects", b'[]'), ("/api/projects", b'null'), ("/api/projects", b'{"name":"a","name":"b"}'),
                 ("/api/projects", b'{"name":"a","unknown":1}'), ("/api/projects", b'{"name":NaN}'),
                 ("/api/actions", json.dumps({"project_id": self.ident, "action_id": [], "options": {}}).encode()),
                 ("/api/actions", json.dumps({"project_id": self.ident, "action_id": "sandbox.run", "options": []}).encode()),
                 ("/api/configure", json.dumps({"project_id": self.ident, "module_id": [], "values": {}}).encode()),
                 ("/api/configure", json.dumps({"project_id": self.ident, "module_id": "interpretation", "values": []}).encode())]
        for path, body in cases:
            with self.subTest(path=path, body=body):
                self.assertEqual(self.request("POST", path, raw=body)[0], 400)
        self.assertEqual(len(self.workspace.projects()), initial)
        self.assertFalse(self.workspace.jobs)
        self.assertEqual(self.request("POST", "/api/projects", raw=b'{}', headers={"Content-Type": "text/plain"})[0], 400)
        self.assertEqual(self.request("POST", "/api/projects", raw=b'{}', headers={"Content-Length": str(runtime.MAX_FILE * 2)})[0], 400)

    def test_no_command_or_implicit_install_execution_is_exposed(self):
        actions = [("echo unsafe", {}), ("sandbox.run", {"command": "echo unsafe"}), ("shiny.risk.install", {}),
                   ("study.install", {"allow_install": "true"}), ("shiny.risk.run", {"port": 9000})]
        with patch("subprocess.Popen", side_effect=AssertionError("No process should be started")):
            for action, options in actions:
                with self.subTest(action=action):
                    status, _, _ = self.request("POST", "/api/actions", {"project_id": self.ident, "action_id": action, "options": options})
                    self.assertEqual(status, 400)
        self.assertFalse(self.workspace.jobs)

    def test_file_traversal_symlink_upload_and_download(self):
        for path in ["../project.json", "/etc/passwd", "C:/private.txt", "..\\secret"]:
            query = urlencode({"project_id": self.ident, "path": path})
            self.assertEqual(self.request("GET", "/api/files?" + query)[0], 400)
        (self.root / "leak").symlink_to(self.source, target_is_directory=True)
        query = urlencode({"project_id": self.ident, "path": "leak/private-not-in-manifest.txt"})
        self.assertEqual(self.request("GET", "/api/files?" + query)[0], 400)
        relative = "risk_monitor/shiny/data/signals.csv"
        original = (self.root / relative).read_bytes()
        payload = {"project_id": self.ident, "path": relative, "content_base64": base64.b64encode(original).decode()}
        self.assertEqual(self.request("POST", "/api/files", payload)[0], 200)
        self.assertEqual(self.request("POST", "/api/files", dict(payload, path="launch_app.R"))[0], 400)
        query = urlencode({"project_id": self.ident, "path": relative})
        status, content, headers = self.request("GET", "/api/files?" + query)
        self.assertEqual(status, 200)
        self.assertEqual(content, original)
        self.assertIn("attachment", headers["Content-Disposition"])
        self.assertEqual(self.request("GET", "/api/files?" + query + "&path=x")[0], 400)

    def test_configuration_roundtrip_and_remote_model_endpoint_rejection(self):
        body = {"project_id": self.ident, "module_id": "interpretation", "values": {"model": "reviewed-local:1", "seed": 88}}
        with patch("subprocess.Popen", side_effect=AssertionError("No model should run")):
            status, content, _ = self.request("POST", "/api/configure", body)
            self.assertEqual(status, 200, content)
            query = urlencode({"project_id": self.ident, "module_id": "interpretation"})
            status, content, _ = self.request("GET", "/api/configure?" + query)
            self.assertEqual(status, 200)
            self.assertEqual(content["values"]["model"], "reviewed-local:1")
            self.assertEqual(content["values"]["seed"], 88)
            self.assertNotIn("values", content["values"])
            status, _, _ = self.request("POST", "/api/configure", dict(body, values={"endpoint": "http://external.example.com"}))
            self.assertEqual(status, 400)

    @unittest.skipUnless(shutil.which("Rscript"), "Rscript not installed")
    def test_real_base_r_job_through_api_produces_downloadable_outputs(self):
        status, started, _ = self.request("POST", "/api/actions", {"project_id": self.ident, "action_id": "sandbox.run", "options": {}})
        self.assertEqual(status, 200, started)
        status, _, _ = self.request("POST", "/api/actions", {"project_id": self.ident, "action_id": "sandbox.run", "options": {}})
        self.assertEqual(status, 400)
        status, _, _ = self.request("POST", "/api/configure", {"project_id": self.ident, "module_id": "interpretation", "values": {}})
        self.assertEqual(status, 400)
        done = wait_for_job(self.workspace, started["id"], timeout=60)
        self.assertEqual(done["status"], "succeeded", done["log"])
        status, job, _ = self.request("GET", "/api/jobs/" + started["id"])
        self.assertEqual(status, 200)
        self.assertIn("STUB", job["log"])
        self.assertIn("numeric-consistency: PASS", job["log"])
        self.assertEqual(len(job["outputs"]), 9)
        path = "sim_lifecycle/out/results_summary.csv"
        status, content, _ = self.request("GET", "/api/files?" + urlencode({"project_id": self.ident, "path": path}))
        self.assertEqual(status, 200)
        self.assertIn(b"N_PARTICIPANTS", content)
        self.assertFalse((self.source / "sim_lifecycle/out/results_summary.csv").exists())


if __name__ == "__main__":
    unittest.main()
