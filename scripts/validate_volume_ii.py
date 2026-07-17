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
from urllib.parse import unquote
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
# Owner Decision status is resolved from the register's own `Current Status` field and from
# nowhere else. Continuation 003 was briefed on the premise that OD-001 was pending, because
# PRULE-005, PRULE-020 and the evidence-contract preamble still call its method set an
# "interim" -- prose written before ratification and never updated. The register says
# "Ratified ... Blocking Impact: None". Deriving status from incidental wording would have
# withheld behaviour the owner approved, which is the mirror image of pre-empting an open
# decision. These checks make the register controlling and executable.
DECISION_STATUS_PENDING = re.compile(r"(?i)^\s*pending\b")
DECISION_STATUS_SETTLED = re.compile(r"(?i)^\s*(ratified|resolved|withdrawn|superseded|retired)\b")

# OD-027 feature-blocks exactly three artifacts until approval: a has_one narrowing, a
# unique (parsing_job_id) constraint, and any second IndexingJob per ParsingJob. Contracting
# any of them as settled would resolve a pending decision by implementation; the limb is
# withheld, not undecided-but-probably-fine.
OD_027_WITHHELD_ARTIFACT = re.compile(
    r"(?i)(unique\s*\(\s*parsing_job_id\s*\)|has_one\s+:?indexing_job|"
    r"second\s+IndexingJob\s+per\s+ParsingJob)")
# Naming the artifact to withhold it is the correct contract; naming it without citing the
# decision that blocks it is the defect. A proximity window was tried first and proved
# untrustworthy: an unrelated "blocked" 218 characters away in neighbouring prose exempted a
# real violation. Requiring the document to cite OD-027 is precise and has no such accident.
OD_027_CITATION = re.compile(r"\bOD-027\b")

# The unit that binds a withholding phrase to the tag it withholds against, and a rejection to the
# method it rejects. Splitting on the sentence terminator and the table-cell separator is
# STRUCTURAL: a sentence binds a subject to its predicate, and a cell is that same unit inside a
# row. It is emphatically not a character-proximity window. A window of any width silently exempts a
# real violation whenever unrelated prose falls inside it -- an unrelated "blocked" 218 characters
# away already exempted a real OD-027 violation, and a rejection of an unrelated subject already
# disabled the verification-method check for a whole document tail. A sentence boundary is a
# property of the text; a window width is a number this checker made up.
#
# Line scoping was correct when written and is no longer sufficient. IMPLEMENTATION_MATRIX.md is
# generated and renders a whole contract field as one physical line of several thousand characters,
# so a `deferred under` in one sentence collides with a tag named in another sentence that states
# the opposite -- "OD-020 ratifies the authority, `UPSTREAM-V1-READ-AUTHORIZATION-004` is retired".
# Deleting that sentence to satisfy the checker would destroy the truth to protect the test.
SEGMENT_SPLIT = re.compile(r"(?<=\.)\s+|\s*\|\s*")

RATIFIED_VERIFICATION_METHODS = {"dns_txt", "http_file"}
CANDIDATE_VERIFICATION_METHOD = re.compile(
    r"`(meta_tag|html_meta|email_verification|email_token|manual_review|manual_verification|"
    r"file_upload|cname|dns_cname|ns_delegation|whois|oauth_domain|tls_alpn)`")
