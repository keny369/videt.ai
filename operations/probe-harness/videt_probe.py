#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["anthropic", "openai"]
# ///
"""
VIDET probe harness. Throwaway operations tooling, not platform code.

What it is for: screening many prospects across many questions in one pass, so
you know which story is real before spending a manual hour on any of them.

What it is NOT: a substitute for the consumer surface. These are API calls.
ChatGPT-the-product and its model via API are different systems, with different
system prompts, retrieval stacks and personalisation. Nothing measured here may
be reported to a prospect as "ChatGPT said". Use it to FIND the specimen, then
re-run that one specimen manually on the consumer product and cite that run.
Every record written carries surface="api" so this can never be lost later.

  uv run videt_probe.py plan                  # matrix + cost estimate, no calls
  uv run videt_probe.py models                # what model ids your keys can see
  uv run videt_probe.py run                   # probe + transcribe, resumable
  uv run videt_probe.py verify                # fetch every cited URL, save text
  uv run videt_probe.py report                # counts per target and per question

Dependencies are declared inline above, so `uv run` resolves them itself.
Env: ANTHROPIC_API_KEY, OPENAI_API_KEY
"""

from __future__ import annotations

import argparse
import concurrent.futures as futures
import hashlib
import json
import os
import re
import sys
import tomllib
import urllib.error
import urllib.request
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
EVIDENCE = HERE / "evidence"
RUNS_PATH = EVIDENCE / "runs.jsonl"
SOURCES_DIR = EVIDENCE / "sources"

# Per-request ceiling. A web-search turn legitimately takes 30-60s; beyond
# this something is wedged and a hung job should not stall the whole run.
REQUEST_TIMEOUT_S = 120.0

FORCED_OFF_PREFIX = (
    "Please answer from your own knowledge only — do not search the web for this.\n\n"
)

# ---------------------------------------------------------------------------
# Transcription schema. A separate call reads the answer text and extracts
# structure. It never sees the question's intent, only the text.
# ---------------------------------------------------------------------------

def _nullable(t: str) -> dict:
    return {"anyOf": [{"type": t}, {"type": "null"}]}


TRANSCRIPT_SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "required": ["entities", "sources_cited", "declined_to_recommend", "subject", "notes"],
    "properties": {
        "entities": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": [
                    "position", "name_as_written", "url_as_written",
                    "location_attributed", "country_attributed",
                    "descriptors", "credentials_attributed", "recommended",
                    "first_mentioned_in",
                ],
                "properties": {
                    "position": _nullable("integer"),
                    "name_as_written": {"type": "string"},
                    "url_as_written": _nullable("string"),
                    "location_attributed": _nullable("string"),
                    "country_attributed": {
                        "type": "string",
                        "enum": ["AU", "US", "GB", "NZ", "other", "unstated"],
                    },
                    "descriptors": {"type": "array", "items": {"type": "string"}},
                    "credentials_attributed": {"type": "array", "items": {"type": "string"}},
                    "recommended": {"type": "boolean"},
                    "first_mentioned_in": {
                        "type": "string",
                        "enum": ["initial_answer", "followup", "not_stated"],
                    },
                },
            },
        },
        "sources_cited": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["url", "claimed_support"],
                "properties": {
                    "url": {"type": "string"},
                    "claimed_support": {"type": "string"},
                },
            },
        },
        "declined_to_recommend": {"type": "boolean"},
        "subject": {
            "type": "object",
            "additionalProperties": False,
            "required": [
                "described", "recognition", "name_as_written", "location_attributed",
                "people_attributed", "services_attributed", "credentials_attributed", "stance",
            ],
            "properties": {
                "described": {"type": "boolean"},
                "recognition": {
                    "type": "string",
                    "enum": [
                        "know_this_specific_business", "recognise_name_only",
                        "inferring_from_name_and_category", "do_not_know", "not_applicable",
                    ],
                },
                "name_as_written": _nullable("string"),
                "location_attributed": _nullable("string"),
                "people_attributed": {"type": "array", "items": {"type": "string"}},
                "services_attributed": {"type": "array", "items": {"type": "string"}},
                "credentials_attributed": {"type": "array", "items": {"type": "string"}},
                "stance": {
                    "type": "string",
                    "enum": ["recommended", "neutral", "cautioned", "declined_to_say", "not_applicable"],
                },
            },
        },
        "notes": {"type": "string"},
    },
}

