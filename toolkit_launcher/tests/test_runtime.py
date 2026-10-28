import base64
from contextlib import contextmanager
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import zipfile

from toolkit_launcher import desktop, jobs, runtime
from toolkit_launcher.tests.helpers import make_source, wait_for_job


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="toolkit runtime ")
        self.folder = Path(self.temp.name)
        self.source = make_source(self.folder / "download")
        self.workspace = runtime.Workspace(self.folder / "private", source=self.source)
        self.created = self.workspace.create_project("My independent project")
        self.ident = self.created["id"]
        self.root = self.workspace.project(self.ident)

    def tearDown(self):
        self.workspace.close()
        self.temp.cleanup()

    def plan(self, code, outputs=None):
        return {"commands": [{"argv": [sys.executable, "-c", code], "cwd": str(self.root), "env": {}}],
                "outputs": outputs or [], "long_running": False}

    def descendant_plan(self, parent_exits=False):
        child = """import os,signal,time
from pathlib import Path
signal.signal(signal.SIGTERM,signal.SIG_IGN)
Path('descendant.pid').write_text(str(os.getpid()))
while True:
 with Path('heartbeat').open('a') as out:out.write('alive\\n')
 time.sleep(.02)
"""
        parent = ("import subprocess,sys,time\nfrom pathlib import Path\n"
                  "subprocess.Popen([sys.executable,'-c'," + repr(child) + "])\n"
                  "while not Path('heartbeat').exists():time.sleep(.01)\n"
                  "print('descendant ready',flush=True)\n" + ("" if parent_exits else "time.sleep(60)\n"))
        return self.plan(parent)

    def await_heartbeat(self):
        deadline = time.monotonic() + 10
        while not (self.root / 'heartbeat').exists():
            if time.monotonic() >= deadline:
                self.fail('The descendant fixture did not start.')
            time.sleep(.02)

    def cleanup_descendant(self):
        file = self.root / 'descendant.pid'
        if file.exists():
            try:
                os.kill(int(file.read_text()), signal.SIGTERM if os.name == 'nt' else signal.SIGKILL)
            except OSError:
                pass

    def test_stop_reclaims_descendant_after_leader_exits(self):
        # On POSIX the leader exits on TERM while this child deliberately ignores
        # TERM. Windows must likewise reclaim the whole owned Job Object.
        with patch.object(jobs, 'build_plan', return_value=self.descendant_plan()), patch.object(runtime, 'PROCESS_STOP_GRACE', .15):
            record = self.workspace.start(self.ident, 'sandbox.run', {})
            try:
                self.await_heartbeat()
                self.workspace.stop_job(record['id'])
                self.assertEqual(wait_for_job(self.workspace, record['id'])['status'], 'stopped')
                size = (self.root / 'heartbeat').stat().st_size
                time.sleep(.2)
                self.assertEqual((self.root / 'heartbeat').stat().st_size, size, 'Stopped task left a live descendant.')
            finally:
                self.cleanup_descendant()

    def test_normal_exit_reclaims_descendant_before_next_command(self):
        plan = self.descendant_plan(parent_exits=True)
        next_command = self.plan("from pathlib import Path;import time;p=Path('heartbeat');n=p.stat().st_size;time.sleep(.2);assert p.stat().st_size==n,'previous command still running';Path('next-command-ok').write_text('done')")['commands'][0]
        plan['commands'].append(next_command)
        with patch.object(jobs, 'build_plan', return_value=plan), patch.object(runtime, 'PROCESS_STOP_GRACE', .15):
            record = self.workspace.start(self.ident, 'sandbox.run', {})
            try:
                done = wait_for_job(self.workspace, record['id'])
                self.assertEqual(done['status'], 'succeeded', done['log'])
                self.assertTrue((self.root / 'next-command-ok').is_file())
                size = (self.root / 'heartbeat').stat().st_size
                time.sleep(.2)
                self.assertEqual((self.root / 'heartbeat').stat().st_size, size)
            finally:
                self.cleanup_descendant()

    @unittest.skipUnless(os.name == 'nt', 'Windows Job Object assignment')
    def test_windows_assignment_failure_never_starts_requested_command(self):
        marker = self.root / 'must-not-run'
        with (self.root / 'wrapper.log').open('w') as log, patch.object(runtime, 'assign_windows_job', side_effect=OSError('fixture failure')):
            with self.assertRaises(runtime.InputError):
                runtime.spawn_owned_process([sys.executable, '-c', "from pathlib import Path;Path('must-not-run').write_text('bad')"], str(self.root), dict(os.environ), log)
        time.sleep(.1)
        self.assertFalse(marker.exists())

    def test_job_logs_use_utf8_even_with_a_competing_console_encoding(self):
        message = "QC \u2713 \u2013 \u0394"
        plan = self.plan("print(" + repr(message) + ")")
        with patch.dict(os.environ, {'PYTHONIOENCODING': 'ascii', 'PYTHONUTF8': '0'}), patch.object(jobs, 'build_plan', return_value=plan):
            record = self.workspace.start(self.ident, 'sandbox.run', {})
            done = wait_for_job(self.workspace, record['id'])
        self.assertEqual(done['status'], 'succeeded', done['log'])
        self.assertIn(message, done['log'])

    def test_cleanup_failure_is_persisted_instead_of_leaving_job_running(self):
        plan = self.plan("print('command finished')")
        with patch.object(jobs, 'build_plan', return_value=plan), patch.object(runtime.Workspace, '_terminate', side_effect=runtime.InputError('cleanup fixture')):
            record = self.workspace.start(self.ident, 'sandbox.run', {})
            done = wait_for_job(self.workspace, record['id'])
        self.assertEqual(done['status'], 'failed')
        self.assertIn('could not finish stopping', done['error'])
        saved = json.loads((self.workspace.job_dir / (record['id'] + '.json')).read_text())
        self.assertEqual(saved['status'], 'failed')

    def test_only_manifest_files_are_copied_and_private_state_is_rejected(self):
        self.assertFalse((self.root / "private-not-in-manifest.txt").exists())
        self.assertFalse((self.root / ".git").exists())
        csv = self.root / "risk_monitor/shiny/data/signals.csv"
        self.assertEqual(csv.read_bytes(), (self.source / csv.relative_to(self.root)).read_bytes())
        if os.name != "nt":
            self.assertEqual(csv.stat().st_mode & 0o777, 0o600)
        inventory = self.source / "toolkit_launcher/source_manifest.json"
        original = json.loads(inventory.read_text())
        for name in ["../outside.txt", ".git/config", "data.sqlite", "launcher-settings.json", "toolkit_configuration/private.json"]:
            target = self.source / name
            target.parent.mkdir(exist_ok=True, parents=True)
            target.write_text("PRIVATE")
            inventory.write_text(json.dumps({"schema": 1, "files": [name]}))
            with self.subTest(name=name), self.assertRaises(runtime.InputError):
                self.workspace.create_project("Should fail")
        inventory.write_text(json.dumps(original))

    def test_path_and_symlink_boundaries(self):
        for name in ["../private.txt", "/etc/passwd", "C:/secret", "risk_monitor\\secret", "x\x00y"]:
            with self.subTest(name=name), self.assertRaises(runtime.InputError):
                runtime.safe_path(self.root, name, exists=False)
        (self.root / "leak").symlink_to(self.source, target_is_directory=True)
        with self.assertRaises(runtime.InputError):
            runtime.safe_path(self.root, "leak/private-not-in-manifest.txt")
        (self.root / "link.txt").symlink_to(self.source / "private-not-in-manifest.txt")
        archive = self.workspace.export_project(self.ident)
        try:
            with zipfile.ZipFile(archive) as content:
                self.assertNotIn("link.txt", content.namelist())
                self.assertFalse(any(name.startswith("leak/") for name in content.namelist()))
        finally:
            archive.unlink()

    def test_upload_validation_backup_and_original_header_contract(self):
        relative = "risk_monitor/shiny/data/signals.csv"
        original = (self.root / relative).read_bytes()
        text = original.decode()
        rows = text.splitlines()
        with_extra = "\n".join(row + (",extra" if i == 0 else ",optional") for i, row in enumerate(rows)) + "\n"
        result = self.workspace.upload(self.ident, relative, base64.b64encode(with_extra.encode()).decode())
        self.assertEqual((self.root.parent / "input-backups" / result["backup"]).read_bytes(), original)
        self.workspace.upload(self.ident, relative, base64.b64encode(original).decode())
        self.assertEqual((self.root / relative).read_bytes(), original)
        for payload in ["bad,headers\nx,y\n", rows[0] + "\nwrong,row\n", "\x00bad"]:
            with self.assertRaises(runtime.InputError):
                self.workspace.upload(self.ident, relative, base64.b64encode(payload.encode()).decode())
        with self.assertRaises(runtime.InputError):
            self.workspace.upload(self.ident, "launch_app.R", base64.b64encode(b"arbitrary code").decode())

    def test_active_job_locks_inputs_duplicate_start_and_stop(self):
        plan = self.plan("import time;print('running',flush=True);time.sleep(60)")
        with patch.object(jobs, "build_plan", return_value=plan):
            record = self.workspace.start(self.ident, "sandbox.run", {})
            with self.assertRaises(runtime.InputError):
                self.workspace.start(self.ident, "sandbox.run", {})
            relative = "risk_monitor/shiny/data/signals.csv"
            with self.assertRaises(runtime.InputError):
                self.workspace.upload(self.ident, relative, base64.b64encode((self.root / relative).read_bytes()).decode())
            with self.assertRaises(runtime.InputError):
                self.workspace.export_project(self.ident)
            self.workspace.stop_job(record["id"])
            self.assertEqual(wait_for_job(self.workspace, record["id"])["status"], "stopped")
        self.assertEqual(self.workspace.stop_job(record["id"])["stopping"], False)

    def test_outputs_logs_and_bounded_history_survive_reopening(self):
        plan = self.plan("from pathlib import Path;Path('results').mkdir();Path('results/result.csv').write_text('n\\n40\\n');print('finished')", ["results"])
        with patch.object(jobs, "build_plan", return_value=plan):
            record = self.workspace.start(self.ident, "sandbox.run", {})
        done = wait_for_job(self.workspace, record["id"])
        self.assertEqual(done["status"], "succeeded")
        self.assertEqual(done["outputs"][0]["path"], "results/result.csv")
        reopened = runtime.Workspace(self.workspace.base, source=self.source)
        try:
            restored = reopened.job_state(record["id"])
            self.assertEqual(restored["outputs"], done["outputs"])
            self.assertIn("finished", restored["log"])
        finally:
            reopened.close()
        for n in range(105):
            ident = f"{n:032x}"
            data = dict(done, id=ident, status="running", outputs=[])
            runtime.atomic_json(self.workspace.job_dir / (ident + ".json"), data)
        with patch.object(runtime.Workspace, "_terminate", side_effect=AssertionError("Never kill a saved PID")):
            reopened = runtime.Workspace(self.workspace.base, source=self.source)
            try:
                self.assertEqual(len(reopened.jobs), 100)
                self.assertTrue(all(j["status"] == "failed" for j in reopened.jobs.values()))
                self.assertTrue(all("run the action again" in j["error"] for j in reopened.jobs.values()))
            finally:
                reopened.close()

    def test_export_blocks_mutation_until_snapshot_is_finished(self):
        entered, release, upload_done = threading.Event(), threading.Event(), threading.Event()
        original_write = zipfile.ZipFile.write
        result = []
        def slow_write(archive, *args, **kwargs):
            entered.set()
            self.assertTrue(release.wait(5))
            return original_write(archive, *args, **kwargs)
        def export():
            result.append(self.workspace.export_project(self.ident))
        def upload():
            path = "risk_monitor/shiny/data/signals.csv"
            self.workspace.upload(self.ident, path, base64.b64encode((self.root / path).read_bytes()).decode())
            upload_done.set()
        with patch.object(zipfile.ZipFile, "write", slow_write):
            worker = threading.Thread(target=export)
            worker.start()
            self.assertTrue(entered.wait(5))
            writer = threading.Thread(target=upload)
            writer.start()
            self.assertFalse(upload_done.wait(.1))
            release.set()
            worker.join(5); writer.join(5)
        self.assertTrue(upload_done.is_set())
        result[0].unlink()

    def test_desktop_lock_covers_job_and_server_cleanup(self):
        holding = {"lock": False}
        @contextmanager
        def lock(_base):
            holding["lock"] = True
            try:
                yield True
            finally:
                holding["lock"] = False
        class FakeWorkspace:
            def __init__(self, _base): pass
            def close(inner): self.assertTrue(holding["lock"])
        class FakeServer:
            server_port = 8101
            def serve_forever(inner, **_kwargs): pass
            def server_close(inner): self.assertTrue(holding["lock"])
        with patch.object(desktop, "launcher_lock", lock), patch.object(desktop, "Workspace", FakeWorkspace), patch.object(desktop, "create_server", return_value=FakeServer()):
            self.assertEqual(desktop.main(["--workspace", str(self.folder / "desktop"), "--no-browser", "--port", "8101"]), 0)
        self.assertFalse(holding["lock"])
        self.assertFalse((self.folder / "desktop/.launcher-session.json").exists())


if __name__ == "__main__":
    unittest.main()
