"""Execute the reviewed ten-gate harness and frozen defect registry in a browser.

The canonical Python sources remain the implementation. An AST adaptation makes
their fixed command calls awaitable; R commands cross a webR bridge and the three
fixed Python checks run inside Pyodide. No subprocess, model service, arbitrary
uploaded code, human signature or substituted statistical check is introduced.
"""
from __future__ import annotations

import ast
import base64
from contextlib import contextmanager, redirect_stderr, redirect_stdout
import hashlib
import inspect
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import runpy
import shutil
import subprocess
import sys
import tempfile
import types


ADAPTER_PATH = "browser_modules/validation/browser_validation.py"
CANONICAL_RUNNERS = ("toolkit_launcher/native_harness.py", "toolkit_launcher/native_teeth.py")
PYTHON_CHECKS = frozenset(("validation_harness/checks/g2_geo.py",
                         "validation_harness/teeth/apply_defect.py", "package_qc.py"))
ESSENTIAL_PATHS = CANONICAL_RUNNERS + (
    "toolkit_launcher/stub_profile.R", "validation_harness/run_harness.sh",
    "validation_harness/checks/conformance.R", "validation_harness/checks/independent_recompute.R",
    "validation_harness/checks/g2_geo.py", "validation_harness/teeth/apply_defect.py",
    "validation_harness/teeth/defects.csv", "validation_harness/teeth/defects.sha256",
    "validation_harness/teeth/run_teeth.sh", "validation_harness/index.html", "package_qc.py",
    "sim_lifecycle/run_lifecycle.R", "sim_lifecycle/simulate_adam.R", "sim_lifecycle/priors.R",
    "sasr_monitoring_wiki/trialmon_tests/testthat/helper-trialmon.R",
    "sasr_monitoring_wiki/trialmon_tests/testthat/test-boundaries.R",
    "sasr_monitoring_wiki/trialmon_tests/testthat/test-hyslaw-grid.R",
    "sasr_monitoring_wiki/trialmon_tests/testthat/test-logic.R",
    "sasr_monitoring_wiki/trialmon_tests/testthat/test-server.R", "uat_irt/tests/test-logic.R",
)
SKIP_DIRS = frozenset((".git", "node_modules", ".quarto", "__pycache__"))
MAX_TRANSFER_BYTES = 128 * 1024 * 1024
MAX_FILES = 12000
R_DATA_DIRECTORIES = ("sim_lifecycle/", "tlf_interpret/", "sasr_monitoring_wiki/trialmon_shiny/",
                      "sasr_monitoring_wiki/trialmon_tests/", "uat_irt/", "apps/", "assets/theme/",
                      "browser_modules/shared/")
R_DATA_EXTENSIONS = frozenset((".csv", ".json", ".txt", ".yaml", ".yml", ".rds", ".rdata", ".js", ".css", ".html"))


def source_requirements():
    """Build-time declaration; use the same complete public inventory as Pages.

    G1 parses every supplied R source and G8 checks links throughout the supplied
    package. Essential files alone are deliberately insufficient as a bundle.
    """
    return {"scope": "complete reviewed public toolkit snapshot",
            "essential_paths": list(ESSENTIAL_PATHS) + [ADAPTER_PATH, "browser_modules/validation/browser_session.py"],
            "required_directories": ["r_tlf_pseudocode", "sas_tlf_pseudocode", "tlf_interpret",
                                     "sim_lifecycle", "sasr_monitoring_wiki", "uat_irt", "assets"],
            "r_packages": ["testthat", "shiny", "bslib", "DT", "ggplot2", "jsonlite"],
            "python_packages": [],
            "limits": ["Native SAS is not executed.", "G5 is manual and G7 remains unsigned.",
                       "PDF text extraction is unavailable in the browser package scanner.",
                       "Self-test of the reviewed toolkit; not certification of uploaded project code."]}


def _relative(value):
    if not isinstance(value, str) or not value or "\\" in value or ":" in value:
        raise ValueError("Expected a safe relative file path.")
    path = PurePosixPath(value)
    if path.is_absolute() or any(p in ("", ".", "..") for p in value.split("/")):
        raise ValueError("Expected a safe relative file path.")
    return path.as_posix()


