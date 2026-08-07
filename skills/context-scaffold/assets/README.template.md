# Context

This folder is the single source of truth for **everything a person or an agent needs to know about this project without asking anyone**. It is documentation-only: no code, no secrets, no credentials.

All context is delivered as **PDF, TXT, or XML files** — whichever matches the format the source material arrives in:

- **PDF** — decks, exports, specs, reports; anything that travels between teams without reformatting.
- **TXT** — plain notes, meeting minutes, freeform write-ups where structure doesn't matter.
- **XML** — structured or tabular data (schemas, config-like references, machine-readable exports).

Pick one format per document based on its source and content — don't convert just to standardize.

## Structure

```
context/
├── README.md          <- this file
├── business/          <- why this exists and what "good" means commercially
├── product/           <- what is being built and how it should behave
└── data/
    ├── input/         <- every dataset that goes INTO the system
    └── output/        <- every dataset the system PRODUCES
```

## Rules that apply to every document

1. **One object per file.** One business unit, one product surface, one dataset. Do not bundle.
2. **Filename:** `NN-kebab-case-name.<ext>` with `<ext>` one of `pdf` / `txt` / `xml` — e.g. `01-market-and-customers.pdf`, `03-transactions-raw.xml`. The `NN` prefix sets reading order.
3. **Front matter.** Every document opens with (a PDF page, or a header block for TXT/XML) containing:
   - Title
   - Owner (name + role)
   - Last updated (YYYY-MM-DD)
   - Status: `draft` | `reviewed` | `authoritative`
   - One-paragraph summary — what the reader learns from this document
4. **Self-contained.** Assume the reader has read nothing else. Expand every acronym on first use.
5. **Say what is unknown.** An explicit "Open questions / not yet decided" section at the end beats a confident gap.
6. **Keep the source.** If the document was exported from a deck, sheet, or doc, put that link in the front matter.

---

## `business/`

The commercial and organisational context. Answers *why this work exists and how success is judged*.

Each document should cover, as applicable to its object:

- **Problem & opportunity** — what is broken or missing today, and the cost of leaving it that way.
- **Market & customers** — segments, sizes, who pays, who uses, how they buy.
- **Stakeholders** — decision makers, approvers, blockers, and who must be kept informed.
- **Business model** — revenue/cost mechanics, unit economics, pricing.
- **Success metrics** — the KPIs this work moves, current baseline, target, and measurement window.
- **Competition & alternatives** — including "do nothing" and manual workarounds.
- **Constraints** — budget, timeline, legal, regulatory, contractual, brand.
- **Risks & assumptions** — what would invalidate the plan, and how likely that is.
- **Glossary** — internal vocabulary an outsider would misread.

Suggested files: `01-problem-and-opportunity.<ext>`, `02-market-and-customers.<ext>`, `03-stakeholders.<ext>`, `04-metrics-and-targets.<ext>`, `05-constraints-and-risks.<ext>` (`<ext>` = `pdf` / `txt` / `xml`).

---

## `product/`

The functional context. Answers *what is being built and how it must behave*.

Each document should cover, as applicable to its object:

- **Scope** — in scope, explicitly out of scope, and deferred to later.
- **Users & personas** — goals, context of use, level of expertise, accessibility needs.
- **User journeys** — the end-to-end flows, including the unhappy paths.
- **Functional requirements** — numbered, testable statements. Mark each `must` / `should` / `could`.
- **Non-functional requirements** — latency, throughput, availability, privacy, retention, localisation.
- **Business rules & edge cases** — the logic that is not obvious from the happy path.
- **Interfaces** — screens, APIs, integrations, notifications; wireframes or mockups where they exist.
- **Acceptance criteria** — how someone proves a requirement is met.
- **Dependencies** — teams, vendors, systems this relies on.
- **Open questions** — decisions still outstanding, with who owns each.

Suggested files: `01-scope-and-vision.<ext>`, `02-personas-and-journeys.<ext>`, `03-requirements.<ext>`, `04-rules-and-edge-cases.<ext>`, `05-acceptance-criteria.<ext>` (`<ext>` = `pdf` / `txt` / `xml`).

---

## `data/`

Data context is split by direction of flow. **If a dataset both arrives and is emitted, document it in both places** — the input document describes it as received, the output document describes it as delivered.

### `data/input/`

Everything the system consumes. One document per source dataset.

- **Source** — system of record, owner, how it is obtained (API, export, upload, stream, scrape).
- **Delivery** — format (CSV/JSON/Parquet/XLSX/PDF), encoding, compression, transport, file naming.
- **Cadence & volume** — frequency, arrival window, row/byte volume, expected growth, seasonality.
- **Schema** — every field: name, type, unit, nullability, example value, plain-language meaning.
- **Keys & relationships** — primary keys, foreign keys, join paths to other inputs, grain of one row.
- **Quality** — known gaps, duplicates, typical error rates, historical incidents, how bad rows arrive.
- **Validation rules** — what must be true on arrival for the data to be accepted.
- **History** — how far back data goes, whether it is corrected retroactively, how late-arriving records behave.
- **Sensitivity** — PII/PHI/financial fields, classification, retention limits, masking requirements, licence or usage restrictions.
- **Sample** — a small, anonymised excerpt (10–20 rows) rendered in the document.

Suggested files: `01-<source-name>.<ext>`, `02-<source-name>.<ext>`, … (`<ext>` = `pdf` / `txt` / `xml`; `xml` is a natural fit here for schema-shaped samples).

### `data/output/`

Everything the system produces. One document per delivered dataset, report, or model artefact.

- **Consumer** — who or what reads this, and the decision it drives.
- **Format & destination** — file type, API shape, table, dashboard, or export target.
- **Cadence & SLA** — when it must be available, freshness guarantee, what happens when it is late.
- **Schema** — every field: name, type, unit, nullability, example value, plain-language meaning.
- **Derivation** — for each field, which inputs it comes from and the rule or formula applied. This is the lineage from `data/input/`.
- **Aggregation & grain** — what one row represents after transformation.
- **Quality guarantees** — accuracy targets, reconciliation checks against inputs, tolerances.
- **Known limitations** — where the output is approximate, biased, or not fit for a given purpose.
- **Versioning** — how schema changes are communicated and how consumers are protected.
- **Sample** — a small excerpt of the real output, rendered in the document.

Suggested files: `01-<output-name>.<ext>`, `02-<output-name>.<ext>`, … (`<ext>` = `pdf` / `txt` / `xml`).

---

## Completeness check

Before treating this folder as done, confirm:

- [ ] `business/` explains why the project exists and how success is measured.
- [ ] `product/` contains requirements specific enough to test against.
- [ ] Every input dataset has a document in `data/input/` with a full schema.
- [ ] Every output dataset has a document in `data/output/` with a full schema and field-level derivation.
- [ ] Every output field traces back to at least one input field or a documented constant.
- [ ] Every document has front matter with an owner and a date.
- [ ] Sensitive fields are flagged, and no document contains live credentials or unmasked personal data.
