"""Exercise the browser adapter with a separate native R mirror as a QC oracle.

No R command sees the Python project directory: only bridge-transferred files.
Use a disposable complete public source snapshot; result evidence is generated
inside it. This test does not claim to execute WebAssembly.
"""
import argparse
import asyncio
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("browser_validation", ROOT / "browser_modules/validation/browser_validation.py")
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


def snapshot(root):
    return {path.relative_to(root).as_posix(): path.read_bytes() for path in adapter._walk(root)}


class NativeMirror:
    def __init__(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="validation-r-mirror-")
        self.root = Path(self.temporary.name) / "project"
        self.active = None
        self.calls = []

    async def __call__(self, request):
        if request["root"] != self.active:
            shutil.rmtree(self.root, ignore_errors=True)
            self.root.mkdir()
            self.active = request["root"]
        for name in request["deleted"]:
            adapter._file(self.root, name).unlink(missing_ok=True)
        for file in request["files"]:
            path = adapter._file(self.root, file["path"])
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(base64.b64decode(file["base64"], validate=True))
        before = snapshot(self.root)
        virtual = Path(request["root"])
        cwd = self.root / Path(request["cwd"]).relative_to(virtual)
        argv = [shutil.which("Rscript")]
        for arg in request["argv"][1:]:
            argv.append(str(self.root / Path(arg).relative_to(virtual)) if arg.startswith(str(virtual) + "/") else arg)
        env = dict(os.environ, R_PROFILE_USER=str(self.root / request["profile"]))
        started = time.monotonic()
        process = await asyncio.create_subprocess_exec(*argv, cwd=cwd, env=env,
                                                       stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        try:
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=240)
        except BaseException:
            process.kill(); await process.wait(); raise
        after = snapshot(self.root)
        files = [{"path": name, "base64": base64.b64encode(data).decode()}
                 for name, data in after.items() if before.get(name) != data]
        call = {"command": request["argv"][1:3], "returncode": process.returncode,
                "seconds": round(time.monotonic() - started, 3), "sent_files": len(request["files"]),
                "returned_files": len(files)}
        self.calls.append(call)
        print("R", len(self.calls), call, file=sys.__stdout__, flush=True)
        return {"returncode": process.returncode, "stdout": stdout.decode(errors="replace"),
                "stderr": stderr.decode(errors="replace"), "files": files,
                "deleted": sorted(set(before) - set(after))}


async def main(args):
    source = args.source.resolve()
    mirror = NativeMirror()
    runtime = adapter.ValidationRuntime(source, mirror)
    started = time.monotonic()
    report = {"scope": "Browser Python adapter with separate native R mirror; not WebAssembly", "passed": False}
    evidence = {}
    try:
        ledger = await runtime.harness()
        report["gates"] = [{k: row[k] for k in ("gate", "status", "evidence")} for row in ledger["gates"]]
        assert len(ledger["gates"]) == 10
        gates = {row["gate"].split()[0]: row for row in ledger["gates"]}
        assert gates["G5"]["status"] == "manual" and gates["G7"]["status"] == "not signed"
        assert all(gates[g]["status"] == "green" for g in ("G1", "G2", "G3", "G4", "G6", "G8", "G9")), report["gates"]
        assert gates["G10"]["status"] == "stale"
        print("PASS ten canonical gates with manual/unsigned/stale distinctions", flush=True)
        if args.full_teeth or args.only:
            summary = await runtime.teeth(only=args.only)
            report["teeth"] = summary
            evidence.update({"teeth/" + item["path"]: item for item in runtime.export_files()})
            if args.full_teeth:
                assert summary["n_run"] == 18 and not summary["partial"]
                assert summary["counts"] == {"CAUGHT": 15, "SURVIVED": 0, "EQUIVALENT": 1, "NOT APPLICABLE": 2}, summary["counts"]
                ledger = await runtime.harness()
                assert ledger["gates"][-1]["status"] == "green", ledger["gates"][-1]
            else:
                assert summary["partial"]
            print("PASS frozen defect registry:", summary["counts"], flush=True)
        report["passed"] = True
    except BaseException as error:
        report["error"] = repr(error)
        raise
    finally:
        report["calls"] = mirror.calls
        report["elapsed_seconds"] = time.monotonic() - started
        args.output.mkdir(parents=True, exist_ok=True)
        (args.output / "report.json").write_text(json.dumps(report, indent=2))
        (args.output / "last.log").write_text(runtime.last_log)
        evidence.update({"latest/" + item["path"]: item for item in runtime.export_files()})
        for name, file in evidence.items():
            path = args.output / "exports" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(base64.b64decode(file["base64"]))
        mirror.temporary.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--full-teeth", action="store_true")
    parser.add_argument("--only", default="")
    args = parser.parse_args()
    if args.full_teeth and args.only:
        parser.error("Use the full registry or explicit partial IDs, not both.")
    asyncio.run(main(args))
