#!/usr/bin/env python3
"""Tests for the Engineering Manual generator.

These exist because the generator silently emitted unparseable authority metadata
into 177 chapters and nothing detected it. The front matter tests below are
regression tests for that defect class, not decoration: each one fails if the
dedent_block fix is reverted.

Run: python3 scripts/test_generate_engineering_manual.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate_engineering_manual as g


# A conforming front-matter reader, written independently of the generator and of
# the validator: the block must start at byte 0 and close with an unindented '---'.
CONFORMING_FRONT_MATTER = re.compile(r"\A---\n(.*?)\n---\n", re.S)

FAILURES: list[str] = []


def check(condition: bool, label: str) -> None:
    if condition:
        print(f"  pass: {label}")
    else:
        print(f"  FAIL: {label}")
        FAILURES.append(label)


def parse_front_matter(text: str) -> dict[str, str] | None:
    match = CONFORMING_FRONT_MATTER.match(text)
    if not match:
        return None
    meta = {}
    for line in match.group(1).splitlines():
        key, _, value = line.partition(":")
        meta[key.strip()] = value.strip()
    return meta


def every_chapter() -> list[tuple[g.Volume, g.Chapter]]:
    return [(v, c) for v in g.VOLUMES.values() for c in v.chapters]


def test_dedent_block_survives_unindented_interpolation() -> None:
    """The exact failure mode: an interpolated line at column zero.

    textwrap.dedent would return this unchanged because the common prefix is ''.
    """
    print("test_dedent_block_survives_unindented_interpolation")
    template = "\n    ---\n    title: X\n    ---\n\n    body\n- interpolated bullet at column zero\n"
    out = g.dedent_block(template)
    check("\n---\ntitle: X\n---\n" in out, "template indent stripped despite column-zero interpolation")
    check("    title: X" not in out, "no indented front matter key survives")
    check("- interpolated bullet at column zero" in out, "column-zero content preserved verbatim")


def test_generated_chapters_have_conforming_front_matter() -> None:
    print("test_generated_chapters_have_conforming_front_matter")
    chapters = every_chapter()
    check(len(chapters) > 0, f"generator declares chapters ({len(chapters)} found)")
    unparseable, indented = [], []
    for volume, ch in chapters:
        text = g.chapter_content(volume, ch) + "\n"
        if parse_front_matter(text) is None:
            unparseable.append(ch.filename)
        if any(line.startswith("    ") for line in text.splitlines()[:8]):
            indented.append(ch.filename)
    check(not unparseable, f"every generated chapter parses ({len(unparseable)} unparseable)")
    check(not indented, f"no generated chapter has indented front matter ({len(indented)} indented)")


def test_front_matter_starts_at_byte_zero() -> None:
    print("test_front_matter_starts_at_byte_zero")
    offenders = []
    for volume, ch in every_chapter():
        text = g.chapter_content(volume, ch)
        if not text.startswith("---\n"):
            offenders.append((ch.filename, text.splitlines()[0][:40] if text.splitlines() else ""))
    check(not offenders, f"no chapter is preceded by a heading or blank line ({len(offenders)} offenders)")


def test_generated_identifier_and_title_match_filename() -> None:
    print("test_generated_identifier_and_title_match_filename")
    bad_id, bad_title = [], []
    for volume, ch in every_chapter():
        meta = parse_front_matter(g.chapter_content(volume, ch) + "\n")
        if meta is None:
            bad_id.append(ch.filename)
            continue
        expected_id = f"EM-{volume.roman}-{ch.number:03d}"
        if meta.get("identifier") != expected_id:
            bad_id.append(f"{ch.filename}: {meta.get('identifier')} != {expected_id}")
        expected_title = re.match(r"CHAPTER-\d{3}-(.+)\.md$", ch.filename).group(1).replace("-", " ")
        if meta.get("title", "").lower() != expected_title.lower():
            bad_title.append(f"{ch.filename}: {meta.get('title')!r} != {expected_title!r}")
    check(not bad_id, f"identifiers match EM-<roman>-<nnn> ({len(bad_id)} wrong)")
    check(not bad_title, f"titles match filenames ({len(bad_title)} wrong)")


def test_generated_status_and_owner_are_normative() -> None:
    print("test_generated_status_and_owner_are_normative")
    bad = []
    for volume, ch in every_chapter():
        meta = parse_front_matter(g.chapter_content(volume, ch) + "\n") or {}
        if meta.get("status") != "Normative" or meta.get("owner") != "Engineering Governance":
            bad.append(ch.filename)
    check(not bad, f"status Normative and owner Engineering Governance ({len(bad)} wrong)")


def test_generator_uses_canonical_spelling() -> None:
    print("test_generator_uses_canonical_spelling")
    source = Path(g.__file__).read_text(encoding="utf-8")
    check("Organisation" not in source, "generator source has no non-canonical 'Organisation'")
    emitted = "\n".join(g.chapter_content(v, c) for v, c in every_chapter())
    check("Organisation" not in emitted, "generated chapters have no non-canonical 'Organisation'")
    check("organisation" not in emitted, "generated chapters have no non-canonical 'organisation'")


def test_support_templates_are_not_indented() -> None:
    """README/INDEX/TRACEABILITY templates share the dedent_block path."""
    print("test_support_templates_are_not_indented")
    volume = g.VOLUME_IV
    for label, text in [
        ("README", g.volume_readme(volume)),
        ("TRACEABILITY", g.volume_traceability(volume)),
        ("CHANGELOG", g.volume_changelog(volume)),
    ]:
        indented = [line for line in text.splitlines() if line.startswith("    ") and line.strip()]
        check(not indented, f"{label} template emits no stray four-space indent ({len(indented)} lines)")


def main() -> int:
    for test in [
        test_dedent_block_survives_unindented_interpolation,
        test_generated_chapters_have_conforming_front_matter,
        test_front_matter_starts_at_byte_zero,
        test_generated_identifier_and_title_match_filename,
        test_generated_status_and_owner_are_normative,
        test_generator_uses_canonical_spelling,
        test_support_templates_are_not_indented,
    ]:
        test()
    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)} check(s)", file=sys.stderr)
        for f in FAILURES:
            print(f"  - {f}", file=sys.stderr)
        return 1
    print("Generator tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
