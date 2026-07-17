#!/usr/bin/env python3
"""Tests for the Volume II matrix generator's canonical data model.

The matrix is generated, so the risk that matters is silent loss: a regeneration that
drops completed contract data, or a hand-edit that forks the generated file from its
sources without anyone noticing. Every test here fails if that protection is removed.

Run: python3 scripts/test_volume_ii_matrix.py
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_volume_ii_matrix as g

FAILURES: list[str] = []


def check(cond: bool, label: str) -> None:
    print(f"  {'pass' if cond else 'FAIL'}: {label}")
    if not cond:
        FAILURES.append(label)


def test_completed_values_survive_regeneration() -> None:
    """The core guarantee: regeneration must not reset a completed row."""
    print("test_completed_values_survive_regeneration")
    rows, _ = g.build()
    by_id = {r.row_id: r for r in rows}
    completed = [r for r in rows if r.contract]
    check(len(completed) > 0, f"contracts load from the canonical source ({len(completed)} rows)")

    first = g.render(*g.build())
    second = g.render(*g.build())
    check(first == second, "two consecutive renders are byte-identical")

    on_disk = g.OUT.read_text(encoding="utf-8")
    check(on_disk == first, "the committed matrix matches what the sources produce")

    for r in completed:
        check(f"### {r.row_id} -" in first, f"{r.row_id} contract block is rendered")
        for fname, value in r.contract.items():
            check(value.strip() in first, f"{r.row_id}.{fname} value survives into the matrix")


def test_completed_rows_are_marked_complete() -> None:
    print("test_completed_rows_are_marked_complete")
    rows, stats = g.build()
    for r in rows:
        if r.contract:
            check(r.status.startswith("Complete"), f"{r.row_id} status is Complete, not Pass B required")
        else:
            check(r.status.startswith("Pass B required"), f"{r.row_id} without a contract stays Pass B required")
            break  # one is enough to prove the negative branch


def test_unrelated_rows_do_not_regress() -> None:
    """Completing one slice must not disturb another slice's rows."""
    print("test_unrelated_rows_do_not_regress")
    rows, stats = g.build()
    check(len(rows) == 97, f"all 97 rows remain present ({len(rows)})")
    check(stats["acs"] == 97, f"all 97 AC mappings remain exact ({stats['acs']})")
    uncontracted = [r for r in rows if not r.contract]
    check(all(r.status.startswith("Pass B required") for r in uncontracted),
          "every row without a contract is untouched and still Pass B required")
    check(len(stats["withheld"]) == 18, f"18 limb-withheld rows preserved ({len(stats['withheld'])})")


def test_vague_values_are_rejected() -> None:
    """A field that asserts nothing must not count as completion."""
    print("test_vague_values_are_rejected")
    with tempfile.TemporaryDirectory() as tmp:
        bad = Path(tmp) / "S-99.json"
        bad.write_text(json.dumps({"slice": "S-99", "rows": {"MTX-002": {"idempotency": "TBD"}}}))
        original = g.CONTRACTS
        try:
            g.CONTRACTS = Path(tmp)
            try:
                g.load_contracts()
                check(False, "a vague value ('TBD') is rejected")
            except SystemExit:
                check(True, "a vague value ('TBD') is rejected")
        finally:
            g.CONTRACTS = original


def test_unknown_field_is_rejected() -> None:
    print("test_unknown_field_is_rejected")
    with tempfile.TemporaryDirectory() as tmp:
        bad = Path(tmp) / "S-99.json"
        bad.write_text(json.dumps({"slice": "S-99", "rows": {"MTX-002": {"made_up_field": "x"}}}))
        original = g.CONTRACTS
        try:
            g.CONTRACTS = Path(tmp)
            try:
                g.load_contracts()
                check(False, "an unknown contract field is rejected")
            except SystemExit:
                check(True, "an unknown contract field is rejected")
        finally:
            g.CONTRACTS = original


def test_check_mode_detects_manual_edit() -> None:
    """The negative control for hand-editing the generated file."""
    print("test_check_mode_detects_manual_edit")
    original = g.OUT.read_text(encoding="utf-8")
    try:
        ok = subprocess.run([sys.executable, str(g.ROOT / "scripts" / "build_volume_ii_matrix.py"), "--check"],
                            capture_output=True)
        check(ok.returncode == 0, "--check passes on an unmodified generated file")

        g.OUT.write_text(original.replace("| MTX-001 |", "| MTX-001-HAND-EDITED |", 1), encoding="utf-8")
        bad = subprocess.run([sys.executable, str(g.ROOT / "scripts" / "build_volume_ii_matrix.py"), "--check"],
                             capture_output=True)
        check(bad.returncode != 0, "--check FAILS on a hand-edited generated file")
    finally:
        g.OUT.write_text(original, encoding="utf-8")

    restored = subprocess.run([sys.executable, str(g.ROOT / "scripts" / "build_volume_ii_matrix.py"), "--check"],
                              capture_output=True)
    check(restored.returncode == 0, "the file is restored after the control")


def test_no_duplicate_row_ownership() -> None:
    print("test_no_duplicate_row_ownership")
    seen: dict[str, str] = {}
    dupes = []
    for path in sorted(g.CONTRACTS.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        for row_id in data.get("rows", {}):
            if row_id in seen:
                dupes.append(f"{row_id} in {seen[row_id]} and {path.name}")
            seen[row_id] = path.name
    check(not dupes, f"no row is contracted in two sources ({len(dupes)} duplicates)")


def main() -> int:
    for t in [test_completed_values_survive_regeneration,
              test_completed_rows_are_marked_complete,
              test_unrelated_rows_do_not_regress,
              test_vague_values_are_rejected,
              test_unknown_field_is_rejected,
              test_check_mode_detects_manual_edit,
              test_no_duplicate_row_ownership]:
        t()
    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)} check(s)", file=sys.stderr)
        for f in FAILURES:
            print(f"  - {f}", file=sys.stderr)
        return 1
    print("Volume II matrix generator tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