# Naming an unapproved method as a rejection fixture is correct and required: the contract has
# to prove that meta_tag is refused. Only asserting one as usable is the defect.
#
# Matched against the method's own line, never a surrounding character window. A window is
# unsound here: any neighbouring prose that happens to reject something *else* silently exempts
# a real violation. That is not hypothetical -- integrating S-12's PRULE-023 fragment, which
# ends by rejecting a reused fingerprint version, disabled this check for the whole tail of
# SECURITY_PERFORMANCE.md until the negative control caught it. The rejection must be asserted
# about the method itself, on the same line.
VERIFICATION_METHOD_REJECTED = re.compile(
    r"(?i)(unsupported_method|outside baseline|out of baseline|not approved|not accepted|"
    r"MUST NOT|are each|rejected as|refused|denied)")

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
# Pass B slice fragments are integration INPUTS, not published documents. `integrate_fragments.py`
# merges each section into the canonical owner named by its contract, and their links are authored
# in the OWNER's frame of reference -- `APPLICATION_LAYER.md#...` resolves once merged and cannot
# resolve from `fragments/`. Linting them where they sit reports the integrator's own convention as
# a defect. This is a structural exemption of one directory whose contents are provably already
# merged (`integrate_fragments.py --check` reports 0 pending), not a pattern that could mask a
# defect in a published document.
INTEGRATION_INPUTS = "specification/volume-ii/fragments/"
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
# An upstream blocker tag withholds behaviour. Once its Owner Decision is ratified the tag is
# retired, and citing it as a live reason withholds behaviour the owner has approved -- the
# mirror image of pre-empting an open decision, and just as wrong. INDEX.md's registry is the
# status authority; these are the phrasings that make a citation a live withholding.
RETIRED_BLOCKER_USE = re.compile(
    r"(?i)\b(deferred under|deferred pending|disabled by|blocked by|blocked mappings?|"
    r"remains? deferred|remains? blocked|unreachable until|withheld under|not routable)\b")
# A line that states the tag's retirement is a status record, not a live citation.
BLOCKER_STATUS_STATEMENT = re.compile(r"(?i)(retired under|status:\s*resolved|resolved by ADR|"
                                      r"\bLIVE\b|removes? .{0,40}under ADR)")
BLOCKER_REGISTRY_ROW = re.compile(
    r"^\|\s*`(UPSTREAM-[A-Z0-9-]+)`\s*\|\s*(OD-\d{3})\s*\|\s*(.+?)\s*\|\s*$")
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
    if rel in HISTORICAL_RECORDS or rel.startswith(INTEGRATION_INPUTS):
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
        #
        # Scoped to the structural segment naming the method, not the whole line. The original
        # defect here was a character-proximity window, which S-12's PRULE-023 fragment defeated by
        # ending with a rejection of a reused fingerprint version -- disabling the check for the
        # whole tail of SECURITY_PERFORMANCE.md until a negative control caught it. Line scoping
        # narrowed that failure without closing it: a single line that asserts `meta_tag` as usable
        # AND rejects something unrelated still exempts a real violation. The rejection must be
        # asserted about the method itself, in the same sentence or cell.
        for i, line in enumerate(text.splitlines(), 1):
            for segment in SEGMENT_SPLIT.split(line):
                if VERIFICATION_METHOD_REJECTED.search(segment):
                    continue  # this segment rejects the method it names; the required fixture
                for m in CANDIDATE_VERIFICATION_METHOD.finditer(segment):
                    method = m.group(1)
                    if method not in RATIFIED_VERIFICATION_METHODS:
                        findings.append(Finding(path, i, "unauthorized_verification_method",
                                                f"{method}: OD-001 ratifies dns_txt and http_file only; "
                                                "other methods are outside baseline scope"))

        # OD-027 withheld limb contracted as settled
        if OD_027_WITHHELD_ARTIFACT.search(text) and not OD_027_CITATION.search(text):
            m = OD_027_WITHHELD_ARTIFACT.search(text)
            findings.append(Finding(path, line_of(text, m.group(0)), "withheld_limb_contracted_as_settled",
                                    f"{m.group(0).strip()}: OD-027 feature-blocks this until approval; "
                                    "it may be named as withheld, never contracted as settled"))

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
    findings.extend(validate_decision_status(root))
    findings.extend(validate_retired_blockers(root))
    findings.extend(validate_successor_decisions(root))
    findings.extend(validate_anchors(root))

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


