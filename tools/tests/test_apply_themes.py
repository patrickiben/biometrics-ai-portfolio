"""Regression coverage for standalone theme injection around embedded JavaScript."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("apply_themes", ROOT / "apply_themes.py")
themes = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(themes)


class ThemeGenerationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ("assets/theme/tokens.css", "assets/legacy-theme.css", "assets/legacy-theme.js"):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("/* theme fixture */", encoding="utf-8")

    def generate(self, source):
        (self.root / "guide.html").write_text(source, encoding="utf-8")
        with patch.object(themes.subprocess, "check_output", return_value=b"guide.html\0"):
            return themes.theme_updates(self.root)

    def test_embedded_head_literal_stays_inside_script(self):
        script = '<script>const closing = "</head>"; const button = \'<button class="theme-toggle">\';</script>'
        source = "<!doctype html><html><head>\n" + script + "\n</head><body>Guide</body></html>"
        result = self.generate(source)["guide.html"]
        self.assertIn(script, result)
        self.assertGreater(result.index("<!-- toolkit-theme:start -->"), result.index("</script>"))
        self.assertEqual(result.count("<!-- toolkit-theme:start -->"), 1)

    def test_injection_is_idempotent_and_managed_pages_remain_reported(self):
        source = "<html><head><title>Guide</title></head><body>Guide</body></html>"
        first = self.generate(source)["guide.html"]
        self.assertEqual(self.generate(first), {"guide.html": first})

    def test_existing_real_control_is_preserved(self):
        source = '<html><head></head><body><button class="theme-toggle">Theme</button></body></html>'
        self.assertEqual(self.generate(source), {})

    def test_html_fragments_are_untouched(self):
        self.assertEqual(self.generate("<section>Example</section>"), {})


if __name__ == "__main__":
    unittest.main()
