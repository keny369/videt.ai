#!/usr/bin/env python3
"""Validate the F1 Engineering Manual repository structure.

The validator is intentionally conservative: it checks repository-local manual
integrity and reports exact file locations where practical. It does not attempt
to decide product semantics; it enforces that the manual does not use known
removed names and that control files enumerate the manual that exists.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANUAL_ROOT = ROOT / "engineering" / "manual"

ROMAN_BY_VOLUME = {
    "volume-i": "I",
    "volume-ii": "II",
    "volume-iii": "III",
    "volume-iv": "IV",
    "volume-v": "V",
    "volume-vi": "VI",
    "volume-vii": "VII",
    "volume-viii": "VIII",
    "volume-ix": "IX",
    "volume-x": "X",
    "volume-xi": "XI",
    "volume-xii": "XII",
}

EXPECTED_SUPPORT = ["README.md", "INDEX.md", "TRACEABILITY.md", "VALIDATION_REPORT.md", "CHANGELOG.md"]
MASTER_FILES = [
    "README.md",
    "MASTER_INDEX.md",
    "MASTER_TRACEABILITY.md",
    "MANUAL_AUTHORITY.md",
    "MANUAL_VERSION_HISTORY.md",
    "MANUAL_CHANGELOG.md",
    "MANUAL_VALIDATION_REPORT.md",
    "IMPLEMENTATION_AGENT_ENTRYPOINT.md",
]
FRONT_MATTER_KEYS = ["title", "identifier", "version", "status", "owner"]
PLACEHOLDER_RE = re.compile(r"\b(TODO|TBD|FIXME|YYYY-MM-DD)\b", re.IGNORECASE)
LINK_RE = re.compile(r"(?<!!)(?:\[[^\]]+\])\(([^)]+)\)")
REMOVED_REFERENCES = {
    "ComparisonGenerated": "OD-024 removes the comparison domain event.",
    "ReassessmentTriggered": "OD-025 removes the reassessment trigger event.",
    "DocumentQuarantined": "OD-015 removes Document quarantine.",
    "DocumentRetired": "OD-015 removes Document retirement.",
    "QuarantineDocument": "OD-015 removes the operation.",
    "RetireDocument": "OD-015 removes the operation.",
}
PROHIBITED_STATE_PATTERNS = {
    r"Document\s+quarantined|`quarantined`": "Document quarantined state is removed from the canonical lifecycle.",
    r"Document\s+retired|`retired`": "Document retired state is removed from the canonical lifecycle.",
}


@dataclass(frozen=True)
class Finding:
    path: Path
    line: int | None
    code: str
    message: str

    def format(self, root: Path) -> str:
        try:
            rel = self.path.relative_to(root)
        except ValueError:
            rel = self.path
        location = str(rel)
        if self.line is not None:
            location = f"{location}:{self.line}"
        return f"{location}: {self.code}: {self.message}"


def expected_chapters(volume: str) -> list[str]:
    if volume == "volume-i":
        return [f"CHAPTER-{number:02d}-" for number in range(1, 21)]
    return [f"CHAPTER-{number:03d}-" for number in range(1, 21)]


def parse_front_matter(path: Path, text: str) -> tuple[dict[str, str], int | None]:
    lines = text.splitlines()
    start = 0
    if lines and lines[0].startswith("# engineering/manual/"):
        start = 2 if len(lines) > 1 and not lines[1].strip() else 1
    if len(lines) <= start or lines[start].strip() != "---":
        return {}, None
    data: dict[str, str] = {}
    for index, line in enumerate(lines[start + 1 :], start=start + 2):
        if line.strip() == "---":
            return data, index
        if ":" not in line:
            data[f"__invalid_{index}"] = line
            continue
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip()
    return data, None


def title_from_filename(path: Path) -> str | None:
    match = re.match(r"CHAPTER-\d{2,3}-(.+)\.md$", path.name)
    if not match:
        return None
    return match.group(1).replace("-", " ")


def chapter_number(path: Path) -> int | None:
    match = re.match(r"CHAPTER-(\d{2,3})-", path.name)
    if not match:
        return None
    return int(match.group(1))


def collect_manual_files(root: Path) -> list[Path]:
    return sorted(path for path in root.rglob("*.md") if path.is_file())


def line_for(text: str, needle: str) -> int | None:
    for index, line in enumerate(text.splitlines(), start=1):
        if needle in line:
            return index
    return None


def validate(root: Path) -> list[Finding]:
    findings: list[Finding] = []
    identifiers: dict[str, Path] = {}

    if not root.exists():
        return [Finding(root, None, "missing_manual_root", "engineering/manual does not exist")]

    for volume, roman in ROMAN_BY_VOLUME.items():
        volume_dir = root / volume
        if not volume_dir.exists():
            findings.append(Finding(volume_dir, None, "missing_volume", f"Expected {volume}"))
            continue

        for prefix in expected_chapters(volume):
            matches = sorted(volume_dir.glob(f"{prefix}*.md"))
            if len(matches) != 1:
                findings.append(Finding(volume_dir, None, "chapter_sequence", f"Expected exactly one {prefix} chapter, found {len(matches)}"))

        if volume != "volume-i":
            for support in EXPECTED_SUPPORT:
                if not (volume_dir / support).exists():
                    findings.append(Finding(volume_dir / support, None, "missing_support_file", "Expected volume support file"))

        chapter_files = sorted(volume_dir.glob("CHAPTER-*.md"))
        seen_numbers = [chapter_number(path) for path in chapter_files]
        if seen_numbers != list(range(1, 21)):
            findings.append(Finding(volume_dir, None, "nonsequential_chapters", f"Observed chapter numbers {seen_numbers}"))

        strict_front_matter = volume not in {"volume-i", "volume-ii", "volume-iii"}
        for path in chapter_files:
            text = path.read_text(encoding="utf-8")
            front_matter, end_line = parse_front_matter(path, text)
            if strict_front_matter and end_line is None:
                findings.append(Finding(path, 1, "invalid_front_matter", "Missing closing front matter delimiter"))
            if strict_front_matter:
                for key in FRONT_MATTER_KEYS:
                    if not front_matter.get(key):
                        findings.append(Finding(path, 1, "invalid_front_matter", f"Missing {key}"))
                if front_matter.get("status") != "Normative":
                    findings.append(Finding(path, 1, "invalid_front_matter", "status must be Normative"))
                if front_matter.get("owner") != "Engineering Governance":
                    findings.append(Finding(path, 1, "invalid_front_matter", "owner must be Engineering Governance"))

                expected_identifier = f"EM-{roman}-{chapter_number(path):03d}"
                if front_matter.get("identifier") != expected_identifier:
                    findings.append(Finding(path, 1, "identifier_mismatch", f"Expected {expected_identifier}"))
            title_words = title_from_filename(path)
            if strict_front_matter and title_words and front_matter.get("title") and front_matter["title"].lower() != title_words.lower():
                findings.append(Finding(path, 1, "filename_front_matter_mismatch", "Chapter filename and title differ"))

            identifier = front_matter.get("identifier")
            if identifier:
                previous = identifiers.get(identifier)
                if previous:
                    findings.append(Finding(path, 1, "duplicate_identifier", f"Duplicate of {previous.relative_to(root)}"))
                identifiers[identifier] = path

    for master in MASTER_FILES:
        if not (root / master).exists():
            findings.append(Finding(root / master, None, "missing_master_file", "Expected master control file"))

    manual_files = collect_manual_files(root)
    for path in manual_files:
        text = path.read_text(encoding="utf-8")
        legacy_volume_i = "volume-i" in path.parts
        if not text.strip():
            findings.append(Finding(path, 1, "zero_byte_or_blank", "File has no substantive content"))
            continue
        if len([line for line in text.splitlines() if line.strip()]) < 8:
            findings.append(Finding(path, 1, "placeholder_only", "File is too short to be a substantive manual document"))
        if not legacy_volume_i and text.count("```") % 2:
            findings.append(Finding(path, line_for(text, "```") or 1, "unbalanced_fence", "Markdown code fences are unbalanced"))

        placeholder = PLACEHOLDER_RE.search(text)
        if placeholder and not legacy_volume_i:
            findings.append(Finding(path, line_for(text, placeholder.group(0)), "publication_placeholder", f"Unresolved placeholder {placeholder.group(0)}"))

        for removed, reason in REMOVED_REFERENCES.items():
            if removed in text:
                findings.append(Finding(path, line_for(text, removed), "removed_reference", f"{removed}: {reason}"))
        for pattern, reason in PROHIBITED_STATE_PATTERNS.items():
            if re.search(pattern, text, flags=re.IGNORECASE):
                findings.append(Finding(path, None, "prohibited_state_reference", reason))

        for match in LINK_RE.finditer(text):
            target = match.group(1).split("#", 1)[0]
            if not target or re.match(r"^[a-z][a-z0-9+.-]*:", target, flags=re.IGNORECASE):
                continue
            if target.startswith("mailto:"):
                continue
            target_path = (path.parent / target).resolve()
            try:
                target_path.relative_to(root.resolve())
            except ValueError:
                findings.append(Finding(path, line_for(text, match.group(0)), "external_manual_link", f"Link leaves manual root: {target}"))
                continue
            if not target_path.exists():
                findings.append(Finding(path, line_for(text, match.group(0)), "broken_relative_link", f"Missing target {target}"))

    for volume in ROMAN_BY_VOLUME:
        index = root / volume / "INDEX.md"
        if not index.exists():
            continue
        text = index.read_text(encoding="utf-8")
        for chapter in sorted((root / volume).glob("CHAPTER-*.md")):
            if chapter.name not in text:
                findings.append(Finding(index, None, "missing_index_entry", f"Missing {chapter.name}"))
        if volume == "volume-i":
            for appendix in sorted((root / volume).glob("APPENDIX-*.md")):
                if appendix.name not in text:
                    findings.append(Finding(index, None, "missing_index_entry", f"Missing {appendix.name}"))

    master_index = root / "MASTER_INDEX.md"
    if master_index.exists():
        text = master_index.read_text(encoding="utf-8")
        for path in manual_files:
            if path.name == "MASTER_INDEX.md":
                continue
            rel = path.relative_to(root).as_posix()
            if rel not in text:
                findings.append(Finding(master_index, None, "missing_master_index_entry", f"Missing {rel}"))

    chapter_fingerprints: dict[str, Path] = {}
    for path in (path for path in manual_files if path.name.startswith("CHAPTER-")):
        text = path.read_text(encoding="utf-8")
        body = re.sub(r"---.*?---", "", text, count=1, flags=re.S)
        body = re.sub(r"^#.*$", "", body, flags=re.M)
        body = re.sub(r"\bEM-[IVX]+-\d{3}\b", "", body)
        body = re.sub(r"\bchapter\s+\d+\b", "", body, flags=re.IGNORECASE)
        fingerprint = re.sub(r"\s+", " ", body).strip().lower()
        if not fingerprint:
            continue
        previous = chapter_fingerprints.get(fingerprint)
        if previous:
            findings.append(Finding(path, 1, "near_duplicate_content", f"Very similar to {previous.relative_to(root)}"))
        else:
            chapter_fingerprints[fingerprint] = path

    return findings


def run_negative_controls() -> int:
    source = MANUAL_ROOT
    if not source.exists():
        print("Manual root is missing; cannot run negative controls", file=sys.stderr)
        return 2
    cases = [
        ("duplicate identifier", lambda root: replace_once(root / "volume-iv" / "CHAPTER-003-Zeitwerk-and-Autoloading-Standards.md", "identifier: EM-IV-003", "identifier: EM-IV-002"), "duplicate_identifier"),
        ("missing chapter", lambda root: (root / "volume-v" / "CHAPTER-020-Persistence-Evolution-and-Compatibility-Standards.md").unlink(), "chapter_sequence"),
        ("filename/front matter mismatch", lambda root: replace_once(root / "volume-v" / "CHAPTER-001-Persistence-and-Data-Engineering-Philosophy.md", "title: Persistence and Data Engineering Philosophy", "title: Incorrect Title"), "filename_front_matter_mismatch"),
        ("broken relative link", lambda root: append_text(root / "volume-v" / "README.md", "\n[Broken](MISSING.md)\n"), "broken_relative_link"),
        ("unbalanced code fence", lambda root: append_text(root / "volume-vi" / "README.md", "\n```ruby\nputs 'open'\n"), "unbalanced_fence"),
        ("publication placeholder", lambda root: append_text(root / "volume-vii" / "README.md", "\nTODO\n"), "publication_placeholder"),
        ("missing master-index entry", lambda root: remove_first_line_containing(root / "MASTER_INDEX.md", "volume-viii/CHAPTER-001-Security-Engineering-Philosophy.md"), "missing_master_index_entry"),
        ("removed-event reference", lambda root: append_text(root / "volume-ix" / "README.md", "\nComparisonGenerated\n"), "removed_reference"),
        ("prohibited state reference", lambda root: append_text(root / "volume-x" / "README.md", "\nDocument quarantined\n"), "prohibited_state_reference"),
    ]
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="f1-manual-negative-") as temp_name:
        temp_root = Path(temp_name) / "manual"
        shutil.copytree(source, temp_root, ignore=shutil.ignore_patterns(".DS_Store"))
        for label, mutator, expected_code in cases:
            case_root = Path(temp_name) / label.replace(" ", "-")
            shutil.copytree(temp_root, case_root)
            mutator(case_root)
            codes = {finding.code for finding in validate(case_root)}
            if expected_code not in codes:
                failures.append(f"{label}: expected {expected_code}, observed {sorted(codes)}")
            shutil.rmtree(case_root)
    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    print("Negative controls passed")
    return 0


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise RuntimeError(f"Expected exactly one occurrence of {old} in {path}")
    path.write_text(text.replace(old, new), encoding="utf-8")


def append_text(path: Path, text: str) -> None:
    path.write_text(path.read_text(encoding="utf-8") + text, encoding="utf-8")


def remove_first_line_containing(path: Path, needle: str) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(lines):
        if needle in line:
            del lines[index]
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            return
    raise RuntimeError(f"Expected a line containing {needle} in {path}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate the F1 Engineering Manual")
    parser.add_argument("--negative-controls", action="store_true", help="Run isolated negative controls against a temporary copy")
    args = parser.parse_args()
    if args.negative_controls:
        return run_negative_controls()

    findings = validate(MANUAL_ROOT)
    if findings:
        for finding in findings:
            print(finding.format(ROOT))
        print(f"Validation failed with {len(findings)} finding(s)", file=sys.stderr)
        return 1
    print("Engineering manual validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