def owner_decision_status(root: Path) -> dict[str, dict]:
    """Read each decision's canonical status from the register's own `Current Status` field.

    Deliberately does NOT look at requirement prose. A rule that says "interim" does not make
    its decision pending, and a rule that omits the word does not make it ratified.
    """
    text = (root / "specification" / "volume-i" / "OWNER_DECISION_REGISTER.md").read_text(encoding="utf-8")
    parts = re.split(r"\n### (OD-\d{3})[^\n]*\n", text)
    out: dict[str, dict] = {}
    for i in range(1, len(parts), 2):
        od, body = parts[i], parts[i + 1]
        m = re.search(r"^- Current Status:\s*(.+)$", body, re.M)
        status = m.group(1).strip() if m else ""
        out[od] = {
            "status": status,
            "pending": bool(DECISION_STATUS_PENDING.match(status)),
            "settled": bool(DECISION_STATUS_SETTLED.match(status)),
        }
    return out


def validate_decision_status(root: Path) -> list[Finding]:
    """A row's withholding must match its decisions' canonical register status.

    This re-derives the classification independently of the generator, so a defect in either
    one is caught by disagreement with the other rather than by both being wrong together.
    """
    findings: list[Finding] = []
    matrix = root / "specification" / "volume-ii" / "IMPLEMENTATION_MATRIX.md"
    if not matrix.exists():
        return findings
    decisions = owner_decision_status(root)

    register = (root / "specification" / "volume-i" / "OWNER_DECISION_REGISTER.md").read_text(encoding="utf-8")
    affected: dict[str, list[str]] = {}
    parts = re.split(r"\n### (OD-\d{3})[^\n]*\n", register)
    for i in range(1, len(parts), 2):
        od, body = parts[i], parts[i + 1]
        m = re.search(r"^- Affected Acceptance Criteria:\s*(.+)$", body, re.M)
        if m:
            for ac in re.findall(r"AC-[A-Z]+-\d{3}", m.group(1)):
                affected.setdefault(ac, []).append(od)

    for od, meta in sorted(decisions.items()):
        if not meta["pending"] and not meta["settled"]:
            findings.append(Finding(
                root / "specification" / "volume-i" / "OWNER_DECISION_REGISTER.md", None,
                "decision_status_unrecognized",
                f"{od}: Current Status {meta['status'][:60]!r} matches no known status vocabulary; "
                "status must be explicit rather than inferred"))

    for line in matrix.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\|\s*(MTX-\d{3})\s*\|\s*(AC-[A-Z]+-\d{3})\s*\|", line)
        if not m:
            continue
        cells = [c.strip() for c in line.split("|")]
        if len(cells) < 14:
            continue
        row_id, ac, status_cell = m.group(1), m.group(2), cells[12]
        row_ods = affected.get(ac, [])
        pending = [od for od in row_ods if decisions.get(od, {}).get("pending")]
        withheld = "withheld" in status_cell.lower()

        if pending and not withheld:
            findings.append(Finding(matrix, None, "pending_decision_treated_as_ratified",
                                    f"{row_id} depends on pending {', '.join(pending)} but is not marked withheld"))
        if withheld and not pending:
            findings.append(Finding(matrix, None, "ratified_decision_treated_as_pending",
                                    f"{row_id} is marked withheld but none of its decisions "
                                    f"({', '.join(row_ods) or 'none'}) is pending in the register"))
    return findings


def retired_blockers(root: Path) -> dict[str, str]:
    """Map each upstream blocker tag to its status, from INDEX.md's registry table.

    INDEX.md is the status authority for Volume II blocker tags, exactly as each decision's
    `Current Status` field is the status authority for Owner Decisions. Prose elsewhere is not
    a status source.
    """
    index = root / "specification" / "volume-ii" / "INDEX.md"
    if not index.exists():
        return {}
    statuses: dict[str, str] = {}
    for line in index.read_text(encoding="utf-8").splitlines():
        m = BLOCKER_REGISTRY_ROW.match(line)
        if m:
            statuses[m.group(1)] = m.group(3)
    return {tag: st for tag, st in statuses.items()
            if not re.search(r"(?i)\bLIVE\b", st) and re.search(r"(?i)retired|resolved", st)}




