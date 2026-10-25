#!/usr/bin/env python3
"""Plant one seeded defect from the registry into a throwaway copy of the repository.

Usage:
  python3 apply_defect.py <defects.csv> <id> <copy_root>           plant the defect
  python3 apply_defect.py <defects.csv> <id> <copy_root> --check   only check that it applies
  python3 apply_defect.py <defects.csv> --check-all <root>          check every applicable row

The registry row gives the file (relative to the root), an exact old_str and its new_str.
Nothing is written unless old_str occurs exactly once in that file. The copy must not be a git
checkout (no .git entry at its root), so the defect can never land in a working tree or branch.

Exit codes: 0 applied (or applies), 2 old_str missing or not unique, 3 not applicable (file
"n/a"), 4 bad arguments, unknown id or a git checkout as target.
Part of the validation harness's seeded-defect run (G10). Synthetic data only.
"""
import csv
import os
import sys

FIELDS = ["id", "class", "file", "old_str", "new_str", "predicted_catcher", "rationale"]


def load(registry):
    with open(registry, encoding="utf-8", newline="") as fh:
        rows = list(csv.DictReader(fh))
    if not rows or list(rows[0].keys()) != FIELDS:
        raise SystemExit(f"registry columns must be {FIELDS}")
    return rows


def check(row, root):
    """(status, message): status 0 applies, 2 does not, 3 not applicable"""
    if row["file"].strip().lower() in ("n/a", ""):
        return 3, f"{row['id']}: not applicable ({row['rationale']})"
    path = os.path.join(root, row["file"])
    if not os.path.isfile(path):
        return 2, f"{row['id']}: {row['file']} does not exist under {root}"
    text = open(path, encoding="utf-8").read()
    n = text.count(row["old_str"]) if row["old_str"] else 0
    if n != 1:
        return 2, f"{row['id']}: old_str occurs {n} times in {row['file']} (must be exactly once); nothing changed"
    return 0, f"{row['id']}: applies to {row['file']}"


def main(argv):
    if len(argv) >= 3 and argv[1] == "--check-all":
        rows, root, bad = load(argv[0]), argv[2], 0
        for r in rows:
            s, msg = check(r, root)
            print(msg)
            bad += s == 2
        return 2 if bad else 0
    if len(argv) < 3:
        print(__doc__)
        return 4
    registry, did, root = argv[0], argv[1], argv[2]
    only_check = "--check" in argv[3:]
    match = [r for r in load(registry) if r["id"] == did]
    if len(match) != 1:
        print(f"{did}: not in the registry exactly once")
        return 4
    row = match[0]
    status, msg = check(row, root)
    if status or only_check:
        print(msg)
        return status
    if os.path.exists(os.path.join(root, ".git")):
        print(f"{did}: refusing to plant a defect in a git checkout ({root}); use a throwaway copy")
        return 4
    path = os.path.join(root, row["file"])
    text = open(path, encoding="utf-8").read()
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text.replace(row["old_str"], row["new_str"], 1))
    print(f"{did}: planted in {row['file']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
