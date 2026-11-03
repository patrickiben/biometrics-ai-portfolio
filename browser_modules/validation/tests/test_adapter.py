"""Scheduling, file-boundary and source-provenance checks for the browser adapter."""
import ast
import asyncio
import base64
import importlib.util
import inspect
import json
from pathlib import Path
import subprocess
import tempfile
import types
import unittest

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("browser_validation", ROOT / "browser_modules/validation/browser_validation.py")
adapter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(adapter)


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.runtime = object.__new__(adapter.ValidationRuntime)
        self.runtime.root = self.root
        self.runtime._sent = {}

    def tearDown(self):
        self.directory.cleanup()

    def test_nested_async_calls_preserve_attributes_and_results(self):
        code, functions = adapter._async_source('''
def run():
    def r(expr): return command(["Rscript", "-e", expr], "/project")
    x = r("first").stdout.strip()
    return command(["Rscript", "-e", x], "/project").returncode
''', "example.py")
        seen = []
        async def command(argv, cwd):
            seen.append((argv, cwd))
            return subprocess.CompletedProcess(argv, 7, "  second  ", "")
        scope = {"command": command}
        exec(code, scope)
        self.assertEqual(asyncio.run(scope["run"]()), 7)
        self.assertEqual(functions, ["r", "run"])
        self.assertEqual(seen[1][0][-1], "second")

    def test_canonical_transform_only_changes_scheduling(self):
        class Undo(ast.NodeTransformer):
            def visit_Await(self, node): return self.visit(node.value)
            def visit_AsyncFunctionDef(self, node):
                node = self.generic_visit(node)
                result = ast.FunctionDef(name=node.name, args=node.args, body=node.body,
                                         decorator_list=node.decorator_list, returns=node.returns,
                                         type_comment=node.type_comment)
                if hasattr(node, "type_params"): result.type_params = node.type_params
                return ast.copy_location(result, node)
        # The tested function names provide a fail-closed review signal if a
        # future native orchestration change requires a broader async adaptation.
        expected = {"native_harness.py": ["main", "r", "run", "sensitivity"],
                    "native_teeth.py": ["main", "run", "run_layers"]}
        for relative in adapter.CANONICAL_RUNNERS:
            path = ROOT / relative
            source = path.read_text()
            changed_tree, changed = adapter._async_tree(source, str(path), drop_command=path.name == "native_harness.py")
            self.assertEqual(changed, expected[path.name])
            original = ast.parse(source)
            original.body = [node for node in original.body if not adapter._main_guard(node)
                             and not (path.name == "native_harness.py" and isinstance(node, ast.FunctionDef)
                                      and node.name in {"command", "rscript_path"})]
            self.assertEqual(ast.dump(Undo().visit(changed_tree), include_attributes=False),
                             ast.dump(original, include_attributes=False))

    def test_snapshot_contains_every_R_source_but_no_document_binary(self):
        for name, data in {"root.R": b"x<-1", ".hidden/check.R": b"x<-2", "study/data.csv": b"not needed",
                           "sim_lifecycle/out/adsl.csv": b"USUBJID\nS1\n", "README.pdf": b"pdf",
                           "node_modules/ignored.R": b"ignored"}.items():
            path = self.root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
        files, deleted, hashes = self.runtime._snapshot(self.root)
        self.assertEqual({x["path"] for x in files}, {"root.R", ".hidden/check.R", "sim_lifecycle/out/adsl.csv"})
        self.assertEqual(deleted, [])
        self.runtime._sent = hashes
        (self.root / "root.R").write_text("x<-3")
        (self.root / ".hidden/check.R").unlink()
        files, deleted, _ = self.runtime._snapshot(self.root)
        self.assertEqual([x["path"] for x in files], ["root.R"])
        self.assertEqual(deleted, [".hidden/check.R"])

    def test_bytes_roundtrip_and_deletion(self):
        old = self.root / "old.csv"; old.write_bytes(b"old")
        self.runtime._sent["old.csv"] = "old-hash"
        data = bytes(range(256))
        result = self.runtime._apply_response(self.root, {"returncode": 1, "stdout": "not a success", "stderr": "error",
                            "files": [{"path": "nested/data.bin", "base64": base64.b64encode(data).decode()}], "deleted": ["old.csv"]})
        self.assertEqual((self.root / "nested/data.bin").read_bytes(), data)
        self.assertFalse(old.exists())
        self.assertEqual(result.returncode, 1)

    def test_unsafe_response_is_atomic(self):
        for bad in ["../outside.csv", "/outside.csv", "x/../outside.csv", "x\\outside.csv", "x:outside.csv"]:
            with self.subTest(path=bad):
                with self.assertRaises(ValueError):
                    self.runtime._apply_response(self.root, {"returncode": 0, "files": [
                        {"path": "valid.csv", "base64": "YQ=="}, {"path": bad, "base64": "YQ=="}]})
                self.assertFalse((self.root / "valid.csv").exists())

    def test_invalid_text_output_does_not_write_files(self):
        with self.assertRaises(ValueError):
            self.runtime._apply_response(self.root, {"returncode": 0, "stdout": {}, "files": [{"path": "valid.csv", "base64": "YQ=="}]})
        self.assertFalse((self.root / "valid.csv").exists())

    def test_duplicate_or_conflicting_files_rejected(self):
        item = {"path": "data.csv", "base64": "YQ=="}
        for files, deleted in [([item, item], []), ([item], ["data.csv"]), ([], ["data.csv", "data.csv"])]:
            with self.assertRaises(ValueError):
                self.runtime._apply_response(self.root, {"returncode": 0, "files": files, "deleted": deleted})

    def test_non_string_removal_is_rejected_before_writes(self):
        with self.assertRaises(ValueError):
            self.runtime._apply_response(self.root, {"returncode": 0, "files": [{"path": "valid.csv", "base64": "YQ=="}],
                                                      "deleted": [{"path": "old.csv"}]})
        self.assertFalse((self.root / "valid.csv").exists())

    def test_progress_retains_original_log_and_complete_lines(self):
        lines = []
        output = adapter._ProgressLog(lines.append)
        for part in ("Baseline ", "passed\nDefect 1/18: ", "D00\n", "partial"):
            output.write(part)
        self.assertEqual(lines, ["Baseline passed", "Defect 1/18: D00"])
        self.assertEqual(output.getvalue(), "Baseline passed\nDefect 1/18: D00\npartial")

    def test_symlinked_parent_rejected(self):
        (self.root / "link").symlink_to(Path(tempfile.gettempdir()), target_is_directory=True)
        with self.assertRaises(ValueError):
            self.runtime._apply_response(self.root, {"returncode": 0, "files": [{"path": "link/test.csv", "base64": "YQ=="}]})

    def test_source_hash_mismatch_refuses_execution(self):
        with self.assertRaisesRegex(ValueError, "Reviewed source changed"):
            adapter.ValidationRuntime(ROOT, lambda r: None,
                                      required_source_hashes={adapter.CANONICAL_RUNNERS[0]: "0" * 64})

    def test_complete_registry_is_frozen_and_preserved(self):
        import csv, hashlib
        path = ROOT / "validation_harness/teeth/defects.csv"
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), path.with_suffix(".sha256").read_text().split()[0])
        with path.open() as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual([row["id"] for row in rows], [f"D{i:02}" for i in range(18)])
        self.assertEqual(sum(row["class"] == "not applicable" for row in rows), 2)

    def test_manual_and_unsigned_statuses_are_not_rewritten(self):
        runtime = adapter.ValidationRuntime(ROOT, lambda r: None)
        native = (ROOT / adapter.CANONICAL_RUNNERS[0]).read_text()
        self.assertIn('"G5 Adversarial QC panel"', native)
        self.assertIn('"manual", "manual record', native)
        self.assertIn('"not signed" if jargon', native)
        self.assertTrue(inspect.iscoroutinefunction(runtime._modules["harness"].run))
        self.assertTrue(inspect.iscoroutinefunction(runtime._modules["teeth"].run))
        self.assertFalse(inspect.iscoroutinefunction(runtime._modules["teeth"].classify))


if __name__ == "__main__":
    unittest.main()