def _file(root, relative):
    relative = _relative(relative)
    path = root / relative
    current = root
    for component in PurePosixPath(relative).parts:
        current /= component
        if current.is_symlink():
            raise ValueError("Browser validation refuses symlinked files or directories.")
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError("File leaves the current browser project.")
    return path


def _walk(root):
    for directory, dirs, names in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for name in dirs + names:
            if (Path(directory) / name).is_symlink():
                raise ValueError("Browser validation refuses symlinked project content.")
        for name in sorted(names):
            yield Path(directory) / name


def validate_source_manifest(root, reviewed_paths):
    """Check the public inventory passed by the build, without invoking git."""
    root = Path(root).resolve()
    paths = [_relative(x) for x in reviewed_paths]
    if len(paths) != len(set(paths)):
        raise ValueError("The reviewed source inventory contains duplicate files.")
    missing = set(ESSENTIAL_PATHS) - set(paths)
    if missing:
        raise ValueError("Incomplete validation source snapshot: " + ", ".join(sorted(missing)))
    result = {}
    for name in paths:
        path = _file(root, name)
        if not path.is_file():
            raise ValueError("Missing reviewed file: " + name)
        result[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def _main_guard(node):
    return (isinstance(node, ast.If) and isinstance(node.test, ast.Compare)
            and isinstance(node.test.left, ast.Name) and node.test.left.id == "__name__"
            and any(isinstance(x, ast.Constant) and x.value == "__main__" for x in node.test.comparators))


def _async_tree(source, filename, *, drop_command=False):
    """Only alter call scheduling, retaining canonical expressions and bodies."""
    tree = ast.parse(source, filename=filename)
    tree.body = [node for node in tree.body if not _main_guard(node)
                 and not (drop_command and isinstance(node, ast.FunctionDef)
                          and node.name in {"command", "rscript_path"})]
    functions = [node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)]
    async_names = {"command"}
    while True:
        previous = set(async_names)
        for function in functions:
            if any(isinstance(call, ast.Call) and isinstance(call.func, ast.Name)
                   and call.func.id in async_names for call in ast.walk(function)):
                async_names.add(function.name)
        if previous == async_names:
            break

    class AsyncCalls(ast.NodeTransformer):
        def visit_FunctionDef(self, node):
            node = self.generic_visit(node)
            if node.name in async_names:
                updated = ast.AsyncFunctionDef(name=node.name, args=node.args, body=node.body,
                                               decorator_list=node.decorator_list, returns=node.returns,
                                               type_comment=node.type_comment)
                if hasattr(node, "type_params"):
                    updated.type_params = node.type_params
                return ast.copy_location(updated, node)
            return node

        def visit_Call(self, node):
            node = self.generic_visit(node)
            if isinstance(node.func, ast.Name) and node.func.id in async_names:
                return ast.copy_location(ast.Await(value=node), node)
            return node

    tree = ast.fix_missing_locations(AsyncCalls().visit(tree))
    return tree, sorted(async_names - {"command"})


def _async_source(source, filename, *, drop_command=False):
    tree, functions = _async_tree(source, filename, drop_command=drop_command)
    return compile(tree, filename, "exec"), functions


@contextmanager
def _working_directory(path):
    previous = Path.cwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(previous)


class _ProgressLog(io.StringIO):
    """Keep complete canonical output while forwarding completed status lines."""
    def __init__(self, callback=None):
        super().__init__()
        self.callback, self.pending = callback, ""

    def write(self, value):
        count = super().write(value)
        self.pending += value
        while "\n" in self.pending:
            line, self.pending = self.pending.split("\n", 1)
            if self.callback and line.strip():
                self.callback(line)
        return count


