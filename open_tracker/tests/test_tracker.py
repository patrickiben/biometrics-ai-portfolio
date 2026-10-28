"""Black-box acceptance tests for the dependency-free tracker CLI.

Run from the repository root:
    python3 -m unittest discover -s open_tracker/tests -v

Every test uses a temporary database; no example or user files are changed.
"""

import csv
import io
import json
from html.parser import HTMLParser
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


MODULE = Path(__file__).resolve().parents[1]
CLI = MODULE / "tracker.py"


class EmbeddedSnapshot(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.inside = False
        self.matches = 0
        self.fragments = []

    def handle_starttag(self, tag, attrs):
        if tag == "script" and dict(attrs).get("id") == "tracker-data":
            self.inside = True
            self.matches += 1

    def handle_endtag(self, tag):
        if tag == "script":
            self.inside = False

    def handle_data(self, data):
        if self.inside:
            self.fragments.append(data)


class TrackerAcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="open-tracker-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.db = self.root / "tracker.sqlite3"
        self.counter = 0

    def run_cli(self, *args, ok=True):
        result = subprocess.run(
            [sys.executable, str(CLI), "--db", str(self.db), *map(str, args)],
            cwd=MODULE.parent,
            capture_output=True,
            text=True,
            timeout=15,
        )
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stderr + result.stdout)
        return result

    def write_text(self, text, suffix):
        self.counter += 1
        path = self.root / f"input-{self.counter}{suffix}"
        path.write_text(text, encoding="utf-8")
        return path

    def import_json(self, rows, *, ok=True, extra=None, dry_run=False):
        payload = {"schema_version": 1, "rows": rows}
        if extra:
            payload.update(extra)
        path = self.write_text(json.dumps(payload), ".json")
        args = ["upsert", "--json", path, "--actor", "acceptance-test"]
        if dry_run:
            args.append("--dry-run")
        return self.run_cli(*args, ok=ok)

    def import_csv(self, headers, rows, *, ok=True):
        output = io.StringIO(newline="")
        writer = csv.writer(output)
        writer.writerow(headers)
        writer.writerows(rows)
        return self.run_cli("upsert", "--csv", self.write_text(output.getvalue(), ".csv"), ok=ok)

    def snapshot(self):
        self.counter += 1
        path = self.root / f"snapshot-{self.counter}.json"
        self.run_cli("export", "--json", path)
        return json.loads(path.read_text(encoding="utf-8"))

    def seed(self, **overrides):
        row = {
            "task_id": "007",
            "title": "Review deliverables",
            "status": "In progress",
            "owner": "Synthetic owner",
            "due": "2099-12-31",
            "progress": 40,
            "notes": "Synthetic operational example",
        }
        row.update(overrides)
        self.import_json([row])
        return row

    def test_new_csv_row_uses_defaults_and_preserves_text_key(self):
        self.import_csv(["task_id", "title"], [["007", "Review deliverables"]])
        snapshot = self.snapshot()
        self.assertEqual(snapshot["schema_version"], 1)
        self.assertTrue(snapshot["last_import_at"])
        self.assertTrue(snapshot["exported_at"])
        self.assertEqual(len(snapshot["rows"]), 1)
        row = snapshot["rows"][0]
        self.assertEqual(row["task_id"], "007")
        self.assertEqual(row["status"], "Not started")
        self.assertEqual(row["progress"], 0)
        self.assertEqual((row["owner"], row["due"], row["notes"]), ("", "", ""))
        self.assertTrue(row["updated_at"])

    def test_csv_blanks_and_omitted_fields_leave_existing_values(self):
        original = self.seed()
        self.import_csv(["task_id", "owner", "due", "progress", "notes"], [["007", "", "", "", ""]])
        current = self.snapshot()["rows"][0]
        for name, value in original.items():
            self.assertEqual(current[name], value, name)

    def test_json_empty_strings_explicitly_clear_optional_text(self):
        self.seed()
        self.import_json([{"task_id": "007", "owner": "", "due": "", "notes": ""}])
        row = self.snapshot()["rows"][0]
        self.assertEqual((row["owner"], row["due"], row["notes"]), ("", "", ""))
        self.assertEqual(row["title"], "Review deliverables")
        self.assertEqual(row["progress"], 40)

    def test_successful_update_has_before_after_history(self):
        self.seed()
        before = self.snapshot()
        self.import_json([{"task_id": "007", "progress": 75}])
        after = self.snapshot()
        self.assertEqual(len(after["events"]), len(before["events"]) + 1)
        event = max(after["events"], key=lambda item: item["id"])
        self.assertEqual(event["task_id"], "007")
        self.assertEqual(event["actor"], "acceptance-test")
        self.assertEqual(event["changes"]["progress"], {"before": 40, "after": 75})
        self.assertTrue(event["changed_at"])

    def test_identical_reimport_adds_neither_rows_nor_history(self):
        row = self.seed()
        before = self.snapshot()
        self.import_json([row])
        after = self.snapshot()
        self.assertEqual(after["rows"], before["rows"])
        self.assertEqual(after["events"], before["events"])
        self.assertTrue(after["last_import_at"])
        self.assertGreaterEqual(after["last_import_at"], before["last_import_at"])

    def test_invalid_later_row_rolls_back_earlier_update(self):
        self.seed()
        before = self.snapshot()
        result = self.import_json([
            {"task_id": "007", "progress": 99},
            # A title-less patch is valid for an existing key, but not this new
            # key. This error occurs during the transaction, after row 007.
            {"task_id": "NEW", "progress": 50},
        ], ok=False)
        self.assertTrue(result.stderr.strip())
        after = self.snapshot()
        for field in ("rows", "events", "last_import_at"):
            self.assertEqual(after[field], before[field], field)

    def test_batch_duplicate_keys_rejected_without_writes(self):
        self.seed()
        before = self.snapshot()
        self.import_json([
            {"task_id": "007", "progress": 60},
            {"task_id": "007", "progress": 70},
        ], ok=False)
        after = self.snapshot()
        self.assertEqual(after["rows"], before["rows"])
        self.assertEqual(after["events"], before["events"])

    def test_unknown_json_field_is_rejected(self):
        self.import_json([{"task_id": "A", "title": "Review", "participant_id": "example"}], ok=False)

    def test_unknown_and_duplicate_csv_headers_are_rejected(self):
        for headers, values in (
            (["task_id", "title", "participant_id"], ["A", "Review", "example"]),
            (["task_id", "title", "title"], ["A", "Review", "Overwritten"]),
            (["title"], ["No key"]),
        ):
            with self.subTest(headers=headers):
                self.import_csv(headers, [values], ok=False)

    def test_empty_imports_are_rejected(self):
        for content in ("", "task_id,title\n"):
            with self.subTest(content=content):
                self.run_cli("upsert", "--csv", self.write_text(content, ".csv"), ok=False)
        self.import_json([], ok=False)

    def test_json_requires_supported_snapshot_schema(self):
        for payload in (
            {"rows": [{"task_id": "A", "title": "Review"}]},
            {"schema_version": 2, "rows": [{"task_id": "A", "title": "Review"}]},
            [{"task_id": "A", "title": "Review"}],
        ):
            with self.subTest(payload=payload):
                path = self.write_text(json.dumps(payload), ".json")
                self.run_cli("upsert", "--json", path, ok=False)

    def test_duplicate_json_properties_are_rejected(self):
        content = ('{"schema_version":1,"rows":['
                   '{"task_id":"A","title":"Review","progress":20,"progress":90}]}')
        path = self.write_text(content, ".json")
        self.run_cli("upsert", "--json", path, ok=False)
        self.assertFalse(self.db.exists())

    def test_malformed_csv_record_cannot_partially_update(self):
        self.seed()
        before = self.snapshot()
        path = self.write_text("task_id,progress\n007,90\nNEW,20,extra\n", ".csv")
        self.run_cli("upsert", "--csv", path, ok=False)
        after = self.snapshot()
        for field in ("rows", "events", "last_import_at"):
            self.assertEqual(after[field], before[field], field)

    def test_invalid_values_are_rejected_without_changing_state(self):
        self.seed()
        before = self.snapshot()
        invalid = [
            {"title": ""},
            {"title": "t" * 161},
            {"owner": "o" * 121},
            {"notes": "n" * 1001},
            {"owner": None},
            {"status": "Complete"},
            {"status": ""},
            {"due": "2026-02-30"},
            {"due": "2026-1-01"},
            {"due": "10/28/2026"},
            {"progress": -1},
            {"progress": 101},
            {"progress": 1.5},
            {"progress": True},
            {"progress": None},
            {"task_id": ""},
            {"task_id": "k" * 81},
        ]
        for changes in invalid:
            with self.subTest(changes=changes):
                self.import_json([{"task_id": "007", **changes}], ok=False)
        after = self.snapshot()
        for field in ("rows", "events", "last_import_at"):
            self.assertEqual(after[field], before[field], field)

    def test_csv_integer_progress_and_quoted_multiline_values(self):
        title = 'Review, "quality"'
        notes = "Line one\nLine two — synthetic only"
        self.import_csv(["task_id", "title", "progress", "notes"], [["A", title, "75", notes]])
        row = self.snapshot()["rows"][0]
        self.assertEqual(row["progress"], 75)
        self.assertEqual(row["title"], title)
        self.assertEqual(row["notes"], notes)

    def test_new_key_requires_title_but_update_does_not(self):
        self.import_json([{"task_id": "A", "progress": 20}], ok=False)
        self.seed()
        self.import_json([{"task_id": "007", "progress": 20}])
        self.assertEqual(self.snapshot()["rows"][0]["progress"], 20)

    def test_dry_run_does_not_create_database(self):
        self.import_json([{"task_id": "A", "title": "Dry run"}], dry_run=True)
        self.assertFalse(self.db.exists())
        self.assertFalse(list(self.root.glob("tracker.sqlite3*")))

    def test_dry_run_does_not_modify_existing_database(self):
        self.seed()
        before = self.snapshot()
        db_bytes = self.db.read_bytes()
        self.import_json([{"task_id": "007", "progress": 100}], dry_run=True)
        self.assertEqual(self.db.read_bytes(), db_bytes)
        after = self.snapshot()
        for field in ("rows", "events", "last_import_at"):
            self.assertEqual(after[field], before[field], field)

    def test_dry_run_still_validates(self):
        self.import_json([{"task_id": "A", "title": "Dry run", "progress": 101}], dry_run=True, ok=False)
        self.assertFalse(self.db.exists())

    def test_imported_snapshot_cannot_forge_history_or_timestamps(self):
        self.import_json([
            {"task_id": "A", "title": "Review", "updated_at": "1900-01-01T00:00:00Z"}
        ], extra={
            "exported_at": "1900-01-01T00:00:00Z",
            "last_import_at": "1900-01-01T00:00:00Z",
            "events": [{"id": 999, "task_id": "forged", "actor": "forged"}],
        })
        snapshot = self.snapshot()
        self.assertNotEqual(snapshot["rows"][0]["updated_at"], "1900-01-01T00:00:00Z")
        self.assertNotEqual(snapshot["last_import_at"], "1900-01-01T00:00:00Z")
        self.assertEqual(len(snapshot["events"]), 1)
        self.assertEqual(snapshot["events"][0]["task_id"], "A")
        self.assertEqual(snapshot["events"][0]["actor"], "acceptance-test")

    def test_exported_json_can_be_reimported_without_changes(self):
        self.seed()
        before = self.snapshot()
        path = self.write_text(json.dumps(before), ".json")
        self.run_cli("upsert", "--json", path)
        after = self.snapshot()
        self.assertEqual(after["rows"], before["rows"])
        self.assertEqual(after["events"], before["events"])

    def test_exported_html_safely_embeds_untrusted_text(self):
        payload = '</script><script id="injected">alert("test")</script>&\u2028\u2029'
        self.seed(notes=payload)
        path = self.root / "snapshot.html"
        self.run_cli("export", "--html", path)
        html = path.read_text(encoding="utf-8")
        self.assertNotIn(payload, html)
        self.assertNotIn('<script id="injected">', html)
        parser = EmbeddedSnapshot()
        parser.feed(html)
        self.assertEqual(parser.matches, 1)
        snapshot = json.loads("".join(parser.fragments))
        self.assertEqual(snapshot["rows"][0]["notes"], payload)

    def test_check_reports_current_exceptions(self):
        self.seed()
        self.run_cli("check")
        for status in ("At risk", "Blocked"):
            with self.subTest(status=status):
                self.import_json([{"task_id": "007", "status": status}])
                result = self.run_cli("check", ok=False)
                self.assertIn("007", result.stdout + result.stderr)

    def test_overdue_done_row_is_not_an_exception(self):
        self.seed(status="In progress", due="2000-01-01")
        self.run_cli("check", ok=False)
        self.import_json([{"task_id": "007", "status": "Done", "progress": 100}])
        self.run_cli("check")

    def test_stale_check_has_distinct_attention_exit_code(self):
        self.seed()
        healthy = self.run_cli("check", "--stale-hours", "24")
        self.assertEqual(healthy.returncode, 0)
        stale = self.run_cli("check", "--stale-hours", "0", ok=False)
        self.assertEqual(stale.returncode, 2)
        self.assertIn("stale", (stale.stdout + stale.stderr).lower())

    def test_read_commands_do_not_create_missing_database(self):
        self.run_cli("export", "--json", self.root / "missing.json", ok=False)
        self.assertFalse(self.db.exists())
        self.run_cli("check", ok=False)
        self.assertFalse(self.db.exists())

    def test_export_cannot_overwrite_database(self):
        self.seed()
        before = self.db.read_bytes()
        for output_type in ("--json", "--html"):
            with self.subTest(output_type=output_type):
                self.run_cli("export", output_type, self.db, ok=False)
                self.assertEqual(self.db.read_bytes(), before)
        self.assertEqual(self.snapshot()["rows"][0]["task_id"], "007")


if __name__ == "__main__":
    unittest.main()
