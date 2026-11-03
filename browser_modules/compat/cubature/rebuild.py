"""Verify or rebuild the compiler-only cubature compatibility artifact.

Toolkit users receive the compiled package automatically. This developer recipe
uses the pinned official webR toolchain and leaves every scientific source file
unchanged. Only the upstream Makevars.webr build recipe is patched.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify_assets():
    lock = json.loads((HERE / "lock.json").read_text())
    for item in (lock["source"], lock["binary"], lock["patch"]):
        if sha(HERE / item["file"]) != item["sha256"]:
            raise ValueError("Pinned cubature asset checksum mismatch: " + item["file"])
    with tarfile.open(HERE / lock["binary"]["file"]) as package:
        description = package.extractfile("cubature/DESCRIPTION").read().decode()
        library = package.extractfile("cubature/libs/cubature.so").read()
    if "Version: " + lock["version"] + "\n" not in description or "wasm32-unknown-emscripten" not in description:
        raise ValueError("The compatibility package has unexpected version/platform metadata.")
    if hashlib.sha256(library).hexdigest() != lock["binary"]["shared_library_sha256"]:
        raise ValueError("The compiled cubature library differs from the reviewed artifact.")
    return lock


def install_into(site):
    """Pages hook: call after Shiny export and before package-index hashing."""
    lock = verify_assets()
    target = Path(site) / "shinylive/webr/packages/cubature"
    target.mkdir(parents=True, exist_ok=True)
    shutil.copy2(HERE / lock["binary"]["file"], target / lock["binary"]["file"])
    return {"package": lock["package"], "version": lock["version"], "sha256": lock["binary"]["sha256"]}


def patched_source(work, lock):
    original = work / "original"
    original.mkdir()
    with tarfile.open(HERE / lock["source"]["file"]) as archive:
        archive.extractall(original, filter="data")
    roots = list(original.iterdir())
    if len(roots) != 1 or not roots[0].is_dir():
        raise ValueError("Unexpected upstream source archive layout.")
    source = roots[0]
    patched = work / "patched/cubature"
    shutil.copytree(source, patched)
    recipe = patched / "src/Makevars.webr"
    if sha(recipe) != lock["source"]["makevars_sha256"]:
        raise ValueError("The upstream build recipe changed.")
    value = recipe.read_text().replace("WASM_CFLAGS", "CUBATURE_WASM_CFLAGS")
    if value.count("$(CFLAGS) $(CPICFLAGS)") != 3:
        raise ValueError("Unexpected nested compiler-flag recipe.")
    value = value.replace("$(CFLAGS) $(CPICFLAGS)", "$(CFLAGS) $(CPICFLAGS) -fwasm-exceptions -sSUPPORT_LONGJMP=wasm")
    recipe.write_text(value)
    if sha(recipe) != lock["patch"]["patched_makevars_sha256"]:
        raise ValueError("The applied compiler patch differs from the reviewed patch.")
    old = {p.relative_to(source).as_posix(): sha(p) for p in source.rglob("*") if p.is_file()}
    new = {p.relative_to(patched).as_posix(): sha(p) for p in patched.rglob("*") if p.is_file()}
    if old.keys() != new.keys() or sorted(k for k in old if old[k] != new[k]) != ["src/Makevars.webr"]:
        raise ValueError("A file outside the reviewed build recipe changed.")
    return {"upstream_files": len(old), "unchanged_files": len(old) - 1,
            "changed_files": ["src/Makevars.webr"]}


def rebuild(directory, engine):
    lock = verify_assets()
    directory = Path(directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="cubature-build-", dir=directory) as temporary:
        work = Path(temporary)
        proof = patched_source(work, lock)
        script = ('options(rwasm.webr_root="/opt/webr")\n'
                  'pak::pkg_install("Rcpp@' + lock["toolchain"]["Rcpp"] + '", ask=FALSE)\n'
                  'stopifnot(as.character(packageVersion("Rcpp")) == "' + lock["toolchain"]["Rcpp"] + '")\n'
                  'dir.create("/work/out",showWarnings=FALSE)\n'
                  'rwasm::build("local::/work/patched/cubature",out_dir="/work/out",dependencies=FALSE)\n')
        (work / "build.R").write_text(script)
        command = [engine, "run", "--rm", "--platform", lock["toolchain"]["platform"],
                   "-v", str(work) + ":/work", lock["toolchain"]["image"], "Rscript", "/work/build.R"]
        with (directory / "build.log").open("w") as log:
            subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT)
        target = directory / lock["binary"]["file"]
        shutil.copy2(work / "out" / target.name, target)
        with tarfile.open(target) as package:
            library_sha256 = hashlib.sha256(package.extractfile("cubature/libs/cubature.so").read()).hexdigest()
        if library_sha256 != lock["binary"]["shared_library_sha256"]:
            raise ValueError("The rebuilt Wasm library differs from the pinned compiler output; investigate before updating the release.")
        proof.update(binary_sha256=sha(target), shared_library_sha256=library_sha256,
                     compiled_library_matches_published=True, toolchain=lock["toolchain"],
                     note="Build timestamps can change the archive hash; review and run browser numerical QC before updating the published lock.")
        (directory / "rebuild-provenance.json").write_text(json.dumps(proof, indent=2) + "\n")
        print(json.dumps(proof, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rebuild", action="store_true")
    parser.add_argument("--work", type=Path)
    parser.add_argument("--container-runtime", default="podman", choices=("podman", "docker"))
    args = parser.parse_args()
    if args.rebuild:
        if args.work is None:
            parser.error("Rebuild needs an external --work directory.")
        rebuild(args.work, args.container_runtime)
    else:
        lock = verify_assets()
        with tempfile.TemporaryDirectory(prefix="cubature-source-proof-") as temporary:
            proof = patched_source(Path(temporary), lock)
        print(json.dumps({"verified": True, "binary_sha256": lock["binary"]["sha256"], **proof}, indent=2))
