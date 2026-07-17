#!/usr/bin/env python3
"""Generate the Volume II implementation backlog from the frozen specification.

The backlog is derived rather than authored, for the same reason the implementation matrix
is: a hand-written backlog over 97 rows and 24 slices cannot be trusted to be complete or
to stay true, and a derived one can be re-derived and diffed. Every item is a matrix row,
and every matrix row becomes exactly one item. Nothing else may become an item -- a backlog
that can invent work can invent a feature.

Ordering is the slice dependency graph from SLICE_REGISTER.md, topologically sorted, with
the cross-cutting rows last because they are enforced in every slice rather than built once.
Ties break on slice id so the output is byte-deterministic.

Run: python3 scripts/build_implementation_backlog.py [--check]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
V2 = ROOT / "specification" / "volume-ii"
OUT = V2 / "IMPLEMENTATION_BACKLOG.md"

VOLUME_I_BASELINE = "v1.5-volume-i-frozen"
MANUAL_BASELINE = "v1.7-engineering-manual-accepted"

# The slice dependency table in SLICE_REGISTER.md:
# | S-xx | Name | Outcome | Depends on | Unlocks | Independently testable | OD limb |
SLICE_ROW = re.compile(
    r"^\|\s*(S-\d{2})\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|"
    r"\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*$")
MATRIX_ROW = re.compile(r"^\|\s*(MTX-\d{3})\s*\|\s*(AC-[A-Z]+-\d{3})\s*\|\s*([^|]+?)\s*\|")


def slices() -> dict[str, dict]:
    text = (V2 / "SLICE_REGISTER.md").read_text(encoding="utf-8")
    out: dict[str, dict] = {}
    for line in text.splitlines():
        m = SLICE_ROW.match(line)
        if not m or m.group(2).strip() in ("Name", "---"):
            continue
        sid, name, outcome, depends, _unlocks, _test, limb = (g.strip() for g in m.groups())
        out[sid] = {
            "name": name,
            "outcome": outcome,
            "depends": [d for d in re.findall(r"S-\d{2}", depends)],
            "limb": limb,
        }
    return out


def topo(sl: dict[str, dict]) -> list[str]:
    """Slice order. A cycle is a defect in the register, not something to route around."""
    order: list[str] = []
    seen: set[str] = set()
    while len(order) < len(sl):
        ready = sorted(s for s in sl
                       if s not in seen and all(d in seen for d in sl[s]["depends"]))
        if not ready:
            raise SystemExit(f"SLICE_REGISTER.md dependency cycle among {sorted(set(sl) - seen)}")
        for s in ready:
            order.append(s)
            seen.add(s)
    return order


def contracts() -> dict[str, tuple[str, dict]]:
    out: dict[str, tuple[str, dict]] = {}
    for path in sorted((V2 / "contracts").glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        for row_id, fields in data.get("rows", {}).items():
            out[row_id] = (path.name, fields)
    return out


def matrix_rows() -> dict[str, dict]:
    text = (V2 / "IMPLEMENTATION_MATRIX.md").read_text(encoding="utf-8")
    out: dict[str, dict] = {}
    for line in text.splitlines():
        m = MATRIX_ROW.match(line)
        if not m:
            continue
        cells = [c.strip() for c in line.split("|")]
        if len(cells) < 14:
            continue
        out[m.group(1)] = {
            "ac": m.group(2), "source": m.group(3),
            "slice": cells[10], "tests": cells[11],
            "status": cells[12], "blocker": cells[13],
        }
    return out


def first_sentence(text: str, limit: int = 400) -> str:
    s = re.split(r"(?<=\.)\s+", text.strip())[0]
    return s if len(s) <= limit else s[:limit].rstrip() + " ..."


def render() -> str:
    sl = slices()
    order = topo(sl)
    rows = matrix_rows()
    con = contracts()
    rank = {s: i for i, s in enumerate(order)}

    def key(item: tuple[str, dict]) -> tuple:
        rid, r = item
        first = r["slice"].split(",")[0]
        # `ALL` rows are enforced in every slice, so they are verified last, never built once.
        return (len(order) + 1 if first == "ALL" else rank.get(first, len(order)),
                int(rid.split("-")[1]))

    ordered = sorted(rows.items(), key=key)

    L: list[str] = []
    A = L.append
    A("# Volume II Implementation Backlog")
    A("")
    A("## Status")
    A("")
    A("- Status: Generated implementation backlog. Not product authority. Not frozen.")
    A("- Last Updated: 2026-07-17")
    A("- Owner: Chief Architect")
    A(f"- Product-behaviour baseline: `{VOLUME_I_BASELINE}` (frozen Volume I)")
    A(f"- Engineering-practice baseline: `{MANUAL_BASELINE}` (accepted Engineering Manual)")
    A("")
    A("## Authority")
    A("")
    A("This backlog carries no product authority. Every item is a matrix row, every matrix row is")
    A("derived from an accepted Volume I acceptance criterion, and the contract named by each item")
    A("is the thing to be implemented. Where this backlog and a contract disagree, the contract")
    A("prevails and this backlog is defective. It invents no feature: an item that no acceptance")
    A("criterion governs cannot exist here, by construction.")
    A("")
    A("## Derivation")
    A("")
    A("Generated by `scripts/build_implementation_backlog.py` from `SLICE_REGISTER.md`,")
    A("`IMPLEMENTATION_MATRIX.md` and the per-slice contract sources. Re-running it against an")
    A("unchanged specification MUST reproduce this file byte for byte, and")
    A("`--check` fails if it differs. Do not edit this file by hand.")
    A("")
    A("Order is the slice dependency graph, topologically sorted. Cross-cutting (`ALL`) rows are")
    A("listed last because they are enforced in every slice rather than implemented once; they are")
    A("not the final work, they are the work that is never finished early.")
    A("")
    A("## How To Use An Item")
    A("")
    A("An item is done when its acceptance criterion passes, and not before. Read in this order:")
    A("")
    A("1. the **acceptance criterion** in `../volume-i/ACCEPTANCE_AND_TEST_MAPPING.md` — the oracle;")
    A("2. the **governing source** — the capability, workflow or product rule that owns the behaviour;")
    A("3. the **contract** — the 40 structured fields naming exactly what to build;")
    A("4. the **verification obligation** — the test types Volume I requires.")
    A("")
    A("A `Withheld limb` line means one named behaviour is reserved by a pending owner decision.")
    A("Build everything else; never effect the limb, and never resolve it by inference. The")
    A("surrounding behaviour is specified and testable.")
    A("")
    A("## Slice Order")
    A("")
    A("| # | Slice | Name | Outcome | Depends on | Withheld limb |")
    A("| --- | --- | --- | --- | --- | --- |")
    for i, s in enumerate(order, 1):
        d = sl[s]
        A(f"| {i} | {s} | {d['name']} | {d['outcome']} | "
          f"{', '.join(d['depends']) or 'none'} | {d['limb']} |")
    A("")
    A("## Backlog")
    A("")
    for n, (rid, r) in enumerate(ordered, 1):
        src, fields = con.get(rid, ("(none)", {}))
        A(f"### BL-{n:03d} — {rid} ({r['ac']})")
        A("")
        A(f"- Slice: {r['slice']}" + (f" — {sl[r['slice'].split(',')[0]]['name']}"
                                      if r['slice'].split(',')[0] in sl else ""))
        A(f"- Acceptance criterion: `{r['ac']}` — the oracle; see `../volume-i/ACCEPTANCE_AND_TEST_MAPPING.md`")
        A(f"- Governing source: {r['source']}")
        A(f"- Owning contract: `specification/volume-ii/contracts/{src}` row `{rid}`")
        owner = fields.get("contract_owner", "")
        if owner:
            A(f"- Canonical narrative owner: [{owner.split('#')[0].split('/')[-1]}]({owner.split('specification/volume-ii/')[-1] if 'specification/volume-ii/' in owner else owner})")
        deps = sl.get(r["slice"].split(",")[0], {}).get("depends", [])
        A(f"- Dependencies: {', '.join(deps) if deps else 'none'}"
          + (" (cross-cutting: every slice)" if r["slice"] == "ALL" else ""))
        A(f"- Verification obligation: {r['tests']}")
        A(f"- Status: {r['status']}")
        if r["blocker"] != "None":
            A(f"- Withheld limb: {r['blocker']}")
        if "interface_type" in fields:
            A(f"- Interface: {first_sentence(fields['interface_type'], 200)}")
        A("")

    withheld = [r for r in rows.values() if "withheld" in r["status"]]
    A("## Totals")
    A("")
    A(f"- Backlog items: {len(ordered)}")
    A(f"- Matrix rows: {len(rows)} — every row is exactly one item, by construction")
    A(f"- Items carrying a withheld limb: {len(withheld)}")
    A(f"- Slices: {len(order)}")
    A("")
    A("## Change Control")
    A("")
    A("This file is generated. To change it, change the specification and re-run the generator.")
    A("An item MUST NOT be added, removed or reordered by hand: the ordering is the dependency")
    A("graph and the population is the acceptance-criterion set, and both are properties of the")
    A("specification rather than of this document.")
    return "\n".join(L) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate the Volume II implementation backlog")
    ap.add_argument("--check", action="store_true",
                    help="fail if the generated file differs from what the sources produce")
    args = ap.parse_args()
    rendered = render()
    if args.check:
        current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if current != rendered:
            print(f"{OUT.relative_to(ROOT)} differs from its canonical sources; "
                  "it has been hand-edited or is stale. Run the generator.", file=sys.stderr)
            return 1
        print("backlog matches its canonical sources")
        return 0
    OUT.write_text(rendered, encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
