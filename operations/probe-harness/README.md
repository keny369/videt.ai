# VIDET probe harness

Throwaway operations tooling. Not platform code, not specification, not canon. When the platform measures this properly, delete this directory.

**Do not run this from here. Follow `operations/FOUNDING20_PROSPECT_SCREEN.md` top to bottom.** That runsheet is the instruction set; these are the two files it drives.

- `videt_probe.py` — the script. Subcommands: `plan`, `models`, `run`, `verify`, `report`.
- `probe_config.toml` — the seed file. Questions, arms, repeats, targets. Everything the harness does comes from here.
- `evidence/` — created on first run. `runs.jsonl` plus fetched source pages. Not committed by default; back it up.

The one thing to keep in your head: **these are API calls, not the consumer product.** Every record carries `surface: "api"`. Nothing measured here may be reported to a prospect as "ChatGPT said". The harness finds the specimen; you re-run that specimen by hand on the consumer app and cite that run. Step 7 of the runsheet.
