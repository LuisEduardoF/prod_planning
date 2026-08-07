## Checklist review

Checked this diff against `<checklist folder>/checklist-code.md` and
`checklist-data.md`. Advisory only — this does not block the merge, and the
checklists are generated, so fix a wrong item in its source context document and
re-run `checklist-generate` rather than editing the checklist.

### ⛔ Breaks

- **Item:** <checklist item quoted verbatim, including its `(source: ...)` tag>
  **Where:** `<path>` — <hunk header or line range>
  **Why:** <one sentence: what the diff removed/changed that makes the item false>

### ⚠ At risk

- **Item:** <checklist item quoted verbatim, including its `(source: ...)` tag>
  **Where:** `<path>` — <hunk header or line range>
  **Why:** <one sentence: what the diff touches, and what it does not settle>

### Summary

- ⛔ Breaks: <count>
- ⚠ At risk: <count>
- Checklist items considered: <count>