def validate_retired_blockers(root: Path) -> list[Finding]:
    """A retired blocker tag must not be cited as a live reason to withhold behaviour.

    Naming a retired tag is legitimate and required -- the correction packages record what each
    blocker was and how it resolved. The defect is naming it as the *reason* a capability is
    deferred, disabled or unroutable, because a reader who trusts that withholds behaviour the
    owner ratified.

    Scope is the whole in-scope corpus, not one directory. `schemas/POSTGRESQL_SCHEMA.md` cited
    retired tags as live reasons to refuse a DML grant and was never scanned, because this check
    globbed `specification/volume-ii/*.md` while every other check in this file uses `in_scope`.
    A rule that is right about a defect and blind to where it lives is not a rule.
    """
    findings: list[Finding] = []
    retired = retired_blockers(root)
    if not retired:
        return findings
    for path in sorted(root.rglob("*.md")):
        if ".git" in path.parts or not in_scope(path, root):
            continue
        for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for segment in SEGMENT_SPLIT.split(line):
                if BLOCKER_STATUS_STATEMENT.search(segment):
                    continue  # states the tag's status; not a live citation
                use = RETIRED_BLOCKER_USE.search(segment)
                if not use:
                    continue
                for tag, status in retired.items():
                    if tag in segment:
                        findings.append(Finding(
                            path, i, "retired_blocker_cited_as_live",
                            f"{tag} is '{status}' per INDEX.md, but is cited here as "
                            f"'{use.group(0)}'; a retired blocker withholds nothing"))
    return findings


# A settled decision that hands a required policy question to a successor must name a successor
# that exists. OD-020 was ratified with "remain deny-by-default pending a separate decision" and
# no such decision was ever registered, so for months the affected rows could neither withhold
# against it nor implement it, and their citations drifted onto a retired blocker tag instead.
# That is the defect this rule exists to make impossible to repeat.
DELEGATES_TO_SUCCESSOR = re.compile(r"(?i)pending a (separate|further|subsequent) (owner )?decision")
# The link is explicit and machine-readable rather than inferred from prose. A successor that has
# to be recognised by wording is a successor that can be missed by wording.
SUCCESSOR_TO = re.compile(r"^- Successor To:\s*(OD-\d{3})\s*$", re.M)
# Only a decision's own normative fields delegate. Quoting a delegation while analysing it -- which
# every successor decision necessarily does -- is not itself a delegation.
NORMATIVE_FIELDS = ("Ratified Behavior", "Resolved Behavior", "Approved Option", "Resolved Option",
                    "Blocking Impact")


def validate_successor_decisions(root: Path) -> list[Finding]:
    """Every delegated policy question must have a registered node to be delegated to."""
    register = root / "specification" / "volume-i" / "OWNER_DECISION_REGISTER.md"
    if not register.exists():
        return []
    text = register.read_text(encoding="utf-8")
    parts = re.split(r"\n### (OD-\d{3})[^\n]*\n", text)
    bodies = {parts[i]: parts[i + 1] for i in range(1, len(parts), 2)}

    successors: set[str] = set()
    for body in bodies.values():
        successors.update(SUCCESSOR_TO.findall(body))

    findings: list[Finding] = []
    decisions = owner_decision_status(root)
    for od, body in sorted(bodies.items()):
        if decisions.get(od, {}).get("pending"):
            continue  # an open decision delegates nothing; it is the open question
        for label in NORMATIVE_FIELDS:
            m = re.search(rf"^- {label}:\s*(.+)$", body, re.M)
            if not m or not DELEGATES_TO_SUCCESSOR.search(m.group(1)):
                continue
            if od not in successors:
                findings.append(Finding(
                    register, None, "unresolved_successor_decision",
                    f"{od} delegates a required policy question to a separate decision in its "
                    f"{label}, but no registered decision names '- Successor To: {od}'; the "
                    "affected rows can neither withhold against it nor implement it"))
            break
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


# --- anchor integrity ------------------------------------------------------

# GitHub's heading anchor, matching `scripts/integrate_fragments.py#slug` exactly. The two must
# agree: the integrator routes a fragment section by looking its title's slug up among the declared
# `contract_owner` anchors, so a different slug here would validate links the integrator cannot
# resolve.
MD_LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
ATX_HEADING = re.compile(r"^#{1,6}\s+(.*?)\s*#*$")
FENCE = re.compile(r"^\s*(```|~~~)")


