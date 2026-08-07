---
name: checklist-generate
description: Read a filled-in context/ folder (business/product/data PDFs, TXT, or XML docs following context/README.md) and produce a code checklist and a data checklist of actionable, traceable to-dos. Use when the user asks to turn context docs into a checklist, generate a build/validation checklist from context, or audit what's implemented against what the context requires.
---

# Checklist generation from context

Turns a project's `context/` folder into two actionable checklists: one for **code** (what must be built/tested) and one for **data** (what must be validated/prepared), each item traceable back to the source document it came from.

## Inputs

1. **Context folder path** — required. The folder holding `business/`, `product/`, `data/input/`, `data/output/` (see that folder's `README.md` for the expected shape — it may not be at the repo's default `context/`). If not given, ask for it; do not assume a default location.
2. **Output path** — required. Where to write the two checklist files. If not given, ask for it — do not default silently (it may belong inside the context folder, at the repo root, under `docs/`, etc.).

## Steps

1. **Inventory the context folder.** List everything under `business/`, `product/`, `data/input/`, `data/output/`. Note any empty or missing subfolder — that becomes a gap entry in the relevant checklist, not a silent skip.
2. **Read every document fully.** PDF, TXT, XML — for long PDFs, read all pages (don't stop at the front-matter page). Track, per document: title, owner, status (`draft` / `reviewed` / `authoritative`), and its section content.
3. **Build the code checklist** from `business/` + `product/`, using `assets/checklist-code.template.md` as the section skeleton:
   - One item per functional requirement, carrying its `must` / `should` / `could` marker.
   - One item per business rule / edge case.
   - One item per acceptance criterion, linked to the requirement it verifies.
   - One item per non-functional requirement (latency, availability, privacy, localisation, etc.).
   - One item per interface, integration, or dependency the code must satisfy.
   - Fold relevant business constraints (legal, budget, timeline, brand) in as constraints on the implementation, not as vague standalone items.
   - Carry forward a document's `draft` status as a caveat on its items (e.g. "per draft doc — confirm before building").
4. **Build the data checklist** from `data/input/` + `data/output/`, using `assets/checklist-data.template.md` as the section skeleton:
   - Per input dataset: one item per schema field to validate, one item per stated validation rule, one item for sensitivity/PII handling, one item confirming the documented sample matches the real source.
   - Per output dataset: one item per schema field, one item per derivation rule (trace to the specific input field(s) or constant it comes from), one item per quality guarantee/reconciliation check, one item per versioning/compatibility rule.
   - Explicitly flag any output field that does **not** trace to a documented input field or constant — that's a gap, not an assumption to fill in.
5. **Flag gaps as items, not omissions.** If a requirement has no acceptance criteria, a dataset has no schema, or sensitivity isn't stated, add a checklist item saying so, tagged `⚠ gap`, rather than leaving it out.
6. **Write the two files** at the given output path: `checklist-code.md` and `checklist-data.md` (or the names the user specifies). Use real markdown checkboxes (`- [ ]`) grouped under headings that mirror the source structure (by product doc / by dataset). Each item cites its source, e.g. `(source: product/03-requirements.pdf)`.
7. **Report** a one-line summary per checklist: item count and gap count.

## Notes

- Never invent requirements or schema fields that aren't in the context docs — the checklist reflects what's documented, plus explicit gaps for what isn't.
- Re-running this skill after the context folder changes should regenerate both files from scratch, not patch them — the context docs are the source of truth, not the previous checklist.
- If the context folder's `README.md` has a "Completeness check" section, use it as a cross-check before finishing: confirm every box it lists is either satisfied by the docs or captured as a gap item.
