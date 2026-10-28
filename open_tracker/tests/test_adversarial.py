"""Regressions from the independent October 2026 QC pass."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import tracker


class AdversarialStorageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.db = self.directory / "data.sqlite"

    def test_frozen_or_backward_clock_cannot_reuse_row_version(self):
        fixed = "2026-10-28T12:00:00.000000Z"
        with patch.object(tracker, "now", return_value=fixed):
            tracker.upsert(self.db, [dict(task_id="A", title="Task")], "job")
            version = tracker.snapshot(self.db)["rows"][0]["updated_at"]
            tracker.upsert(self.db, [dict(task_id="A", progress=10)], "one",
                           expected_versions={"A": version})
            newer = tracker.snapshot(self.db)["rows"][0]["updated_at"]
            self.assertGreater(newer, version)
            with self.assertRaises(tracker.TrackerConflict):
                tracker.upsert(self.db, [dict(task_id="A", progress=99)], "stale",
                               expected_versions={"A": version})
        with patch.object(tracker, "now", return_value="2025-01-01T00:00:00Z"):
            tracker.upsert(self.db, [dict(task_id="A", progress=20)], "two",
                           expected_versions={"A": newer})
        data = tracker.snapshot(self.db)
        self.assertEqual(data["rows"][0]["progress"], 20)
        self.assertGreater(data["rows"][0]["updated_at"], newer)
        self.assertEqual(len(data["events"]), 3)

    def test_export_cannot_replace_sqlite_recovery_files(self):
        tracker.upsert(self.db, [dict(task_id="A", title="Task")], "job")
        for suffix in ("-wal", "-shm", "-journal"):
            with self.subTest(suffix=suffix):
                target = Path(str(self.db) + suffix)
                # Exercise protection without fabricating real recovery state.
                with self.assertRaises(tracker.TrackerError):
                    tracker.atomic_write(target, "overwrite", self.db)
                self.assertFalse(target.exists())

    def test_export_cannot_overwrite_shared_server_worker_or_manager(self):
        for filename in ("server.py", "notifications.py", "manage.py", "admin.py", "web_setup.py", "desktop.py", "admin.html", "SETUP.html"):
            target = Path(tracker.__file__).with_name(filename)
            before = target.read_bytes()
            with self.assertRaises(tracker.TrackerError):
                tracker.atomic_write(target, "overwrite", self.db)
            self.assertEqual(target.read_bytes(), before)

    def test_nested_json_is_rejected_as_input_error(self):
        path = self.directory / "nested.json"
        path.write_text('[' * 2000 + '0' + ']' * 2000)
        with self.assertRaises(tracker.TrackerError):
            tracker.read_input(path, "json")

    def test_import_byte_and_row_limits_are_enforced(self):
        path = self.directory / "large.json"
        path.write_bytes(b" " * (tracker.MAX_BYTES + 1))
        with self.assertRaises(tracker.TrackerError):
            tracker.read_input(path, "json")
        path = self.directory / "many.csv"
        path.write_text("task_id,title\n" + "\n".join(f"{i},Task" for i in range(tracker.MAX_ROWS + 1)))
        with self.assertRaises(tracker.TrackerError):
            tracker.read_input(path, "csv")

    def test_invalid_actor_is_rejected_before_storage(self):
        for actor in (None, 123, "\ud800", "\n", ""):
            with self.subTest(actor=repr(actor)), self.assertRaises(tracker.TrackerError):
                tracker.upsert(self.db, [dict(task_id="A", title="Task")], actor)
        self.assertFalse(self.db.exists())


if __name__ == "__main__":
    unittest.main()
