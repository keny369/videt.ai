# Trademark & Legal Working Papers — intentionally excluded from source control

The documents in this directory (counsel instructions, clearance/knockout reports, goods-and-services schedules, filing data sheets, correspondence) are **privileged legal working papers**. They are **deliberately kept out of git** — only this `README.md` and the `.gitignore` are tracked.

## Why

- **Privilege.** Legal advice and clearance analysis are privileged; the repository is not the right custody for privileged material.
- **Precedent.** This matches the project's established position: under **OD-011** (legal closure, ADR-020), privileged material is excluded from this repository by design, keeping only a factual, non-privileged record where one is needed.
- **Not reproducible engineering.** They are binary, frequently revised working documents; they are not part of the buildable system and have no place in CI/CD.

## Where the canonical version lives

The authoritative trademark position — the marks to assert, the classes, the jurisdictions, filing status — lives with counsel and in the brand foundation's guidance (`../BRAND_FOUNDATION.md §12`, non-privileged, marked for legal review). This directory is a local working area only.

If a non-privileged, factual summary of the trademark position ever needs to be version-controlled, add it as a new tracked file here (and to the `.gitignore` allowlist) — never the privileged working papers themselves.
