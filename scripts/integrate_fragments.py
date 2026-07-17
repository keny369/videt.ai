#!/usr/bin/env python3
"""Merge Pass B slice fragments into the canonical Volume II owner documents.

Workers write two artifacts per slice: a structured contract
(`contracts/S-xx.json`) and a narrative fragment (`fragments/S-xx.md`). Workers
never write the owner documents directly -- parallel workers appending to the
same two files would conflict. This script performs that merge centrally.

Routing. A fragment may either carry explicit marker headings (`## APPLICATION_LAYER.md`
/ `## SECURITY_PERFORMANCE.md`), under which its real sections nest, or be flat,
in which case each section is routed by looking up the GitHub slug of its title
among the `contract_owner` anchors declared in the contracts. A section that
resolves to neither is reported rather than guessed at: a fragment whose section
title and declared anchor disagree is a defect, and silently filing it under a
default would hide the broken cross-reference that `contract_owner_does_not_cite_row`
exists to catch.

Idempotent: a section whose heading is already present in the target document is
skipped, so integrating a later wave never double-appends an earlier one.

Usage:  integrate_fragments.py [--check] [S-xx ...]
        --check reports what would be merged and exits non-zero if anything is
        pending, without writing.
        Naming slices merges only those. Idempotency is keyed on the section
        heading, so a fragment revised after integration will not re-merge --
        only integrate a slice whose worker has reported it complete.
"""

import glob
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "specification" / "volume-ii"
ROUTES = ("APPLICATION_LAYER.md", "SECURITY_PERFORMANCE.md")


def slug(title):
    """GitHub heading anchor: lowercase, drop punctuation, spaces to hyphens."""
    s = re.sub(r"[^a-z0-9 \-]", "", title.strip().lower())
    return re.sub(r"\s+", "-", s).strip("-")


def anchor_owners():
    """Map every declared contract_owner anchor to the document that owns it."""
    owners = {}
    for path in sorted(glob.glob(str(ROOT / "contracts" / "S-*.json"))):
        rows = json.load(open(path)).get("rows", {})
        for row_id, fields in rows.items():
            doc, _, anchor = fields["contract_owner"].partition("#")
            doc = doc.split("/")[-1]
            if anchor in owners and owners[anchor] != doc:
                raise SystemExit(
                    f"{path}: anchor #{anchor} claimed by both {owners[anchor]} and {doc}"
                )
            owners[anchor] = doc
    return owners


def sections(text, owners):
    """Yield (target_document, section_text) for each real section in a fragment."""
    parts = re.split(r"(?m)^(## .+)$", text)
    marker = None
    for i in range(1, len(parts), 2):
        heading, body = parts[i].strip(), parts[i + 1]
        title = heading[3:].strip()
        if title in ROUTES:
            marker = title
            continue
        target = owners.get(slug(title)) or marker
        yield target, title, (heading + "\n" + body).rstrip() + "\n"


def main():
    check = "--check" in sys.argv
    only = {a for a in sys.argv[1:] if a.startswith("S-")}
    owners = anchor_owners()
    pending, unrouted = {doc: [] for doc in ROUTES}, []

    for frag in sorted(glob.glob(str(ROOT / "fragments" / "S-*.md"))):
        name = pathlib.Path(frag).name
        if only and name[:-3] not in only:
            continue
        for target, title, block in sections(pathlib.Path(frag).read_text(), owners):
            if target is None:
                unrouted.append(f"{name}: '{title}' matches no contract_owner anchor")
                continue
            if (ROOT / target).read_text().find(f"\n## {title}\n") != -1:
                continue  # already integrated
            pending[target].append((name, title, block))

    for line in unrouted:
        print(f"unrouted: {line}")

    total = sum(len(v) for v in pending.values())
    for doc, blocks in pending.items():
        for name, title, _ in blocks:
            print(f"{'would merge' if check else 'merge'} {name}: '{title}' -> {doc}")
        if blocks and not check:
            path = ROOT / doc
            body = path.read_text().rstrip("\n")
            path.write_text(body + "\n\n" + "\n\n".join(b for _, _, b in blocks) + "\n")

    if unrouted:
        raise SystemExit(f"{len(unrouted)} unrouted section(s)")
    if check:
        print(f"{total} section(s) pending integration")
        raise SystemExit(1 if total else 0)
    print(f"integrated {total} section(s)")


if __name__ == "__main__":
    main()
