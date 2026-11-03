"""Browser entry-point boundaries and preservation of incomplete evidence."""
import asyncio
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from browser_modules.validation import browser_session as session


class FakeRuntime:
    last_log = "Baseline failed: a required automatic gate did not pass.\n"

    async def harness(self):
        raise ValueError("Baseline gate failed")

    async def teeth(self, only=""):
        return {"partial": bool(only), "requested": only}

    def export_files(self):
        return [{"path": "validation.log", "base64": "bG9n"}]


class SessionTests(unittest.TestCase):
    def test_failed_run_preserves_downloadable_evidence(self):
        with patch.object(session, "_runtime", FakeRuntime()):
            result = asyncio.run(session.call("validation-harness", {}))
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "Baseline gate failed")
        self.assertIn("Baseline failed", result["last_log"])
        self.assertEqual(result["files"][0]["path"], "validation.log")
        self.assertNotIn("ledger", result)

    def test_only_frozen_registry_selection_is_accepted(self):
        with patch.object(session, "_runtime", FakeRuntime()):
            result = asyncio.run(session.call("validation-teeth", {"only": "D00,D04"}))
            self.assertTrue(result["summary"]["partial"])
            for operation, payload in (("validation-teeth", {"source": "x"}),
                                       ("validation-harness", {"only": "D00"}),
                                       ("validation-harness", {"files": []})):
                with self.assertRaises(ValueError):
                    asyncio.run(session.call(operation, payload))


if __name__ == "__main__":
    unittest.main()
