#!/usr/bin/env python3
"""Turn a probe run into a `measurement-set-package-v1` the platform can import.

Throwaway operations tooling, like the rest of this directory. It reads the harness's own
`runs.jsonl` plus an `export-*.json` and emits ONE package per business per measurement kind.

WHAT IT MAPS, AND WHAT IT REFUSES TO MAP. The harness measures AI answers. That is genuine
`ai_answer_presence` evidence and it is mapped in full. It is NOT search-index evidence and it
is NOT authority-reference evidence:

  * `search_index_presence` needs, per query key, the matching canonical in-scope URLs an index
    returned. The harness records the URLs a MODEL's search tool surfaced while composing an
    answer, which is a different measurement with a different denominator. Emitting it as search
    presence would report a number no search index produced.
  * `authority_reference_set` needs each reference's attribution status against a canonical
    referrer. The harness records what a model CITED, not whether the cited page attributes
    anything to the business, and deciding that needs the referrer fetched and read.

So this emits `ai_answer_presence` only. The other two stay unmeasured, and the platform keeps
reporting `input_evidence_missing` for them — which is the truthful answer, and the one OD-010
requires when no approved set supplies the evidence.

A CITATION IS WHAT THE MODEL CITED. `transcript.sources_cited` is used, never `urls_seen`:
`urls_seen` harvests every URL the run touched, including search results the answer never used.
Counting those as citations would mark a business "cited" in answers that never mentioned it,
and would break the schema's own rule that an `absent` item requires `not_cited`.

Usage:
    python3 build_measurement_package.py \
        --runs evidence/runs.jsonl --export evidence/export-2026-08-07.json \
        --business xircon-homes --organization <uuid> --project <uuid> \
        --catalog-version check-catalog-v1 --catalog-sha256 <hex> \
        --definition-sha256 <hex> --out package.json
"""

import argparse
import hashlib
import json
import re
from collections import OrderedDict
from datetime import datetime, timedelta, timezone
from pathlib import Path

PACKAGE_SCHEMA = "measurement-set-package-v1"
OBSERVATION_SCHEMA = "external-observation-v1"
MEASUREMENT_POLICY_VERSION = "external-measurement-interim-v1"
FRESHNESS = timedelta(hours=24)


