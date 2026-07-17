#!/usr/bin/env python3
"""Generate the Volume II canonical implementation matrix from frozen Volume I.

The matrix is derived mechanically rather than authored, so that its coverage is a
property of the source rather than of anyone's diligence: every Volume I acceptance
criterion becomes exactly one row, and every row carries the governing source it was
derived from. A hand-authored matrix over 97 criteria cannot be trusted to be
complete; a derived one can be re-derived and diffed.

Pass A fills only the columns frozen Volume I authoritatively supplies. Technical
contract fields are marked "Pass B required" rather than guessed, per the Pass A
brief: they must not be invented to make the matrix look complete.

Run: python3 scripts/build_volume_ii_matrix.py
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / "specification"
V1 = SPEC / "volume-i"
OUT = SPEC / "volume-ii" / "IMPLEMENTATION_MATRIX.md"
CONTRACTS = SPEC / "volume-ii" / "contracts"

VOLUME_I_BASELINE = "v1.5-volume-i-frozen"
MANUAL_BASELINE = "v1.7-engineering-manual-accepted"

# Slice map. A slice is a vertical, independently testable path, so it is keyed on the
# capability or workflow that owns the outcome -- never on a technical layer.
SLICE_BY_CAP = {
    "CAP-001": "S-01", "CAP-002": "S-02", "CAP-003": "S-03", "CAP-004": "S-04",
    "CAP-005": "S-05", "CAP-006": "S-06", "CAP-007": "S-07", "CAP-008": "S-07",
    "CAP-009": "S-09", "CAP-010": "S-09", "CAP-011": "S-09", "CAP-012": "S-10",
    "CAP-013": "S-11", "CAP-014": "S-12", "CAP-015": "S-13", "CAP-016": "S-14",
    "CAP-017": "S-15", "CAP-018": "S-16", "CAP-019": "S-17", "CAP-020": "S-18",
    "CAP-021": "S-19", "CAP-022": "S-20", "CAP-023": "S-21", "CAP-024": "S-22",
    "CAP-025": "S-23",
}
SLICE_BY_WF = {
    "WF-001": "S-01", "WF-002": "S-03", "WF-003": "S-05", "WF-004": "S-06",
    "WF-005": "S-07", "WF-006": "S-08", "WF-007": "S-12", "WF-008": "S-13",
    "WF-009": "S-14", "WF-010": "S-15", "WF-011": "S-18", "WF-012": "S-17",
    "WF-013": "S-23", "WF-014": "S-19", "WF-015": "S-22", "WF-016": "S-20",
    "WF-017": "S-24", "WF-018": "S-21",
}
# Score-model areas are assigned to the slice that owns the behaviour they constrain.
SLICE_BY_SM_AREA = {
    "Chain Completeness": "S-13", "Score Attribution": "S-13", "Issue Evidence": "S-12",
    "Reassessment Lineage": "S-18", "Disputed Issue Eligibility": "S-12",
    "Issue Deduplication": "S-12", "Visibility And Redaction": "S-16",
    "Verification Evidence": "S-05",
}

# Engineering Manual volumes by concern. EM chapters govern practice only; they never
# supply product behaviour, so a row cites them for how to build, not what to build.
EM_BY_CONCERN = {
    "identity": "EM-VIII (security), EM-VII (API), EM-III (implementation)",
    "pipeline": "EM-VI (background/integration), EM-V (persistence), EM-III",
    "analysis": "EM-VI (AI provider integration), EM-III, EM-IX (testing)",
    "read": "EM-VII (API), EM-V (read models), EM-III",
    "lifecycle": "EM-VIII (security), EM-V (persistence), EM-VI (jobs)",
    "ops": "EM-X (production), EM-VI (jobs), EM-VIII (security)",
}
CONCERN_BY_SLICE = {
    "S-00": "ops", "S-01": "identity", "S-02": "identity", "S-03": "identity",
    "S-04": "pipeline", "S-05": "pipeline", "S-06": "pipeline", "S-07": "pipeline",
    "S-08": "pipeline", "S-09": "analysis", "S-10": "analysis", "S-11": "analysis",
    "S-12": "analysis", "S-13": "analysis", "S-14": "analysis", "S-15": "read",
    "S-16": "read", "S-17": "read", "S-18": "pipeline", "S-19": "pipeline",
    "S-20": "read", "S-21": "lifecycle", "S-22": "lifecycle", "S-23": "lifecycle",
    "S-24": "ops",
}

# The canonical Pass B contract schema. The order is fixed here rather than taken from the
# JSON, so regeneration is byte-deterministic regardless of key order in the source.
CONTRACT_FIELDS = [
    "contract_owner",
    "interface_type", "route", "request_schema", "response_schema", "controller",
    "command", "command_input", "command_output", "actor", "organization_scope",
    "aggregate", "aggregate_boundary", "value_objects", "domain_service",
    "repository", "persistence_model", "migration", "transaction_boundary",
    "concurrency", "idempotency",
    "background_job", "queue", "retry_policy", "terminal_failure", "reconciliation",
    "domain_events", "event_payload", "event_producer", "event_consumers", "serializer",
    "authorization_entry_point", "permission_checks", "tenant_boundary",
    "error_contract", "audit_record", "observability", "retention",
    "test_contracts", "rollout",
]
FIELD_LABELS = {f: f.replace("_", " ") for f in CONTRACT_FIELDS}

# Values that look like completion but assert nothing. A contract must name exact ownership
# and behaviour, so these are rejected rather than accepted as filled.
VAGUE_VALUES = re.compile(
    r"(?i)^\s*(tbd|to be decided|to be determined|handled by service|standard validation|"
    r"normal authorization|appropriate logging|retry as needed|tests required|existing model|"
    r"as needed|n/a|none|pass b required)\s*\.?\s*$"
)


# Pending owner decisions withhold a limb rather than a capability. The register records
# each as "Volume II - no" under its interim, so Pass A proceeds and marks the limb.
# The withheld text is the limb, never the whole row: Volume I permits the surrounding
# behaviour and permits the state to be represented, only never effected.
WITHHELD_LIMBS = {
    "OD-014": ("UPSTREAM-V1-PROJECT-LIFECYCLE-003",
               "pause/resume/archive transition withheld; create/activate permitted; "
               "paused/archived state may be represented, never effected"),
    "OD-023": ("UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009",
               "credential rotation begin/complete withheld; other Credential lifecycle permitted"),
    "OD-027": (None, "second IndexingJob per ParsingJob and index-key narrowing withheld "
                     "under indexing-interim-v1"),
    "OD-031": (None, "routine retention-expiry destruction withheld under "
                     "retention-destruction-trigger-interim-v1"),
    "OD-032": (None, "canonical namespace for an unassigned record withheld; behaviour permitted "
                     "under the interim"),
}


@dataclass
class Row:
    row_id: str
    ac: str
    source_kind: str
    source: str
    caps: list[str] = field(default_factory=list)
    wfs: list[str] = field(default_factory=list)
    prules: list[str] = field(default_factory=list)
    ods: list[str] = field(default_factory=list)
    prreqs: list[str] = field(default_factory=list)
    test_types: list[str] = field(default_factory=list)
    slice_id: str = ""
    status: str = "Pass B required"
    blocker: str = "None"
    note: str = ""
    contract: dict = field(default_factory=dict)


def load_contracts() -> dict[str, dict]:
    """Load completed contract data from the canonical per-slice JSON sources.

    The matrix is generated, so contract data cannot live in it: a regeneration would
    destroy hand-entered cells. It also must not live in a second prose document, which
    would create a competing source of truth. So the structured facts live here, the
    narrative contract lives in the Volume II document named by `contract_owner`, and
    the matrix is derived from both. `scripts/validate_volume_ii.py` enforces that the
    document and the structured facts agree, so consistency is executed, not promised.
    """
    contracts: dict[str, dict] = {}
    if not CONTRACTS.exists():
        return contracts
    for path in sorted(CONTRACTS.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        for row_id, fields in data.get("rows", {}).items():
            if row_id in contracts:
                raise SystemExit(f"{path.name}: {row_id} is defined in more than one contract source")
            unknown = set(fields) - set(CONTRACT_FIELDS)
            if unknown:
                raise SystemExit(f"{path.name}: {row_id} has unknown fields {sorted(unknown)}")
            for key, value in fields.items():
                if not isinstance(value, str) or not value.strip():
                    raise SystemExit(f"{path.name}: {row_id}.{key} must be a non-empty string")
                if VAGUE_VALUES.match(value):
                    raise SystemExit(f"{path.name}: {row_id}.{key} is vague: {value!r}")
            contracts[row_id] = fields
    return contracts


def expand_ranges(text: str, prefix: str) -> list[str]:
    """Expand 'CAP-009 through CAP-017' plus bare ids, preserving document order."""
    out: list[str] = []
    for a, b in re.findall(rf"({prefix}-\d{{3}})\s+through\s+({prefix}-\d{{3}})", text):
        for n in range(int(a.split("-")[-1]), int(b.split("-")[-1]) + 1):
            out.append(f"{prefix}-{n:03d}")
    for m in re.findall(rf"\b{prefix}-\d{{3}}\b", text):
        out.append(m)
    seen, uniq = set(), []
    for x in out:
        if x not in seen:
            seen.add(x); uniq.append(x)
    return uniq


def parse_ac_tables() -> list[Row]:
    text = (V1 / "ACCEPTANCE_AND_TEST_MAPPING.md").read_text(encoding="utf-8")
    rows: list[Row] = []
    for line in text.splitlines():
        m = re.match(r"^\|\s*(AC-[A-Z]+-\d{3})\s*\|\s*([^|]+?)\s*\|\s*(.*?)\s*\|\s*([^|]*?)\s*\|\s*$", line)
        if not m:
            continue
        ac, source, _assertion, types = m.groups()
        kind = ac.split("-")[1]
        rows.append(Row(
            row_id="", ac=ac, source_kind=kind, source=source.strip(),
            # TYP-E2E contains a digit; [A-Z]+ silently truncates it to TYP-E.
            test_types=re.findall(r"TYP-[A-Z0-9]+", types),
        ))
    return rows


def parse_owner_decisions() -> dict[str, dict]:
    """Map each owner decision to the artefacts it affects.

    The register is the only authoritative per-decision mapping. The Volume I
    traceability matrix lumps decisions at PR-REQ granularity, which would attribute
    ~23 decisions to a single row and say nothing useful.
    """
    text = (V1 / "OWNER_DECISION_REGISTER.md").read_text(encoding="utf-8")
    parts = re.split(r"\n### (OD-\d{3})[^\n]*\n", text)
    out: dict[str, dict] = {}
    for i in range(1, len(parts), 2):
        od, body = parts[i], parts[i + 1]

        def field_of(label: str) -> str:
            m = re.search(rf"^- {label}:\s*(.+)$", body, re.M)
            return m.group(1).strip() if m else ""

        status = field_of("Current Status")
        out[od] = {
            "status": status,
            "pending": status.lower().startswith("pending"),
            "acs": (expand_ranges(field_of("Affected Acceptance Criteria"), "AC-CAP")
                    + expand_ranges(field_of("Affected Acceptance Criteria"), "AC-WF")
                    + expand_ranges(field_of("Affected Acceptance Criteria"), "AC-SM")
                    + expand_ranges(field_of("Affected Acceptance Criteria"), "AC-PRULE")),
        }
    return out


def parse_product_rules() -> dict[str, dict]:
    text = (V1 / "PRODUCT_RULES.md").read_text(encoding="utf-8")
    out: dict[str, dict] = {}
    for line in text.splitlines():
        cells = [c.strip() for c in line.split("|")]
        if len(cells) < 9 or not re.match(r"^PRULE-\d{3}$", cells[1]):
            continue
        out[cells[1]] = {
            "caps": expand_ranges(cells[6], "CAP"),
            "wfs": expand_ranges(cells[7], "WF"),
            "ods": expand_ranges(cells[8], "OD"),
            "sources": expand_ranges(cells[3], "SEC-REQ") + expand_ranges(cells[3], "PM-REQ"),
        }
    return out


def parse_traceability() -> list[dict]:
    text = (V1 / "TRACEABILITY_MATRIX.md").read_text(encoding="utf-8")
    out = []
    for line in text.splitlines():
        cells = [c.strip() for c in line.split("|")]
        if len(cells) < 8 or not cells[1].startswith("PR-REQ"):
            continue
        out.append({
            "prreqs": expand_ranges(cells[1], "PR-REQ"),
            "caps": expand_ranges(cells[2], "CAP"),
            "wfs": expand_ranges(cells[3], "WF"),
            "prules": expand_ranges(cells[4], "PRULE"),
            "acs": expand_ranges(cells[5], "AC-CAP") + expand_ranges(cells[5], "AC-WF")
                  + expand_ranges(cells[5], "AC-SM") + expand_ranges(cells[5], "AC-PRULE"),
            "ods": expand_ranges(cells[7], "OD"),
        })
    return out


def build() -> tuple[list[Row], dict]:
    rows = parse_ac_tables()
    prules = parse_product_rules()
    trace = parse_traceability()
    ods = parse_owner_decisions()
    contracts = load_contracts()

    for i, r in enumerate(rows, start=1):
        r.row_id = f"MTX-{i:03d}"

        if r.source_kind == "CAP":
            r.caps = [r.source]
        elif r.source_kind == "WF":
            r.wfs = [r.source]
        elif r.source_kind == "PRULE":
            r.prules = [r.source]
            meta = prules.get(r.source, {})
            r.caps = meta.get("caps", [])
            r.wfs = meta.get("wfs", [])

        # PR-REQ reach comes from the Volume I traceability matrix.
        prreqs: list[str] = []
        for t in trace:
            if r.ac in t["acs"]:
                prreqs += t["prreqs"]
        r.prreqs = sorted(set(prreqs), key=lambda x: int(x.split("-")[-1]))

        # Owner-decision dependency comes from the register's own per-decision mapping,
        # which names the exact acceptance criteria each decision affects.
        r.ods = sorted({od for od, meta in ods.items() if r.ac in meta["acs"]},
                       key=lambda x: int(x.split("-")[-1]))

        r.contract = contracts.get(r.row_id, {})
        if r.contract:
            r.status = "Complete"

        pending = [od for od in r.ods if ods[od]["pending"]]
        if pending:
            limbs = []
            blockers = []
            for od in pending:
                upstream, limb = WITHHELD_LIMBS.get(od, (None, "limb withheld under its interim"))
                limbs.append(f"{od}: {limb}")
                blockers.append(f"{upstream} ({od})" if upstream else od)
            r.status = ("Complete; limb withheld" if r.contract else "Pass B required; limb withheld")
            r.blocker = "; ".join(blockers) + " -- " + "; ".join(limbs)

        # Slice assignment, from the capability or workflow that owns the outcome.
        if r.source_kind == "SM":
            r.slice_id = SLICE_BY_SM_AREA.get(r.source, "")
        elif r.caps:
            slices = {SLICE_BY_CAP[c] for c in r.caps if c in SLICE_BY_CAP}
            # A rule spanning most capabilities is cross-cutting, not a slice of its own.
            r.slice_id = "ALL" if len(slices) > 5 else ",".join(sorted(slices))
        elif r.wfs:
            slices = {SLICE_BY_WF[w] for w in r.wfs if w in SLICE_BY_WF}
            r.slice_id = "ALL" if len(slices) > 5 else ",".join(sorted(slices))
        if not r.slice_id:
            r.slice_id = "UNASSIGNED"

    stats = {
        "rows": len(rows),
        "acs": len({r.ac for r in rows}),
        "unassigned": [r.row_id for r in rows if r.slice_id == "UNASSIGNED"],
        "cross_cutting": len([r for r in rows if r.slice_id == "ALL"]),
        "withheld": [r.row_id for r in rows if "withheld" in r.status],
        "complete": [r.row_id for r in rows if r.status.startswith("Complete")],
        "outstanding": [r.row_id for r in rows if r.status.startswith("Pass B required")],
        "pending_ods": sorted({o for r in rows for o in r.ods if ods[o]["pending"]}),
    }
    return rows, stats


def em_for(slice_id: str) -> str:
    first = slice_id.split(",")[0]
    if first == "ALL":
        return "EM-I (governance), EM-II (architecture), EM-III (implementation), EM-IX (testing)"
    return EM_BY_CONCERN.get(CONCERN_BY_SLICE.get(first, "ops"), "EM-II, EM-III, EM-IX")


def render(rows: list[Row], stats: dict) -> str:
    L: list[str] = []
    A = L.append
    A("# Volume II Canonical Implementation Matrix")
    A("")
    A("## Status")
    A("")
    A("- Status: Pass A skeleton. Not frozen.")
    A("- Last Updated: 2026-07-17")
    A("- Owner: Chief Architect")
    A(f"- Product-behaviour baseline: `{VOLUME_I_BASELINE}` (frozen Volume I)")
    A(f"- Engineering-practice baseline: `{MANUAL_BASELINE}` (accepted Engineering Manual)")
    A("")
    A("## Authority")
    A("")
    A("This matrix is the controlling source for Pass B. It carries no product authority of")
    A("its own: every row is derived from an accepted Volume I acceptance criterion and cites")
    A("the governing source it came from. Where this matrix and Volume I disagree, Volume I")
    A("prevails and this matrix is defective. Under PM-REQ-003 authority is resolved by scope")
    A("before rank: Volume I owns product behaviour, the Engineering Manual owns engineering")
    A("practice, and Volume II owns product-specific implementation contracts only.")
    A("")
    A("## Derivation")
    A("")
    A("This file is generated by `scripts/build_volume_ii_matrix.py` from the accepted Volume I")
    A("corpus. Coverage is therefore a property of the source rather than of authoring")
    A("diligence: every acceptance criterion in `ACCEPTANCE_AND_TEST_MAPPING.md` becomes exactly")
    A("one row, and every row names the criterion it was derived from. Re-running the generator")
    A("against an unchanged Volume I MUST reproduce this file byte for byte.")
    A("")
    A("Pass B fills the technical contract fields per row. It MUST NOT add a row that no Volume I")
    A("source governs, and MUST NOT remove a row without a controlled Volume I change.")
    A("")
    A("## Contract Fields")
    A("")
    A("A row is `Complete` when its contract is supplied in `specification/volume-ii/contracts/`")
    A("and rendered under Completed Implementation Contracts below. A row is `Pass B required`")
    A("until then. Fields carry exact ownership and behaviour; a field that genuinely does not")
    A("apply carries `Not applicable - <reason>` rather than being left ambiguous.")
    A("")
    for f in CONTRACT_FIELDS:
        A(f"- {FIELD_LABELS[f]}")
    A("")
    A("## Column Meanings")
    A("")
    A("- `Row`: stable matrix row identifier. Rows are never renumbered.")
    A("- `AC`: the governing Volume I acceptance criterion. Exactly one per row.")
    A("- `Source`: the Volume I artefact that owns the criterion.")
    A("- `PR-REQ`: product requirements reaching this row, via the Volume I traceability matrix.")
    A("- `CAP` / `WF` / `PRULE`: governing capability, workflow and product rules.")
    A("- `OD`: owner decisions the row depends on, resolved or pending.")
    A("- `EM`: Engineering Manual volumes governing how the row is built, never what it does.")
    A("- `Slice`: implementation slice. `ALL` marks a cross-cutting rule enforced in every slice.")
    A("- `Tests`: planned verification types from Volume I.")
    A("- `Status`: `Pass B required` until its contract fields are supplied.")
    A("- `Blocker`: a live upstream blocker, or `None`.")
    A("")
    A("## Matrix")
    A("")
    A("| Row | AC | Source | PR-REQ | CAP | WF | PRULE | OD | EM | Slice | Tests | Status | Blocker |")
    A("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for r in rows:
        def j(xs, limit=6):
            xs = list(dict.fromkeys(xs))
            if not xs:
                return "-"
            if len(xs) > limit:
                return f"{xs[0]}..{xs[-1]} ({len(xs)})"
            return ", ".join(xs)
        A("| {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
            r.row_id, r.ac, f"{r.source_kind}: {r.source}", j(getattr(r, "prreqs", [])),
            j(r.caps), j(r.wfs), j(r.prules), j(sorted(set(r.ods)), 8),
            em_for(r.slice_id), r.slice_id, ", ".join(r.test_types) or "-",
            r.status, r.blocker))
    A("")
    completed = [r for r in rows if r.contract]
    if completed:
        A("## Completed Implementation Contracts")
        A("")
        A("Rendered from the canonical contract sources. Do not edit below by hand: this file is")
        A("generated, and `python3 scripts/build_volume_ii_matrix.py --check` fails if it differs")
        A("from what the sources produce.")
        A("")
        for r in completed:
            A(f"### {r.row_id} - {r.ac} ({r.source_kind}: {r.source})")
            A("")
            A(f"- Slice: {r.slice_id}")
            A(f"- Status: {r.status}")
            if r.blocker != "None":
                A(f"- Withheld limb: {r.blocker}")
            for f in CONTRACT_FIELDS:
                if f in r.contract:
                    A(f"- {FIELD_LABELS[f]}: {r.contract[f]}")
            A("")

    A("## Coverage Invariants")
    A("")
    A(f"- Volume I acceptance criteria: {stats['acs']}")
    A(f"- Matrix rows: {stats['rows']}")
    A(f"- Contracts complete: {len(stats['complete'])}")
    A(f"- Rows still `Pass B required`: {len(stats['outstanding'])}")
    A("- Every acceptance criterion maps to exactly one row, by construction.")
    A("- Every row maps back to exactly one governing acceptance criterion and its source.")
    A(f"- Cross-cutting rows (`ALL`): {stats['cross_cutting']}. These are enforced in every slice")
    A("  rather than implemented once, and are verified in each slice's test set.")
    A("- Both invariants are enforced by `scripts/validate_volume_ii.py`, not by review.")
    A("")
    A("## Change Control")
    A("")
    A("Any change to this matrix MUST:")
    A("")
    A("1. cite the governing Volume I source for every affected row;")
    A("2. preserve row identifiers;")
    A("3. keep acceptance-criterion coverage total;")
    A("4. pass `scripts/validate_volume_ii.py` and its negative controls.")
    return "\n".join(L) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate the Volume II implementation matrix")
    ap.add_argument("--check", action="store_true",
                    help="fail if the generated file differs from what the sources produce")
    args = ap.parse_args()

    rows, stats = build()
    rendered = render(rows, stats)
    if stats["unassigned"]:
        print(f"UNASSIGNED slices: {stats['unassigned']}")
        return 1

    if args.check:
        # A hand-edit to the generated matrix is a silent fork from the canonical sources.
        # This makes it loud.
        current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if current != rendered:
            print(f"{OUT.relative_to(ROOT)} differs from its canonical sources; "
                  "it has been hand-edited or is stale. Run the generator.", file=sys.stderr)
            return 1
        print("matrix matches its canonical sources")
        return 0

    OUT.write_text(rendered, encoding="utf-8")
    print(f"rows: {stats['rows']}  complete: {len(stats['complete'])}  "
          f"outstanding: {len(stats['outstanding'])}  withheld: {len(stats['withheld'])}")
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