class ValidationRuntime:
    """One sequential harness/defect run, backed by an async browser R bridge.

    run_r_command receives {argv,cwd,root,files,deleted,profile,release_root}.
    Each file has safe relative path and base64 bytes. It returns a matching
    {returncode,stdout,stderr,files,deleted} object. A root switch sends a complete
    snapshot and releases the previous webR project copy; later calls send deltas.
    The bridge must emulate a fresh Rscript process, commandArgs and quit/status,
    and load the supplied deterministic profile before executing source.
    """
    def __init__(self, root, run_r_command, *, required_source_hashes=None, runner_files=(), work_parent=None, progress=None):
        self.root = Path(root).resolve()
        if not callable(run_r_command):
            raise TypeError("An async R command bridge is required.")
        self.run_r_command = run_r_command
        if progress is not None and not callable(progress):
            raise TypeError("The optional progress callback must be callable.")
        self.progress = progress
        self.work_parent = Path(work_parent or (Path(tempfile.gettempdir()) / "browser-validation")).resolve()
        if self.work_parent == self.root or self.work_parent.is_relative_to(self.root):
            raise ValueError("Mutation copies must be outside the reviewed project.")
        self.runner_files = tuple(dict.fromkeys((ADAPTER_PATH,) + tuple(_relative(p) for p in runner_files)))
        self.required_source_hashes = dict(required_source_hashes or {})
        for name in ESSENTIAL_PATHS + self.runner_files:
            if not _file(self.root, name).is_file():
                raise ValueError("The reviewed source snapshot is missing " + name)
        for name, expected in self.required_source_hashes.items():
            if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
                raise ValueError("Invalid reviewed source hash for " + str(name))
            if hashlib.sha256(_file(self.root, name).read_bytes()).hexdigest() != expected:
                raise ValueError("Reviewed source changed: " + name)
        self.last_log = ""
        self._artifacts = {}
        self._active_root = None
        self._sent = {}
        self._busy = False
        self._modules = {}
        self._load_modules()

    def _load_modules(self):
        harness = types.ModuleType("native_harness")
        harness.__file__ = str(self.root / CANONICAL_RUNNERS[0])
        code, transformed = _async_source(Path(harness.__file__).read_text(encoding="utf-8"), harness.__file__, drop_command=True)
        harness.__dict__.update(command=self._command, rscript_path=lambda: "Rscript")
        exec(code, harness.__dict__)
        self.transformed_functions = {"native_harness": transformed}
        original_sensitivity = harness.sensitivity

        async def sensitivity(root):
            status, evidence = await original_sensitivity(root)
            try:
                summary = json.loads((root / "validation_harness/teeth/results/summary.json").read_text(encoding="utf-8"))
            except (OSError, ValueError):
                summary = {}
            absent = set(self.runner_files) - set(summary.get("gate_scripts", {}))
            if absent:
                return "stale", "stale: the recorded run did not fingerprint the browser adapter/bridge (" + ", ".join(sorted(absent)) + "). " + evidence
            return status, evidence

        harness.sensitivity = sensitivity
        previous = sys.modules.get("native_harness")
        sys.modules["native_harness"] = harness
        try:
            teeth = types.ModuleType("browser_native_teeth")
            teeth.__file__ = str(self.root / CANONICAL_RUNNERS[1])
            code, transformed = _async_source(Path(teeth.__file__).read_text(encoding="utf-8"), teeth.__file__)
            exec(code, teeth.__dict__)
            self.transformed_functions["native_teeth"] = transformed
        finally:
            if previous is None:
                sys.modules.pop("native_harness", None)
            else:
                sys.modules["native_harness"] = previous
        teeth.GATE_SCRIPTS = tuple(dict.fromkeys(teeth.GATE_SCRIPTS + self.runner_files))
        self._modules = {"harness": harness, "teeth": teeth}

    def _project_root(self, cwd):
        cwd = Path(cwd).resolve()
        for candidate in (cwd,) + tuple(cwd.parents):
            if (candidate / "validation_harness/run_harness.sh").is_file():
                if candidate == self.root or candidate.is_relative_to(self.work_parent):
                    return candidate
                break
        raise ValueError("R command is outside this reviewed validation project.")

    def _snapshot(self, root):
        changed, hashes, total = [], {}, 0
        for path in _walk(root):
            relative = path.relative_to(root).as_posix()
            # G1 must see every .R source. The R computations additionally need
            # these original data/app inputs; PDFs, videos and Office artifacts
            # belong to the unchanged Python package scanner, not the R worker.
            if not (path.suffix == ".R" or (relative.startswith(R_DATA_DIRECTORIES)
                    and path.suffix.lower() in R_DATA_EXTENSIONS)):
                continue
            data = path.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            hashes[relative] = digest
            if len(hashes) > MAX_FILES:
                raise ValueError("The validation snapshot exceeds the browser file limit.")
            if digest != self._sent.get(relative):
                total += len(data)
                if total > MAX_TRANSFER_BYTES:
                    raise ValueError("The validation snapshot exceeds the browser transfer limit.")
                changed.append({"path": relative, "base64": base64.b64encode(data).decode("ascii")})
        deleted = sorted(set(self._sent) - set(hashes))
        return changed, deleted, hashes

    def _apply_response(self, root, response):
        if not isinstance(response, dict) or type(response.get("returncode")) is not int:
            raise ValueError("The R bridge returned an invalid status.")
        changed, deleted = response.get("files", []), response.get("deleted", [])
        if not isinstance(changed, list) or not isinstance(deleted, list) or len(changed) + len(deleted) > MAX_FILES:
            raise ValueError("The R bridge returned an invalid file inventory.")
        stdout, stderr = response.get("stdout", ""), response.get("stderr", "")
        if not isinstance(stdout, str) or not isinstance(stderr, str):
            raise ValueError("The R bridge returned invalid text output.")
        deleted = [_relative(item) for item in deleted]
        if len(deleted) != len(set(deleted)):
            raise ValueError("The R bridge returned duplicate removals.")
        prepared, names, total = [], set(), 0
        for item in changed:
            if not isinstance(item, dict) or set(item) != {"path", "base64"}:
                raise ValueError("The R bridge returned an invalid file.")
            relative = _relative(item["path"])
            if relative in names or relative in deleted:
                raise ValueError("The R bridge returned conflicting files.")
            names.add(relative)
            data = base64.b64decode(item["base64"], validate=True)
            total += len(data)
            if total > MAX_TRANSFER_BYTES:
                raise ValueError("The R bridge result exceeds the browser transfer limit.")
            prepared.append((_file(root, relative), relative, data))
        removals = [(_file(root, item), _relative(item)) for item in deleted]
        # Validate the full response before changing any Python-side file.
        for path, relative in removals:
            if path.exists() and not path.is_file():
                raise ValueError("The R bridge may remove files only.")
        for path, relative in removals:
            path.unlink(missing_ok=True)
            self._sent.pop(relative, None)
        for path, relative, data in prepared:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            self._sent[relative] = hashlib.sha256(data).hexdigest()
        return subprocess.CompletedProcess([], response["returncode"], stdout, stderr)

    async def _command(self, argv, cwd):
        argv = [str(item) for item in argv]
        cwd = Path(cwd).resolve()
        root = self._project_root(cwd)
        if argv[0] == "Rscript":
            release = None
            if root != self._active_root:
                release = str(self._active_root) if self._active_root is not None else None
                self._active_root, self._sent = root, {}
            files, deleted, hashes = self._snapshot(root)
            request = {"argv": argv, "cwd": str(cwd), "root": str(root), "files": files,
                       "deleted": deleted, "profile": "toolkit_launcher/stub_profile.R", "release_root": release}
            response = self.run_r_command(request)
            if inspect.isawaitable(response):
                response = await response
            self._sent = hashes
            result = self._apply_response(root, response)
            result.args = argv
            return result
        if argv[0] != sys.executable or len(argv) < 2:
            raise ValueError("Only the reviewed Python checks and R bridge may run.")
        script = Path(argv[1]) if Path(argv[1]).is_absolute() else cwd / argv[1]
        script = script.resolve()
        try:
            relative = script.relative_to(root).as_posix()
        except ValueError:
            # The canonical teeth runner invokes its reviewed Python helper from
            # the original root while mutating a disposable copy supplied in argv.
            relative = script.relative_to(self.root).as_posix()
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr), _working_directory(cwd):
            if relative == CANONICAL_RUNNERS[0]:
                code = await self._modules["harness"].main(argv[2:])
            elif relative in PYTHON_CHECKS:
                original_argv, original_which = sys.argv, shutil.which
                sys.argv = [str(script)] + argv[2:]
                # Pyodide has no native PDF executable. Match that fact in native
                # adapter tests too; canonical package QC retains its warning.
                shutil.which = lambda name, *a, **k: None if name == "pdftotext" else original_which(name, *a, **k)
                try:
                    runpy.run_path(str(script), run_name="__main__")
                    code = 0
                except SystemExit as exc:
                    code = exc.code if isinstance(exc.code, int) else 0 if exc.code is None else 1
                    if exc.code is not None and not isinstance(exc.code, int):
                        print(str(exc.code), file=sys.stderr)
                finally:
                    sys.argv, shutil.which = original_argv, original_which
            else:
                raise ValueError("This Python program is not a reviewed validation command.")
        return subprocess.CompletedProcess(argv, code, stdout.getvalue(), stderr.getvalue())

    def _capture(self, path, name):
        if path.is_file():
            self._artifacts[_relative(name)] = path.read_bytes()

    def export_files(self):
        """Current run evidence only; includes incomplete logs after a failure."""
        return [{"path": name, "base64": base64.b64encode(data).decode("ascii")}
                for name, data in sorted(self._artifacts.items())]

    def _metadata(self):
        return {"runtime": "browser webR and Pyodide", "scope": "Reviewed toolkit self-test; no uploaded source code is executed.",
                "canonical_sources": {name: hashlib.sha256((self.root / name).read_bytes()).hexdigest() for name in CANONICAL_RUNNERS},
                "browser_sources": {name: hashlib.sha256((self.root / name).read_bytes()).hexdigest() for name in self.runner_files},
                "transformed_functions": self.transformed_functions,
                "limitations": source_requirements()["limits"]}

    async def harness(self):
        if self._busy:
            raise ValueError("Wait for the current validation run to finish.")
        self._busy, self._artifacts = True, {}
        output = _ProgressLog(self.progress)
        try:
            with redirect_stdout(output), redirect_stderr(output):
                ledger = await self._modules["harness"].run(self.root)
            ledger["browser_execution"] = self._metadata()
            self._modules["harness"].write_ledger(self.root, ledger)
            self._artifacts["browser_execution.json"] = json.dumps(self._metadata(), indent=2).encode()
            return ledger
        finally:
            self.last_log = output.getvalue()
            self._artifacts["validation.log"] = self.last_log.encode()
            for relative in ("validation_harness/ledger.json", "validation_harness/EVIDENCE_LEDGER.md", "package_qc_report.md"):
                self._capture(self.root / relative, relative)
            self._busy = False

    async def teeth(self, only=""):
        if self._busy:
            raise ValueError("Wait for the current validation run to finish.")
        if not isinstance(only, str):
            raise ValueError("Choose registered defect identifiers.")
        self._busy, self._artifacts = True, {}
        self.work_parent.mkdir(parents=True, exist_ok=True)
        before = set(self.work_parent.iterdir())
        old_work, old_profile = os.environ.get("TEETH_WORK"), os.environ.get("R_PROFILE_USER")
        os.environ["TEETH_WORK"] = str(self.work_parent)
        output = _ProgressLog(self.progress)
        try:
            with redirect_stdout(output), redirect_stderr(output):
                out = await self._modules["teeth"].run(self.root, only=only)
            summary_path = out / "summary.json"
            summary = json.loads(summary_path.read_text(encoding="utf-8"))
            summary["canonical_runner"] = summary["runner"]
            summary["runner"] = "browser-webR-Pyodide"
            summary["browser_execution"] = self._metadata()
            text = json.dumps(summary, indent=1, ensure_ascii=False)
            summary_path.write_text(text + "\n", encoding="utf-8")
            if not only:
                page = self.root / "validation_harness/index.html"
                page.write_text(re.sub(r'(<script id="teeth-data" type="application/json">\n).*?(\n</script>)',
                                       lambda m: m.group(1) + text + m.group(2), page.read_text(encoding="utf-8"), count=1, flags=re.S), encoding="utf-8")
            self._capture(summary_path, "results/summary.json")
            self._capture(out / Path(summary["results_csv"]).name, "results/" + Path(summary["results_csv"]).name)
            self._artifacts["browser_execution.json"] = json.dumps(self._metadata(), indent=2).encode()
            return summary
        finally:
            self.last_log = output.getvalue()
            self._artifacts["validation.log"] = self.last_log.encode()
            for directory in set(self.work_parent.iterdir()) - before:
                for path in _walk(directory):
                    self._capture(path, "run/" + path.relative_to(directory).as_posix())
            for relative in ("validation_harness/teeth/defects.csv", "validation_harness/teeth/defects.sha256"):
                self._capture(self.root / relative, relative)
            for name, previous in (("TEETH_WORK", old_work), ("R_PROFILE_USER", old_profile)):
                if previous is None:
                    os.environ.pop(name, None)
                else:
                    os.environ[name] = previous
            self._busy = False