def slug(title: str) -> str:
    s = re.sub(r"[^a-z0-9 \-]", "", title.strip().lower())
    return re.sub(r"\s+", "-", s).strip("-")


def heading_slugs(path: Path) -> set[str]:
    """Slugs a Markdown renderer would actually generate for this file.

    Only ATX headings count. Text that merely looks like a heading -- a `#` inside a fenced code
    block, or a table cell naming a section -- generates no anchor, and treating it as one would
    make this check pass for links that are broken in a browser. Duplicate headings take GitHub's
    `-1`, `-2` suffixes.
    """
    out: set[str] = set()
    seen: dict[str, int] = {}
    in_fence = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = ATX_HEADING.match(line)
        if not m:
            continue
        base = slug(re.sub(r"`|\*\*|\*|_", "", m.group(1)))
        if not base:
            continue
        n = seen.get(base, 0)
        seen[base] = n + 1
        out.add(base if n == 0 else f"{base}-{n}")
    return out


def validate_anchors(root: Path) -> list[Finding]:
    """Every local and cross-document Markdown anchor must resolve to a real heading.

    A dead anchor is not cosmetic here: `contract_owner` names a document and an anchor, and the
    whole completeness argument is that a row's contract points at the section that claims it. An
    anchor that silently lands at the top of the file makes a broken cross-reference look answered.
    """
    findings: list[Finding] = []
    cache: dict[Path, set[str]] = {}

    def slugs_of(p: Path) -> set[str]:
        if p not in cache:
            cache[p] = heading_slugs(p)
        return cache[p]

    for path in sorted(root.rglob("*.md")):
        if ".git" in path.parts or not in_scope(path, root):
            continue
        text = path.read_text(encoding="utf-8")
        for i, line in enumerate(text.splitlines(), 1):
            for target in MD_LINK.findall(line):
                if target.startswith(("http://", "https://", "mailto:")) or "#" not in target:
                    continue
                doc, _, frag = target.partition("#")
                if not frag:
                    continue
                if doc:
                    ref = (path.parent / unquote(doc)).resolve()
                    if ref.suffix != ".md":
                        continue
                    if not ref.exists():
                        findings.append(Finding(path, i, "anchor_target_missing",
                                                f"{target}: {doc} does not exist"))
                        continue
                else:
                    ref = path
                if unquote(frag).lower() not in slugs_of(ref):
                    findings.append(Finding(path, i, "anchor_target_missing",
                                            f"{target}: no heading in "
                                            f"{ref.name} generates the anchor '{frag}'"))
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


def _register(root: Path) -> Path:
    return root / "specification" / "volume-i" / "OWNER_DECISION_REGISTER.md"


def mark_od_001_pending(root: Path) -> None:
    """OD-001 is ratified. If the register said pending, every S-05 row would be misclassified."""
    p = _register(root)
    t = p.read_text(encoding="utf-8")
    parts = t.split("### OD-001 ", 1)
    head, body = parts[0], parts[1]
    body = re.sub(r"^- Current Status:.*$", "- Current Status: Pending owner approval",
                  body, count=1, flags=re.M)
    p.write_text(head + "### OD-001 " + body, encoding="utf-8")


def mark_od_014_ratified(root: Path) -> None:
    """OD-014 is pending. If the register said ratified, MTX-003's withholding would be wrong."""
    p = _register(root)
    t = p.read_text(encoding="utf-8")
    parts = t.split("### OD-014 ", 1)
    head, body = parts[0], parts[1]
    body = re.sub(r"^- Current Status:.*$", "- Current Status: Ratified on 2026-07-17 as specified",
                  body, count=1, flags=re.M)
    p.write_text(head + "### OD-014 " + body, encoding="utf-8")


def corrupt_od_status_vocabulary(root: Path) -> None:
    p = _register(root)
    t = p.read_text(encoding="utf-8")
    parts = t.split("### OD-002 ", 1)
    head, body = parts[0], parts[1]
    body = re.sub(r"^- Current Status:.*$", "- Current Status: probably fine, interim-ish",
                  body, count=1, flags=re.M)
    p.write_text(head + "### OD-002 " + body, encoding="utf-8")


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