TRANSCRIBE_INSTRUCTION = """\
You are transcribing an AI assistant's answer into structured data. You are not \
evaluating it, correcting it, or adding to it.

Rules:
- Record ONLY what the answer text below states. Never add an entity, URL, \
location or credential that is not in the text.
- Never repair or complete a URL. Copy it exactly as written, or use null.
- country_attributed is what the ANSWER attributes, not what you believe is \
true. Use "unstated" when the answer does not say. Never infer a country from a \
business name.
- position is the rank the answer gives, or null if it gave no ranking.
- recognition reflects what the answer says about its own knowledge of the \
subject business. Use "not_applicable" when no single subject business was asked about.
- If the answer named no businesses, entities is an empty array.
- first_mentioned_in records WHERE a business first appears: "initial_answer" for \
TURN 0, "followup" if it only appears in a later turn. This matters: an entity \
volunteered cold is a different observation from one produced under prompting.
- sources_cited: capture every page or source the assistant claims to have drawn \
on, across ALL turns. The source-elicitation follow-up is usually where these \
appear. claimed_support is what it said that source shows.

CONVERSATION (turn 0 is the cold question; later turns are follow-ups):
<<<
{answer}
>>>
"""

# ---------------------------------------------------------------------------
# Records
# ---------------------------------------------------------------------------

@dataclass
class Job:
    run_id: str
    provider: str
    probe: str            # "recommendation" | "entity_resolution"
    vertical: str
    question_id: str
    question_text: str
    archetype: str
    kind: str
    arm: str              # "search" | "nosearch"
    repeat: int
    followups: list[str] = field(default_factory=list)
    subject_id: str | None = None
    subject_name: str | None = None


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_config(path: Path) -> dict:
    with path.open("rb") as fh:
        return tomllib.load(fh)


# ---------------------------------------------------------------------------
# Job matrix
# ---------------------------------------------------------------------------

def build_jobs(cfg: dict) -> list[Job]:
    run = cfg["run"]
    arms: list[str] = run["arms"]
    first_only: bool = run.get("followups_on_first_repeat_only", True)
    providers = [n for n, p in cfg["providers"].items() if p.get("enabled")]

    jobs: list[Job] = []
    for v in cfg["verticals"]:
        for q in v["questions"]:
            for arm in arms:
                for rep in range(1, run["repeats_vertical"] + 1):
                    for prov in providers:
                        fups = v.get("followups", []) if q["kind"] == "recommendation" else []
                        if first_only and rep != 1:
                            fups = []
                        jobs.append(Job(
                            run_id=f"{prov}|{q['id']}|{arm}|r{rep}",
                            provider=prov, probe="recommendation",
                            vertical=v["id"], question_id=q["id"],
                            question_text=q["text"], archetype=q["archetype"],
                            kind=q["kind"], arm=arm, repeat=rep, followups=fups,
                        ))

    entity_followups = [
        "Are there any other businesses with the same or a similar name you might be mixing them up with?",
        "Where does your information about them come from? List specific pages or sources.",
    ]
    for t in cfg["targets"]:
        text = (
            f"What can you tell me about {t['name']}, the {t['category_singular']} "
            f"in {t['location']}? What do they do, who runs them, and would you recommend them?"
        )
        for arm in arms:
            for rep in range(1, run["repeats_entity"] + 1):
                for prov in providers:
                    fups = entity_followups if not (first_only and rep != 1) else []
                    jobs.append(Job(
                        run_id=f"{prov}|E-{t['id']}|{arm}|r{rep}",
                        provider=prov, probe="entity_resolution",
                        vertical=t["vertical"], question_id=f"E-{t['id']}",
                        question_text=text, archetype="E", kind="entity",
                        arm=arm, repeat=rep, followups=fups,
                        subject_id=t["id"], subject_name=t["name"],
                    ))
    return jobs


