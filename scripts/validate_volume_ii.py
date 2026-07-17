#!/usr/bin/env python3
"""Validate Specification Volume II against the accepted baselines.

The Engineering Manual remediation found template-generated product inventions that had
survived review for months: an entity DM-REQ-001 never defined, routes with no governing
workflow, and examples that pre-empted a pending owner decision. Volume II is authored the
same way and is far larger, so the same failure mode is expected here. These checks make it
mechanical.

Scope is the whole repository outside the frozen sources themselves. Volume I, the
foundation and the owner-decision register define the canonical vocabulary and are read as
authority, not linted against it. Restricting these checks to one directory is what let the
manual's inventions survive.

Run: python3 scripts/validate_volume_ii.py [--negative-controls]
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / "specification"
V1 = SPEC / "volume-i"
V2 = SPEC / "volume-ii"

# Wording that looks like a contract and specifies nothing. The Pass B brief names
# "idempotent", "uses locking" and "safe to retry" as inadequate precisely because they
# state a category instead of the key material, the predicate or the outcome.
VAGUE_CONTRACT_VALUE = re.compile(
    r"(?i)^\s*(tbd|to be decided|to be determined|handled by service|standard validation|"
    r"normal authorization|appropriate logging|retry as needed|tests required|existing model|"
    r"as needed|pass b required|idempotent|uses locking|safe to retry|locking|retries|"
    r"version[- ]checked|lock[- ]protected|duplicate[- ]tolerant)\s*\.?\s*$")

# OD-001 is ratified as Option 2: DNS TXT and HTTPS file. Volume I states that other methods
# are blocked, and CAP-005's non-goal is "selection of unapproved verification channels without
# owner decision". A verification method outside this set is an invented product channel with a
# real security surface, so it is rejected mechanically rather than caught in review.
RATIFIED_VERIFICATION_METHODS = {"dns_txt", "http_file"}
CANDIDATE_VERIFICATION_METHOD = re.compile(
    r"`(meta_tag|html_meta|email_verification|email_token|manual_review|manual_verification|"
    r"file_upload|cname|dns_cname|ns_delegation|whois|oauth_domain|tls_alpn)`")
# Naming an unapproved method as a rejection fixture is correct and required: the contract has
# to prove that meta_tag is refused. Only asserting one as usable is the defect.
VERIFICATION_METHOD_REJECTED = re.compile(
    r"(?i)(unsupported_method|rejected|reject|MUST NOT|outside baseline|blocked|not approved|"
    r"out of baseline|are each|denied|refus)")

CURRENT_VOLUME_I_BASELINE = "v1.5-volume-i-frozen"
CURRENT_MANUAL_BASELINE = "v1.7-engineering-manual-accepted"
SUPERSEDED_TAGS = {
    "v1.0-spec-baseline", "v1.1-implementation-ready", "v1.2-volume-i-frozen",
    "v1.3-volume-i-corrected", "v1.4-volume-i-ratified-prelegal",
    "v1.6-engineering-manual-governance-baseline",
}

# Files that define canonical vocabulary. They are authority, so they are not linted
# against themselves, and neither are the historical records that must name superseded
# baselines truthfully.
# Trailing slash matters: "specification/volume-ii/x" startswith "specification/volume-i",
# so a bare string prefix silently excludes the whole of Volume II from every check.
AUTHORITY_SOURCES = {"specification/volume-i/", "specification/011 DOMAIN_MODEL.md"}
HISTORICAL_RECORDS = {"CHANGELOG.md", "DECISIONS.md", "PROJECT_STATE.md", "TODO.md",
                      "VERSION.md", "ROADMAP.md",
                      "engineering/manual/MANUAL_VERSION_HISTORY.md",
                      "engineering/manual/MANUAL_CHANGELOG.md"}


@dataclass(frozen=True)
class Finding:
    path: Path
    line: int | None
    code: str
    message: str

    def format(self, root: Path) -> str:
        try:
            rel = str(self.path.relative_to(root))
        except ValueError:
            rel = str(self.path)
        loc = f"{rel}:{self.line}" if self.line else rel
        return f"{loc}: {self.code}: {self.message}"


def line_of(text: str, needle: str) -> int | None:
    for i, line in enumerate(text.splitlines(), 1):
        if needle in line:
            return i
    return None


# --- canonical vocabulary, read from the frozen sources ----------------------

def canonical_entities(root: Path) -> set[str]:
    dm = (root / "specification" / "011 DOMAIN_MODEL.md").read_text(encoding="utf-8")
    m = re.search(r"DM-REQ-001:.*?MUST include (.*?)\.\s*\n", dm, re.S)
    if not m:
        return set()
    raw = re.split(r",\s*|\s+and\s+", m.group(1))
    return {e.strip().rstrip(".") for e in raw if e.strip() and e.strip()[0].isupper()}


EVENT_SUFFIXES = (
    "Created|Activated|Completed|Failed|Started|Issued|Expired|Revoked|Suspended|Reactivated|"
    "Deleted|Assigned|Granted|Changed|Requested|Consumed|Resolved|Disputed|Adjudicated|"
    "Superseded|Published|Canceled|Cancelled|Closed|Evaluated|Promoted|Withdrawn|Released|"
    "Rejected|Approved|Decided|Blocked|Recorded|Validated|Destroyed|Provisioned|Terminated|"
    "Invalidated|Escalated|Sealed|Delivered|Detected|Indexed|Parsed|Ingested|Discovered|"
    "Generated|Retired|Triggered|Quarantined|Acknowledged|Reopened|Restored|Attempted"
)
EVENT_CORE = rf"[A-Z][A-Za-z]{{3,}}(?:{EVENT_SUFFIXES})"
EVENT_RE = re.compile(rf"\b({EVENT_CORE})\b")
EVENT_BACKTICKED_RE = re.compile(rf"`({EVENT_CORE})`")


def authority_text(root: Path) -> str:
    """The full canonical vocabulary: foundation 000-020 plus frozen Volume I.

    Reading only 016 STATE_MODEL.md misses 73 of the 157 canonical event names -- for
    example BootstrapGrantIssued, which WF-001 emits and which lives in
    WORKFLOW_SPECIFICATIONS.md. A check built on a partial vocabulary reports canonical
    names as inventions, which is worse than no check: it trains the reader to ignore it.
    """
    srcs = sorted((root / "specification").glob("0*.md")) + \
           sorted((root / "specification" / "volume-i").glob("*.md"))
    return "\n".join(p.read_text(encoding="utf-8") for p in srcs)


def canonical_events(root: Path) -> set[str]:
    return set(EVENT_RE.findall(authority_text(root)))


def canonical_permissions(root: Path) -> set[str]:
    perms = set(re.findall(r"`([a-z_]+(?:\.[a-z_]+)+)`", authority_text(root)))
    return {p for p in perms if not p.endswith((".md", ".rb", ".py", ".yml", ".json", ".csv", ".txt"))}


def permission_namespaces(root: Path) -> set[str]:
    """First segments of the canonical permission vocabulary.

    A dotted token is only judged as a permission when it sits in a namespace Volume I
    actually uses. Without this, `issues.csv`, `meta.page_size`, `scheduled_actions.id`
    and the Postgres GUC `app.organization_id` are all reported as invented permissions.
    """
    return {p.split(".")[0] for p in canonical_permissions(root)}


def acceptance_criteria(root: Path) -> set[str]:
    t = (root / "specification" / "volume-i" / "ACCEPTANCE_AND_TEST_MAPPING.md").read_text(encoding="utf-8")
    return set(re.findall(r"^\|\s*(AC-[A-Z]+-\d{3})\s*\|", t, re.M))


# --- checks ------------------------------------------------------------------

# Code-shaped assertions of a limb a pending owner decision reserves. Prose that cites the
# deferral is not code and cannot match.
PENDING_OD_PREEMPTION = {
    re.compile(r"\bproject\.(archive|pause|resume)\b"):
        "OD-014 (UPSTREAM-V1-PROJECT-LIFECYCLE-003) reserves Project pause/resume/archive",
    re.compile(r"\bProject#(archive|pause|resume)\b"):
        "OD-014 (UPSTREAM-V1-PROJECT-LIFECYCLE-003) reserves Project pause/resume/archive",
    re.compile(r"\b(Archive|Pause|Resume)Project\b"):
        "OD-014 (UPSTREAM-V1-PROJECT-LIFECYCLE-003) reserves Project pause/resume/archive",
    re.compile(r"\b(archive|pause|resume)_project\b"):
        "OD-014 (UPSTREAM-V1-PROJECT-LIFECYCLE-003) reserves Project pause/resume/archive",
}
NONCANONICAL_SPELLING = re.compile(r"(?<!\w)Organisation\w*")
ROUTE_RE = re.compile(r"\b(GET|POST|PUT|PATCH|DELETE)\s+(/[A-Za-z0-9_{}:/-]*)")
# Volume II owns implementation contracts, so it may name routes -- but only where a
# governing workflow or capability is cited in the same document.
GOVERNANCE_CITE = re.compile(r"\b(WF-\d{3}|CAP-\d{3}|QRY-\d{3}|PRULE-\d{3})\b")
HISTORICAL_MENTION = re.compile(r"(?i)\b(historical|superseded|retained|predecessor|established by|no longer|prior|previous|was frozen|history)\b")
# First path segments naming an F1 product resource.
PRODUCT_ROUTE_SEGMENTS = {"assessments", "projects", "sessions", "evaluations", "issues",
                          "organizations", "organisations", "accounts", "sources", "documents",
                          "crawls", "exports", "credentials", "integrations", "recommendations",
                          "reports", "notifications", "billing", "invitations", "roles"}


def in_scope(path: Path, root: Path) -> bool:
    rel = path.relative_to(root).as_posix()
    if any(rel == a or rel.startswith(a) for a in AUTHORITY_SOURCES):
        return False
    if rel in HISTORICAL_RECORDS:
        return False
    if rel.startswith("scripts/") or rel.startswith(".git"):
        return False
    return True


def validate(root: Path) -> list[Finding]:
    findings: list[Finding] = []
    entities = canonical_entities(root)
    events = canonical_events(root)
    perms = canonical_permissions(root)
    acs = acceptance_criteria(root)

    matrix_path = root / "specification" / "volume-ii" / "IMPLEMENTATION_MATRIX.md"

    for path in sorted(root.rglob("*.md")):
        if ".git" in path.parts or not in_scope(path, root):
            continue
        text = path.read_text(encoding="utf-8")

        # 1. an entity absent from Volume I
        for m in re.finditer(r"(?<!\w)Assessment\w*", text):
            before = text[max(0, m.start() - 30):m.start()]
            if re.search(r"(?i)\b(risk|debt|compatibility|architectural|security|readiness|impact|maturity|self)\s+$", before):
                continue
            findings.append(Finding(path, line_of(text, m.group(0)), "entity_absent_from_volume_i",
                                    f"{m.group(0)}: DM-REQ-001 defines no such entity"))

        # 2. a product route with no governing workflow or obligation
        if not GOVERNANCE_CITE.search(text):
            for m in ROUTE_RE.finditer(text):
                segment = m.group(2).lstrip("/").split("/")[0].split("{")[0].strip("-_")
                if segment in PRODUCT_ROUTE_SEGMENTS:
                    findings.append(Finding(path, line_of(text, m.group(0)),
                                            "route_without_governing_obligation",
                                            f"{m.group(0)}: names an F1 resource with no WF/CAP/QRY/PRULE cited"))

        # 6. a contract that pre-empts a pending owner decision
        for pattern, reason in PENDING_OD_PREEMPTION.items():
            m = pattern.search(text)
            if m:
                findings.append(Finding(path, line_of(text, m.group(0)), "pending_od_preemption",
                                        f"{m.group(0)}: {reason}"))

        # unauthorized verification method (OD-001 ratifies dns_txt and http_file only)
        for m in CANDIDATE_VERIFICATION_METHOD.finditer(text):
            method = m.group(1)
            window = text[max(0, m.start() - 220):m.end() + 220]
            if VERIFICATION_METHOD_REJECTED.search(window):
                continue
            if method not in RATIFIED_VERIFICATION_METHODS:
                findings.append(Finding(path, line_of(text, m.group(0)), "unauthorized_verification_method",
                                        f"{method}: OD-001 ratifies dns_txt and http_file only; "
                                        "other methods are outside baseline scope"))

        # 7. non-canonical Organization terminology
        for m in NONCANONICAL_SPELLING.finditer(text):
            findings.append(Finding(path, line_of(text, m.group(0)), "noncanonical_organization_terminology",
                                    f"{m.group(0)}: the canonical spelling is Organization"))

        # 8. stale authority tags
        for tag in SUPERSEDED_TAGS:
            for i, line in enumerate(text.splitlines(), 1):
                if tag not in line:
                    continue
                # Naming a superseded tag as history is correct and required; naming it as
                # the current baseline is the defect.
                if HISTORICAL_MENTION.search(line):
                    continue
                current = (CURRENT_MANUAL_BASELINE if "manual" in tag else CURRENT_VOLUME_I_BASELINE)
                findings.append(Finding(path, i, "stale_authority_tag",
                                        f"{tag} cited as current authority; the current baseline is {current}"))

    # 3/4/5. invented events, permissions and state transitions, inside Volume II only
    namespaces = permission_namespaces(root)
    for path in sorted((root / "specification" / "volume-ii").glob("*.md")):
        text = path.read_text(encoding="utf-8")
        for m in EVENT_BACKTICKED_RE.finditer(text):
            name = m.group(1)
            if name not in events:
                findings.append(Finding(path, line_of(text, name), "event_absent_from_canonical_model",
                                        f"{name}: no such event in the foundation or Volume I"))
        for m in re.finditer(r"`([a-z_]+\.[a-z_.]+)`", text):
            tok = m.group(1)
            if tok.endswith((".md", ".rb", ".py", ".yml", ".json", ".txt", ".csv")):
                continue
            # Only a token in a canonical permission namespace is judged as a permission.
            if tok.split(".")[0] not in namespaces:
                continue
            if re.match(r"^[a-z_]+\.[a-z_]+(\.[a-z_]+)?$", tok) and tok not in perms:
                findings.append(Finding(path, line_of(text, tok), "permission_absent_from_model",
                                        f"{tok}: not in the Volume I permission model"))

    findings.extend(validate_pass_b_contracts(root))

    # 9. an AC with no matrix row / 10. a matrix row with no governing source
    if matrix_path.exists():
        mtext = matrix_path.read_text(encoding="utf-8")
        rows = re.findall(r"^\|\s*(MTX-\d{3})\s*\|\s*(AC-[A-Z]+-\d{3})\s*\|\s*([^|]+?)\s*\|", mtext, re.M)
        mapped = {ac for _, ac, _ in rows}
        for ac in sorted(acs - mapped):
            findings.append(Finding(matrix_path, None, "acceptance_criterion_without_matrix_row",
                                    f"{ac} has no matrix row"))
        for row_id, ac, source in rows:
            if ac not in acs:
                findings.append(Finding(matrix_path, None, "matrix_row_without_governing_source",
                                        f"{row_id} cites {ac}, which Volume I does not define"))
            if not source.strip() or source.strip() == "-":
                findings.append(Finding(matrix_path, None, "matrix_row_without_governing_source",
                                        f"{row_id} names no governing source"))
    return findings


def validate_pass_b_contracts(root: Path) -> list[Finding]:
    """Enforce that a completed contract is actually complete and actually owned.

    A row is only complete when its structured contract exists, names a canonical owner
    document, and that owner exists and cites the row back. Without the back-citation a
    contract can point at a document that never claims it, which reads as complete and
    is not.
    """
    import json as _json
    findings: list[Finding] = []
    contracts_dir = root / "specification" / "volume-ii" / "contracts"
    if not contracts_dir.exists():
        return findings

    # Mutations required by the Pass B brief for any state-changing contract.
    REQUIRED = ["idempotency", "concurrency", "authorization_entry_point", "permission_checks",
                "tenant_boundary", "error_contract", "audit_record", "observability",
                "test_contracts", "contract_owner"]

    for path in sorted(contracts_dir.glob("*.json")):
        data = _json.loads(path.read_text(encoding="utf-8"))
        for row_id, fields in sorted(data.get("rows", {}).items()):
            for req in REQUIRED:
                if req not in fields:
                    findings.append(Finding(path, None, "contract_missing_required_field",
                                            f"{row_id} has no {req}"))
            for name, value in sorted(fields.items()):
                if VAGUE_CONTRACT_VALUE.match(str(value)):
                    findings.append(Finding(path, None, "contract_field_vague",
                                            f"{row_id}.{name} asserts nothing: {value!r}"))
                if str(value).lower().startswith("not applicable") and "-" not in str(value):
                    findings.append(Finding(path, None, "not_applicable_without_reason",
                                            f"{row_id}.{name} is Not applicable with no reason"))

            owner = fields.get("contract_owner", "")
            if owner:
                doc = owner.split("#", 1)[0]
                owner_path = root / doc
                if not owner_path.exists():
                    findings.append(Finding(path, None, "contract_owner_missing",
                                            f"{row_id} names {doc}, which does not exist"))
                elif row_id not in owner_path.read_text(encoding="utf-8"):
                    findings.append(Finding(owner_path, None, "contract_owner_does_not_cite_row",
                                            f"{row_id} names this document as owner, but it does not cite {row_id}"))
    return findings


# --- negative controls -------------------------------------------------------

def append(path: Path, text: str) -> None:
    path.write_text(path.read_text(encoding="utf-8") + text, encoding="utf-8")


def drop_matrix_row(root: Path) -> None:
    p = root / "specification" / "volume-ii" / "IMPLEMENTATION_MATRIX.md"
    lines = [l for l in p.read_text(encoding="utf-8").splitlines() if not l.startswith("| MTX-001 |")]
    p.write_text("\n".join(lines) + "\n", encoding="utf-8")


def blank_matrix_source(root: Path) -> None:
    p = root / "specification" / "volume-ii" / "IMPLEMENTATION_MATRIX.md"
    t = p.read_text(encoding="utf-8")
    t = re.sub(r"^\| (MTX-002) \| (AC-[A-Z]+-\d{3}) \| [^|]+ \|", r"| \1 | \2 | - |", t, count=1, flags=re.M)
    p.write_text(t, encoding="utf-8")


def _contract_file(root: Path) -> Path:
    return root / "specification" / "volume-ii" / "contracts" / "S-01.json"


def drop_contract_field(root: Path) -> None:
    import json as _json
    p = _contract_file(root)
    data = _json.loads(p.read_text(encoding="utf-8"))
    data["rows"]["MTX-026"].pop("idempotency", None)
    p.write_text(_json.dumps(data, indent=2), encoding="utf-8")


def vague_contract_field(root: Path) -> None:
    import json as _json
    p = _contract_file(root)
    data = _json.loads(p.read_text(encoding="utf-8"))
    data["rows"]["MTX-026"]["concurrency"] = "uses locking"
    p.write_text(_json.dumps(data, indent=2), encoding="utf-8")


def break_owner_citation(root: Path) -> None:
    owner = root / "specification" / "volume-ii" / "APPLICATION_LAYER.md"
    owner.write_text(owner.read_text(encoding="utf-8").replace("MTX-026", "MTX-XXX"), encoding="utf-8")


def run_negative_controls() -> int:
    cases = [
        ("entity absent from Volume I",
         lambda r: append(r / "specification" / "volume-ii" / "AI_EVALUATION.md",
                          "\nThe Assessment aggregate owns evaluation state.\n"),
         "entity_absent_from_volume_i"),
        ("route without governing obligation",
         lambda r: (r / "specification" / "volume-ii" / "PASSA_CONTROL.md").write_text(
             "# Control\n\nPOST /projects/{id}/archive\n", encoding="utf-8"),
         "route_without_governing_obligation"),
        ("event absent from canonical model",
         lambda r: append(r / "specification" / "volume-ii" / "AI_EVALUATION.md",
                          "\nThe pipeline emits `AssessmentGenerated` on completion.\n"),
         "event_absent_from_canonical_model"),
        ("permission absent from model",
         lambda r: append(r / "specification" / "volume-ii" / "SECURITY_PERFORMANCE.md",
                          "\nThe route requires `project.teleport`.\n"),
         "permission_absent_from_model"),
        ("pending OD pre-emption",
         lambda r: append(r / "specification" / "volume-ii" / "APPLICATION_LAYER.md",
                          "\n`project.archive!` completes the transition.\n"),
         "pending_od_preemption"),
        ("non-canonical Organization terminology",
         lambda r: append(r / "specification" / "volume-ii" / "FRONTEND_ARCHITECTURE.md",
                          "\nAn Organisation owns its tenant boundary.\n"),
         "noncanonical_organization_terminology"),
        ("stale authority tag",
         lambda r: append(r / "specification" / "volume-ii" / "INDEX.md",
                          "\nChecked against `v1.3-volume-i-corrected`.\n"),
         "stale_authority_tag"),
        ("acceptance criterion without matrix row", drop_matrix_row,
         "acceptance_criterion_without_matrix_row"),
        ("matrix row without governing source", blank_matrix_source,
         "matrix_row_without_governing_source"),
        ("contract missing required field", drop_contract_field,
         "contract_missing_required_field"),
        ("contract field vague", vague_contract_field,
         "contract_field_vague"),
        ("contract owner does not cite row", break_owner_citation,
         "contract_owner_does_not_cite_row"),
        ("unauthorized verification method",
         lambda r: append(r / "specification" / "volume-ii" / "SECURITY_PERFORMANCE.md",
                          "\nOwnership may also be proved by `meta_tag` placement.\n"),
         "unauthorized_verification_method"),
    ]
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="f1-v2-negative-") as tmp:
        base = Path(tmp) / "repo"
        base.mkdir()
        for sub in ["specification"]:
            shutil.copytree(ROOT / sub, base / sub, ignore=shutil.ignore_patterns(".DS_Store"))
        for label, mutate, expected in cases:
            case = Path(tmp) / label.replace(" ", "-")
            shutil.copytree(base, case)
            mutate(case)
            codes = {f.code for f in validate(case)}
            if expected not in codes:
                failures.append(f"{label}: expected {expected}, observed {sorted(codes)}")
            shutil.rmtree(case)
    if failures:
        for f in failures:
            print(f, file=sys.stderr)
        return 1
    print(f"Negative controls passed ({len(cases)} controls)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Validate Specification Volume II")
    ap.add_argument("--negative-controls", action="store_true")
    args = ap.parse_args()
    if args.negative_controls:
        return run_negative_controls()
    findings = validate(ROOT)
    if findings:
        for f in findings:
            print(f.format(ROOT))
        print(f"Validation failed with {len(findings)} finding(s)", file=sys.stderr)
        return 1
    print("Volume II validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