def drop_successor_link(root: Path) -> None:
    """OD-034 is the registered successor OD-020's ratified text delegates to.

    Remove the link and the governance graph is exactly as it was before ADR-023: a ratified
    decision hands a required policy question to a decision that does not exist, and the affected
    rows can neither withhold against it nor implement it.
    """
    p = _register(root)
    p.write_text(p.read_text(encoding="utf-8").replace("- Successor To: OD-020\n", "", 1),
                 encoding="utf-8")


def break_anchor(root: Path) -> None:
    append(root / "specification" / "volume-ii" / "INDEX.md",
           "\nSee [the metering contract](APPLICATION_LAYER.md#no-such-heading-exists).\n")


def cite_retired_blocker_in_schema(root: Path) -> None:
    """The retired-blocker rule globbed one directory and never saw the schema.

    OD-025 is ratified and REASSESSMENT-TRIGGER-EVENT-010 is retired, so gating a DML grant on it
    withholds behaviour the owner approved -- in the document that decides what the database will
    actually permit.
    """
    append(root / "schemas" / "POSTGRESQL_SCHEMA.md",
           "\nThe reassessment dispatch grant is deferred under "
           "`UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010`.\n")


def unauthorized_method_beside_unrelated_rejection(root: Path) -> None:
    """Regression control for the original `unauthorized_verification_method` vacuity.

    The check once used a character-proximity window, and S-12's PRULE-023 fragment defeated it by
    ending with a rejection of a reused fingerprint version, disabling the check for a whole
    document tail. Line scoping narrowed that hole without closing it: one line asserting `meta_tag`
    as usable while rejecting something unrelated still exempted. The rejection here is about a
    fingerprint version, not about `meta_tag`, so the violation MUST still be reported.
    """
    append(root / "specification" / "volume-ii" / "SECURITY_PERFORMANCE.md",
           "\nOwnership may also be proved by `meta_tag` placement. A reused fingerprint version is "
           "rejected as invalid.\n")


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
        ("ratified decision treated as pending", mark_od_014_ratified,
         "ratified_decision_treated_as_pending"),
        ("pending decision treated as ratified", mark_od_001_pending,
         "pending_decision_treated_as_ratified"),
        ("decision status unrecognized", corrupt_od_status_vocabulary,
         "decision_status_unrecognized"),
        ("withheld limb contracted as settled",
         lambda r: append(r / "specification" / "volume-ii" / "BACKGROUND_PROCESSING.md",
                          "\n\nThe indexing table carries `unique (parsing_job_id)` to enforce the relation.\n\n"),
         "withheld_limb_contracted_as_settled"),
        ("unauthorized verification method",
         lambda r: append(r / "specification" / "volume-ii" / "SECURITY_PERFORMANCE.md",
                          "\nOwnership may also be proved by `meta_tag` placement.\n"),
         "unauthorized_verification_method"),
        # OD-016 is ratified and SESSION-REVOCATION-002 is retired, so citing it as a live
        # reason to defer would withhold ratified behaviour.
        ("retired blocker cited as live",
         lambda r: append(r / "specification" / "volume-ii" / "BACKGROUND_PROCESSING.md",
                          "\nThe revocation sweep is deferred under `UPSTREAM-V1-SESSION-REVOCATION-002`.\n"),
         "retired_blocker_cited_as_live"),
        # The rule is right about the defect and was blind to where it lives: it globbed
        # specification/volume-ii/*.md while every other check uses in_scope.
        ("retired blocker cited as live in the schema", cite_retired_blocker_in_schema,
         "retired_blocker_cited_as_live"),
        ("unresolved successor decision", drop_successor_link,
         "unresolved_successor_decision"),
        ("anchor target missing", break_anchor,
         "anchor_target_missing"),
        ("unauthorized method beside an unrelated rejection",
         unauthorized_method_beside_unrelated_rejection,
         "unauthorized_verification_method"),
    ]
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="f1-v2-negative-") as tmp:
        base = Path(tmp) / "repo"
        base.mkdir()
        for sub in ["specification", "schemas"]:
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