# ---------------------------------------------------------------------------
# Providers
# ---------------------------------------------------------------------------

def _user_location_anthropic(cfg: dict) -> dict | None:
    ul = cfg["run"].get("user_location", {})
    if not ul.get("enabled"):
        return None
    return {
        "type": "approximate",
        "city": ul["city"], "region": ul["region"],
        "country": ul["country"], "timezone": ul["timezone"],
    }


def call_anthropic(cfg: dict, job: Job) -> dict:
    import anthropic

    pc = cfg["providers"]["anthropic"]
    client = anthropic.Anthropic(timeout=REQUEST_TIMEOUT_S, max_retries=1)
    loc = _user_location_anthropic(cfg)
    deviations: list[str] = []

    def tools(with_loc: bool) -> list[dict]:
        if job.arm != "search":
            return []
        tool: dict[str, Any] = {"type": "web_search_20260209", "name": "web_search"}
        if with_loc and loc:
            tool["user_location"] = loc
        return [tool]

    first = job.question_text
    if job.arm == "nosearch":
        first = FORCED_OFF_PREFIX + first

    messages: list[dict] = [{"role": "user", "content": first}]
    turns: list[dict] = []
    raw: list[dict] = []
    use_loc = True

    for turn_index, prompt in enumerate([None] + job.followups):
        if prompt is not None:
            messages.append({"role": "user", "content": prompt})
        try:
            msg = client.messages.create(
                model=pc["model"], max_tokens=pc["max_tokens"],
                output_config={"effort": pc["effort"]},
                tools=tools(use_loc),
                messages=messages,
            )
        except Exception as exc:  # noqa: BLE001
            if use_loc and loc and "user_location" in str(exc):
                deviations.append("user_location rejected by provider; retried without it")
                use_loc = False
                msg = client.messages.create(
                    model=pc["model"], max_tokens=pc["max_tokens"],
                    output_config={"effort": pc["effort"]},
                    tools=tools(False), messages=messages,
                )
            else:
                raise
        # A refusal is data, not an error. No `fallbacks` here on purpose: a
        # server-side fallback would silently swap the model being measured.
        if msg.stop_reason == "refusal":
            deviations.append("stop_reason=refusal")
        if msg.stop_reason == "max_tokens":
            deviations.append("stop_reason=max_tokens (answer truncated)")

        dump = msg.model_dump()
        raw.append(dump)
        text = "\n".join(b.get("text", "") for b in dump.get("content", []) if b.get("type") == "text")
        turns.append({"turn": turn_index, "prompt": prompt or first, "text": text})
        messages.append({"role": "assistant", "content": msg.content})

    return {
        "model_reported": raw[-1].get("model"),
        "stop_reason": raw[-1].get("stop_reason"),
        "turns": turns,
        "raw": raw,
        "deviations": deviations,
    }


