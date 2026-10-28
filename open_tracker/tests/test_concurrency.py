"""Shared edits must reject stale versions and preserve the import heartbeat."""

from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import sys
import tempfile
import threading
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import tracker


class SharedStorageTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.db = Path(self.directory.name) / "tracker.sqlite"

    def test_stale_edit_cannot_overwrite_newer_change(self):
        tracker.upsert(self.db, [{"task_id": "A", "title": "Review"}], "producer")
        before = tracker.snapshot(self.db)
        version = before["rows"][0]["updated_at"]
        tracker.upsert(self.db, [{"task_id": "A", "status": "In progress"}], "editor-one",
                       expected_versions={"A": version}, refresh_heartbeat=False)
        with self.assertRaises(tracker.TrackerConflict):
            tracker.upsert(self.db, [{"task_id": "A", "status": "Done"}], "editor-two",
                           expected_versions={"A": version}, refresh_heartbeat=False)
        after = tracker.snapshot(self.db)
        self.assertEqual(after["rows"][0]["status"], "In progress")
        self.assertEqual(after["last_import_at"], before["last_import_at"])
        self.assertEqual(len(after["events"]), 2)
        self.assertEqual(after["events"][-1]["actor"], "editor-one")

    def test_creation_collision_is_a_conflict(self):
        tracker.upsert(self.db, [{"task_id": "007", "title": "Review"}], "one",
                       expected_versions={"007": None}, refresh_heartbeat=False)
        with self.assertRaises(tracker.TrackerConflict):
            tracker.upsert(self.db, [{"task_id": "007", "title": "Another"}], "two",
                           expected_versions={"007": None}, refresh_heartbeat=False)
        self.assertIsNone(tracker.snapshot(self.db)["last_import_at"])

    def test_simultaneous_initial_imports_are_serialized(self):
        barrier = threading.Barrier(2)

        def write(identifier):
            barrier.wait()
            return tracker.upsert(self.db, [{"task_id": identifier, "title": identifier}], "worker")

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(write, ("A", "B")))
        self.assertEqual([result["created"] for result in results], [1, 1])
        self.assertEqual([row["task_id"] for row in tracker.snapshot(self.db)["rows"]], ["A", "B"])

    def test_failed_first_import_can_be_retried_as_dry_run(self):
        with self.assertRaises(tracker.TrackerError):
            tracker.upsert(self.db, [{"task_id": "A"}], "producer")
        before = self.db.read_bytes()
        result = tracker.upsert(self.db, [{"task_id": "A", "title": "Review"}], "producer", dry_run=True)
        self.assertEqual(result["created"], 1)
        self.assertEqual(self.db.read_bytes(), before)
        result = tracker.upsert(self.db, [{"task_id": "A", "title": "Review"}], "producer")
        self.assertEqual(result["created"], 1)


if __name__ == "__main__":
    unittest.main()