def canonical(value):
    """RFC 8785-shaped canonical JSON, matching Platform::CanonicalJson on the Ruby side."""
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def digest_hex(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def load_runs(path):
    with open(path) as handle:
        return [json.loads(line) for line in handle if line.strip()]


def business_matcher(business):
    """Match the subject by its distinctive name tokens, not by a substring of the whole name.

    A substring test on a short generic name matches other businesses; the harness's own report
    code has the same problem and solves it the same way.
    """
    name = business["business_name"].lower()
    tokens = [t for t in re.split(r"[^a-z0-9]+", name) if len(t) > 2]
    lead = tokens[0] if tokens else name

    def matches(candidate):
        return lead in (candidate or "").lower()

    return matches


def host_of(url):
    match = re.match(r"https?://([^/]+)", (url or "").lower())
    return match.group(1).lstrip("www.") if match else ""


def build_observation(runs, business, vertical_id, set_version, adapter_id, adapter_version,
                      organization_id, project_id):
    matches = business_matcher(business)
    site_host = host_of(business.get("website"))

    relevant = [
        r for r in runs
        if r.get("vertical") == vertical_id and r.get("kind") == "recommendation" and not r.get("error")
    ]
    if not relevant:
        raise SystemExit(f"no clean recommendation runs for vertical {vertical_id}")

    # Ordered by UTF-8 bytes, exactly as the schema requires.
    keys = sorted({r["question_id"] for r in relevant}, key=lambda k: k.encode("utf-8"))
    text = {r["question_id"]: r["question_text"] for r in relevant}

    per = OrderedDict((k, {"runs": 0, "named": 0, "cited": 0, "entities": set()}) for k in keys)
    for run in relevant:
        slot = per[run["question_id"]]
        slot["runs"] += 1
        transcript = run.get("transcript") or {}
        hits = [e for e in (transcript.get("entities") or []) if matches(e.get("name_as_written"))]
        if hits:
            slot["named"] += 1
            for entity in hits:
                slot["entities"].add(entity["name_as_written"])
        cited = [s.get("url", "") for s in (transcript.get("sources_cited") or [])]
        if site_host and any(site_host in (u or "").lower() for u in cited):
            slot["cited"] += 1

    items = []
    for key in keys:
        slot = per[key]
        if slot["runs"] == 0:
            presence, citation, entities = "indeterminate", "indeterminate", []
        elif slot["named"] > 0:
            presence = "present"
            citation = "cited" if slot["cited"] > 0 else "not_cited"
            entities = sorted(slot["entities"])
        else:
            # An item the answers never named is absent, and the schema requires an absent item
            # to be `not_cited` with no entity key. A page of the site appearing in a search
            # result the answer did not use is not a citation of the business.
            presence, citation, entities = "absent", "not_cited", []
        items.append({
            "intent_key": key,
            "presence_status": presence,
            "citation_status": citation,
            "entity_keys": entities,
            "observed_run_count": slot["runs"],
            "named_run_count": slot["named"],
        })

    observed = min(r["captured_at"] for r in relevant)
    observed_at = datetime.fromisoformat(observed).astimezone(timezone.utc).replace(microsecond=0)
    captured = max(r["captured_at"] for r in relevant)
    captured_at = datetime.fromisoformat(captured).astimezone(timezone.utc).replace(microsecond=0)

    return {
        "schema_version": OBSERVATION_SCHEMA,
        "organization_id": organization_id,
        "project_id": project_id,
        "measurement_kind": "ai_answer_presence",
        "measurement_policy_version": MEASUREMENT_POLICY_VERSION,
        "collector_adapter_id": adapter_id,
        "collector_adapter_version": adapter_version,
        "measurement_set_version": set_version,
        "locale": "en-AU",
        "time_zone": "UTC",
        "observed_at_utc": observed_at.isoformat().replace("+00:00", "Z"),
        "captured_at_utc": captured_at.isoformat().replace("+00:00", "Z"),
        "fresh_until_utc": (observed_at + FRESHNESS).isoformat().replace("+00:00", "Z"),
        # Every expected key produced at least one clean run, so the observation covers the whole
        # declared set. `partial` would be the honest value if any key had none.
        "coverage_status": "complete" if all(per[k]["runs"] > 0 for k in keys) else "partial",
        "body": {"expected_intent_keys": keys, "items": items},
    }, keys, text


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--runs", required=True)
    ap.add_argument("--export", required=True)
    ap.add_argument("--business", required=True)
    ap.add_argument("--organization", required=True)
    ap.add_argument("--project", required=True)
    ap.add_argument("--catalog-version", required=True)
    ap.add_argument("--catalog-sha256", required=True)
    ap.add_argument("--definition-sha256", required=True)
    ap.add_argument("--set-version", default="1.0.0")
    ap.add_argument("--approval-reference", default="OD-010")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    export = json.load(open(args.export))
    runs = load_runs(args.runs)
    business = next((b for b in export["businesses"] if b["business_id"] == args.business), None)
    if business is None:
        raise SystemExit(f"{args.business} is not in {args.export}")

    run_meta = export["run"]
    adapter_id = "videt-probe-harness"
    adapter_version = export["schema"]

    observation, keys, text = build_observation(
        runs, business, business["vertical_id"], args.set_version, adapter_id, adapter_version,
        args.organization, args.project,
    )

    package = {
        "package_schema_version": PACKAGE_SCHEMA,
        "measurement_set_id": f"videt-aip-{business['business_id']}",
        "measurement_set_version": args.set_version,
        "measurement_kind": "ai_answer_presence",
        "organization_id": args.organization,
        "project_id": args.project,
        "package_created_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "proposed_effective_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "provider_identities": [
            {"provider": m["provider"], "model": m["model"]} for m in run_meta["models_measured"]
        ],
        "collector_adapter": {
            "id": adapter_id,
            "version": adapter_version,
            # The adapter digest identifies the exact script that produced these bytes.
            "sha256": hashlib.sha256(Path(__file__).with_name("videt_probe.py").read_bytes()).hexdigest(),
        },
        "expected_keys": keys,
        "key_content": {k: text[k] for k in keys},
        "locale": "en-AU",
        "time_zone": "UTC",
        "max_evidence_age_seconds": int(FRESHNESS.total_seconds()),
        "binding": {
            "catalog_version": args.catalog_version,
            "catalog_sha256": args.catalog_sha256,
            "definition_id": "CHK-AIP-001",
            "definition_version": "1.0.0",
            "definition_sha256": args.definition_sha256,
        },
        "retention_location": f"operations/probe-harness/evidence/ ({Path(args.runs).name}, {Path(args.export).name})",
        # Part of the signed bytes: the owners sign a package that names what they are approving.
        "owner_approval_reference": args.approval_reference,
        "surface_warning": run_meta["surface_warning"],
        "observations": [observation],
    }

    Path(args.out).write_text(json.dumps(package, indent=2, ensure_ascii=False))
    print(f"package_sha256={digest_hex(package)}")
    print(f"intent_keys={keys}")
    qualified = [i for i in observation["body"]["items"]
                 if i["presence_status"] == "present" and i["citation_status"] == "cited" and i["entity_keys"]]
    print(f"qualified={len(qualified)}/{len(keys)} observed_at={observation['observed_at_utc']} "
          f"fresh_until={observation['fresh_until_utc']}")


if __name__ == "__main__":
    main()