def call_openai(cfg: dict, job: Job) -> dict:
    from openai import OpenAI

    pc = cfg["providers"]["openai"]
    client = OpenAI(timeout=REQUEST_TIMEOUT_S, max_retries=1)
    ul = cfg["run"].get("user_location", {})
    deviations: list[str] = []

    def tools(with_loc: bool) -> list[dict]:
        if job.arm != "search":
            return []
        tool: dict[str, Any] = {"type": "web_search"}
        if with_loc and ul.get("enabled"):
            tool["user_location"] = {
                "type": "approximate", "city": ul["city"],
                "region": ul["region"], "country": ul["country"],
                "timezone": ul["timezone"],
            }
        return [tool]

    first = job.question_text
    if job.arm == "nosearch":
        first = FORCED_OFF_PREFIX + first

    turns: list[dict] = []
    raw: list[dict] = []
    prev_id: str | None = None
    use_loc = True
    # "Instant" is the ChatGPT fast tier. On the API that is the reasoning model
    # held at its lowest effort, not a separate model id. The accepted spelling
    # for "lowest" moves between model generations, so try a ladder rather than
    # betting on one word, and record which rung actually took.
    ladder: list[str] = list(pc.get("reasoning_effort_ladder") or [])

    for turn_index, prompt in enumerate([first] + job.followups):
        def build() -> dict[str, Any]:
            k: dict[str, Any] = {
                "model": pc["model"], "input": prompt,
                "max_output_tokens": pc["max_output_tokens"],
                "tools": tools(use_loc),
            }
            if ladder:
                k["reasoning"] = {"effort": ladder[0]}
            if prev_id:
                k["previous_response_id"] = prev_id
            return k

        # Degrade one parameter at a time and record it, rather than failing the
        # run or silently dropping a condition variable.
        resp = None
        for _ in range(6):
            try:
                resp = client.responses.create(**build())
                break
            except Exception as exc:  # noqa: BLE001
                msg = str(exc)
                if ladder and ("reasoning" in msg or "effort" in msg):
                    rejected = ladder.pop(0)
                    deviations.append(
                        f"reasoning.effort={rejected} rejected"
                        + (f"; trying {ladder[0]}" if ladder else "; ran at provider default")
                    )
                elif use_loc and "user_location" in msg:
                    deviations.append("user_location rejected by provider; retried without it")
                    use_loc = False
                else:
                    raise
        if resp is None:
            raise RuntimeError("openai call failed after parameter degradation")
        dump = resp.model_dump()
        raw.append(dump)
        prev_id = dump.get("id")
        turns.append({"turn": turn_index, "prompt": prompt, "text": resp.output_text or ""})

    return {
        "model_reported": raw[-1].get("model"),
        "stop_reason": raw[-1].get("status"),
        "reasoning_effort_used": ladder[0] if ladder else "provider_default",
        "turns": turns,
        "raw": raw,
        "deviations": deviations,
    }


# ---------------------------------------------------------------------------
# Transcription
# ---------------------------------------------------------------------------

def transcribe(cfg: dict, job: Job, answer_text: str) -> dict:
    import anthropic

    tc = cfg["transcribe"]
    client = anthropic.Anthropic(timeout=REQUEST_TIMEOUT_S, max_retries=1)
    prompt = TRANSCRIBE_INSTRUCTION.format(
        subject=job.subject_name or "none, this was an open recommendation question",
        answer=answer_text.strip()[:60000],
    )
    msg = client.messages.create(
        model=tc["model"], max_tokens=8000,
        output_config={"effort": tc["effort"], "format": {"type": "json_schema", "schema": TRANSCRIPT_SCHEMA}},
        messages=[{"role": "user", "content": prompt}],
    )
    if msg.stop_reason == "refusal":
        return {"_error": "transcription refused"}
    text = "".join(b.text for b in msg.content if b.type == "text")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {"_error": "transcription not valid json", "_raw": text[:2000]}


# ---------------------------------------------------------------------------
# URL harvesting
# ---------------------------------------------------------------------------

URL_RE = re.compile(r"https?://[^\s<>\"'\])}]+")


def harvest_urls(obj: Any, out: set[str]) -> None:
    """Walk any nested structure and collect every URL, from citation objects
    and from prose alike. Deliberately over-collects; the verify pass dedupes."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in ("url", "source", "page_url") and isinstance(v, str) and v.startswith("http"):
                out.add(v.strip().rstrip(".,);"))
            else:
                harvest_urls(v, out)
    elif isinstance(obj, list):
        for v in obj:
            harvest_urls(v, out)
    elif isinstance(obj, str):
        for m in URL_RE.findall(obj):
            out.add(m.rstrip(".,);"))


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_plan(cfg: dict, args) -> None:
    jobs = build_jobs(cfg)
    by_provider: dict[str, int] = {}
    search_calls = 0
    for j in jobs:
        turns = 1 + len(j.followups)
        by_provider[j.provider] = by_provider.get(j.provider, 0) + turns
        if j.arm == "search":
            search_calls += turns

    total = sum(by_provider.values())
    print(f"jobs:            {len(jobs)}")
    print(f"provider calls:  {total}  " + ", ".join(f"{k}={v}" for k, v in sorted(by_provider.items())))
    print(f"search-arm calls:{search_calls}")
    print(f"transcriptions:  {len(jobs)}  (one per job, last turn only)")
    print()
    print("Rough cost, stated assumptions: search-arm calls pull ~15k input tokens of")
    print("results and emit ~1.5k; no-search calls ~0.2k in / ~1k out; transcription")
    print("~3k in / ~0.6k out. Anthropic at $5/$25 per M. OpenAI assumed comparable.")
    ant = by_provider.get("anthropic", 0)
    ant_s = sum(1 + len(j.followups) for j in jobs if j.provider == "anthropic" and j.arm == "search")
    est = (ant_s * (15000 * 5 + 1500 * 25) + (ant - ant_s) * (200 * 5 + 1000 * 25)) / 1e6
    est += len(jobs) * (3000 * 5 + 600 * 25) / 1e6
    print(f"\nAnthropic side estimate: ~${est:,.2f}  (OpenAI side of similar order)")
    print("\nDry run only. No calls made. Run `models` next to confirm model ids.")


def cmd_models(cfg: dict, args) -> None:
    try:
        import anthropic
        for m in anthropic.Anthropic().models.list():
            print(f"anthropic  {m.id}")
    except Exception as exc:  # noqa: BLE001
        print(f"anthropic  ERROR: {exc}")
    try:
        from openai import OpenAI
        ids = sorted(m.id for m in OpenAI().models.list())
        for i in ids:
            print(f"openai     {i}")
    except Exception as exc:  # noqa: BLE001
        print(f"openai     ERROR: {exc}")
    print("\nSet [providers.*].model in probe_config.toml to ids that appear above.")


def completed_run_ids() -> set[str]:
    if not RUNS_PATH.exists():
        return set()
    ids = set()
    with RUNS_PATH.open() as fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not rec.get("error"):
                ids.add(rec["run_id"])
    return ids


def cmd_run(cfg: dict, args) -> None:
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    jobs = build_jobs(cfg)
    done = completed_run_ids()
    todo = [j for j in jobs if j.run_id not in done]
    if args.only:
        todo = [j for j in todo if args.only in j.run_id]
    print(f"{len(jobs)} jobs, {len(done)} already complete, {len(todo)} to run")
    if not todo:
        return

    lock = __import__("threading").Lock()

    def work(job: Job) -> str:
        with lock:
            print(f"    -> {job.run_id} ({1 + len(job.followups)} turns + transcription)", flush=True)
        base = {
            "run_id": job.run_id,
            "schema": "videt.api-probe-v0.1",
            "surface": "api",  # NOT the consumer product. Never report as such.
            "captured_at": now_iso(),
            "operator": cfg["run"]["operator"],
            "location_note": cfg["run"]["location_note"],
            "provider": job.provider,
            "model_requested": cfg["providers"][job.provider]["model"],
            "arm": job.arm,
            "repeat": job.repeat,
            "probe": job.probe,
            "vertical": job.vertical,
            "question_id": job.question_id,
            "question_text": job.question_text,
            "archetype": job.archetype,
            "kind": job.kind,
            "subject_id": job.subject_id,
            "subject_name": job.subject_name,
            "transcription_method": "separate_call_fresh_context",
        }
        try:
            fn = call_anthropic if job.provider == "anthropic" else call_openai
            result = fn(cfg, job)
            answer = "\n\n".join(
                f"--- TURN {t['turn']} (asked: {t['prompt'][:110]}) ---\n{t['text']}"
                for t in result["turns"]
            )
            base.update(result)
            base["transcript"] = transcribe(cfg, job, answer) if answer.strip() else {"_error": "empty answer"}
            urls: set[str] = set()
            harvest_urls(result["raw"], urls)
            harvest_urls(base["transcript"], urls)
            base["urls_seen"] = sorted(urls)
            base["error"] = None
        except Exception as exc:  # noqa: BLE001
            base["error"] = f"{type(exc).__name__}: {exc}"
        with lock, RUNS_PATH.open("a") as fh:
            fh.write(json.dumps(base, default=str) + "\n")
        return f"{'ok ' if not base['error'] else 'ERR'} {job.run_id} {base.get('error') or ''}"

    with futures.ThreadPoolExecutor(max_workers=cfg["run"]["concurrency"]) as pool:
        for i, line in enumerate(pool.map(work, todo), 1):
            print(f"[{i}/{len(todo)}] {line}", flush=True)

    print(f"\nWritten to {RUNS_PATH}")
    print("Next: `verify` to fetch every cited page, then `report`.")


TAG_RE = re.compile(r"<(script|style)[^>]*>.*?</\1>|<[^>]+>", re.S | re.I)


def cmd_verify(cfg: dict, args) -> None:
    SOURCES_DIR.mkdir(parents=True, exist_ok=True)
    urls: set[str] = set()
    with RUNS_PATH.open() as fh:
        for line in fh:
            rec = json.loads(line)
            urls.update(rec.get("urls_seen") or [])
    urls = {u for u in urls if not u.startswith("https://api.")}
    print(f"{len(urls)} distinct URLs to fetch")

    index = []
    for i, url in enumerate(sorted(urls), 1):
        key = hashlib.sha256(url.encode()).hexdigest()[:16]
        dest = SOURCES_DIR / f"{key}.txt"
        if dest.exists():
            index.append({"url": url, "file": dest.name, "status": "cached"})
            continue
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "VIDET-verify/0.1"})
            with urllib.request.urlopen(req, timeout=25) as resp:
                body = resp.read()[:2_000_000]
                status = resp.status
            text = TAG_RE.sub(" ", body.decode("utf-8", "replace"))
            text = re.sub(r"[ \t]*\n[ \t]*", "\n", re.sub(r"[ \t]+", " ", text)).strip()
            header = (
                f"URL: {url}\nFETCHED_AT: {now_iso()}\nHTTP: {status}\n"
                f"SHA256_BODY: {hashlib.sha256(body).hexdigest()}\n{'-' * 70}\n"
            )
            dest.write_text(header + text)
            index.append({"url": url, "file": dest.name, "status": str(status)})
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError) as exc:
            index.append({"url": url, "file": None, "status": f"ERROR {exc}"})
        print(f"[{i}/{len(urls)}] {index[-1]['status']}  {url}", flush=True)

    (EVIDENCE / "sources_index.json").write_text(json.dumps(index, indent=2))
    print(f"\nSaved page text under {SOURCES_DIR}")
    print("Each file carries the URL, fetch timestamp and a hash of the body.")
    print("That is the dated capture of the source side. Read the claim beside it.")


STOP_TOKENS = {
    "the", "and", "pty", "ltd", "group", "co", "company", "property", "properties",
    "buyers", "buyer", "advocate", "advocates", "agent", "agents", "business",
    "businesses", "broker", "brokers", "sales", "valuation", "valuations",
    "advisory", "advisors", "advisers", "melbourne", "expert", "experts",
}


def norm_tokens(name: str) -> list[str]:
    return [t for t in re.findall(r"[a-z0-9]+", name.lower()) if t]


def distinctive(name: str) -> list[str]:
    return [t for t in norm_tokens(name) if t not in STOP_TOKENS]


def cmd_report(cfg: dict, args) -> None:
    recs = []
    with RUNS_PATH.open() as fh:
        for line in fh:
            rec = json.loads(line)
            if not rec.get("error"):
                recs.append(rec)
    print(f"{len(recs)} clean runs\n")

    # --- geography split, per question -------------------------------------
    print("COUNTRY ATTRIBUTED, per question (what the ANSWER said, not the truth)")
    print(f"{'question':<10}{'arm':<10}{'runs':>5}{'named':>7}{'AU':>5}{'US':>5}{'other':>7}{'unstated':>10}")
    agg: dict[tuple, list[int]] = {}
    for r in recs:
        ents = (r.get("transcript") or {}).get("entities") or []
        k = (r["question_id"], r["arm"])
        a = agg.setdefault(k, [0, 0, 0, 0, 0, 0])
        a[0] += 1
        for e in ents:
            a[1] += 1
            c = e.get("country_attributed", "unstated")
            a[2] += c == "AU"
            a[3] += c == "US"
            a[4] += c not in ("AU", "US", "unstated")
            a[5] += c == "unstated"
    for (qid, arm), a in sorted(agg.items()):
        print(f"{qid:<10}{arm:<10}{a[0]:>5}{a[1]:>7}{a[2]:>5}{a[3]:>5}{a[4]:>7}{a[5]:>10}")

    # --- unprimed mention counts per target --------------------------------
    print("\nUNPRIMED MENTIONS per target (across that vertical's recommendation runs)")
    for t in cfg["targets"]:
        dist = distinctive(t["name"])
        pool = [r for r in recs if r["probe"] == "recommendation" and r["vertical"] == t["vertical"]]
        if not dist:
            print(f"  {t['name']:<38} GENERIC NAME, match by hand ({len(pool)} runs in pool)")
            continue
        cold, prompted, positions = 0, 0, []
        for r in pool:
            where = None
            for e in (r.get("transcript") or {}).get("entities") or []:
                toks = set(norm_tokens(e.get("name_as_written") or ""))
                if all(d in toks for d in dist):
                    where = e.get("first_mentioned_in") or "not_stated"
                    if e.get("position"):
                        positions.append(e["position"])
                    break
            if where == "followup":
                prompted += 1
            elif where is not None:
                cold += 1
        pos = f", first-listed in {sum(1 for p in positions if p == 1)}" if positions else ""
        extra = f" (+{prompted} only after prompting)" if prompted else ""
        print(f"  {t['name']:<38} named in {cold} of {len(pool)} sampled answers{pos}{extra}")

    # --- primed entity probes ----------------------------------------------
    print("\nPRIMED ENTITY PROBES (what it said when handed the name)")
    for t in cfg["targets"]:
        rs = [r for r in recs if r.get("subject_id") == t["id"]]
        if not rs:
            continue
        levels: dict[str, int] = {}
        people: set[str] = set()
        creds: set[str] = set()
        for r in rs:
            s = (r.get("transcript") or {}).get("subject") or {}
            levels[s.get("recognition", "?")] = levels.get(s.get("recognition", "?"), 0) + 1
            people.update(s.get("people_attributed") or [])
            creds.update(s.get("credentials_attributed") or [])
        print(f"  {t['name']} ({len(rs)} runs)")
        print(f"    self-reported recognition: {levels}")
        print(f"    people attributed:      {sorted(people) or 'none'}")
        print(f"    credentials attributed: {sorted(creds) or 'none'}")
        print(f"    expected principal:     {t['principal'] or 'UNCONFIRMED, verify before use'}")
        print(f"    claims a human must check: {'; '.join(t['claims_to_check'])}")

    # --- fabrication controls ----------------------------------------------
    print("\nFABRICATION CONTROLS (did it abstain, or describe a business that does not exist?)")
    for r in recs:
        if r["kind"] != "control_fabrication":
            continue
        s = (r.get("transcript") or {}).get("subject") or {}
        verdict = "DESCRIBED IT" if s.get("described") else "abstained"
        print(f"  {r['run_id']:<44} {verdict:<14} recognition={s.get('recognition')}")

    print("\nEvery number above is an API observation. Before any of it reaches a")
    print("prospect, re-run that specimen on the consumer product and cite that run.")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["plan", "models", "run", "verify", "report"])
    ap.add_argument("--config", default=str(HERE / "probe_config.toml"))
    ap.add_argument("--only", help="run only jobs whose run_id contains this substring")
    args = ap.parse_args()
    cfg = load_config(Path(args.config))
    {"plan": cmd_plan, "models": cmd_models, "run": cmd_run,
     "verify": cmd_verify, "report": cmd_report}[args.command](cfg, args)


if __name__ == "__main__":
    sys.exit(main())
