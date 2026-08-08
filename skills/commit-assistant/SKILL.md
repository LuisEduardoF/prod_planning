---
name: commit-assistant
description: Read a pull request diff against the project's generated checklists (checklist-code.md, checklist-data.md) and report which checklist items the change breaks or puts at risk. Use when the user asks to review a diff or PR against the checklists, check whether a change violates documented requirements, or gate a merge to the production branch on the checklists.
---

# Commit assistance against the checklists

Reads a pull request's diff and answers one question: **does this change break
anything the checklists say must hold?** Advisory only — it reports, it never
edits code, never edits the checklists, and never blocks a merge.

The checklists are the contract. This skill does not re-derive requirements from
the context documents; if an item is not in a checklist, it is not this skill's
business. Regenerate the checklists (`checklist-generate`) when they are stale.

## Inputs

1. **Diff** — required. A unified diff of the pull request against its base
   branch, either as a file path or already in context. If not given, ask for
   it; do not guess by diffing the working tree.
2. **Checklist folder path** — required. The folder holding
   `checklist-code.md` and `checklist-data.md`. If not given, ask for it; do not
   assume a default location.
3. **Report output path** — required. File to write the findings into.
4. **Verdict output path** — required. File to write a single word into:
   `breaks` if there is at least one finding, `clear` otherwise. The calling
   workflow reads this to decide whether to comment.
5. **Context folder path** — optional. Only for resolving what a checklist item
   means when its wording is ambiguous. Never a source of new items, and never
   itself under review — see the note on context edits below.

## Steps

1. **Read both checklists in full.** If neither file exists, write `clear` to
   the verdict path, note in the report that there is nothing to check against,
   and stop — a repo without checklists is not a failing repo.
2. **Read the diff in full.** Note every changed file, and for each, the
   specific hunks. A file rename or deletion counts as a change.
3. **Match changes to checklist items.** For each changed hunk, find the
   checklist items it plausibly touches — by the file's role (schema, pipeline,
   validation, config, output writer), by identifiers the item names (field
   names, SKUs, thresholds, model versions), and by the source document the item
   cites. Most hunks touch nothing; say nothing about those.
4. **Classify every match** as exactly one of:
   - `⛔ breaks` — the diff makes a checked item false. Requires concrete
     evidence in the diff: a removed validation, a renamed/dropped schema field
     the item names, a changed threshold that crosses a stated target, a
     deleted fallback the item requires.
   - `⚠ at risk` — the diff plausibly affects the item but the diff alone
     cannot settle it (e.g. touches the code path behind an acceptance criterion
     without changing its stated behavior).
   - Everything else — not reported.
5. **Quote your evidence.** Every finding cites the checklist item **verbatim**,
   names the file and hunk in the diff that triggered it, and states in one
   sentence why the item no longer holds. A finding without a diff citation is
   speculation — drop it.
6. **Write the report** at the report output path, using
   `assets/commit-assistant-comment.template.md` as the skeleton. Order findings
   `⛔ breaks` first, then `⚠ at risk`.
7. **Write the verdict** — `breaks` if the report has at least one finding of
   either class, otherwise `clear`.
8. **Report** a one-line summary: counts of breaks and at-risk items.

## Notes

- **Never edit the checklists.** They are generated from `context/`; an item
  that is wrong is fixed by changing the source context document and re-running
  `checklist-generate`, not by editing the checklist or by this skill.
- **Never edit the code under review.** This skill reads a diff and writes a
  report. Applying a fix is a separate, human decision.
- **Changes to the context folder are not findings.** This skill is the last
  step of a pipeline — `context-scaffold` → the human fills in `context/` →
  `checklist-generate` → this. Editing a context document does not break a
  checklist item; it makes the checklists stale, and the answer is to re-run
  `checklist-generate`. Ignore context-only hunks in a mixed diff and review the
  rest. (The calling workflow skips a pull request that touches nothing else,
  so a diff that is entirely context edits should not reach this skill at all.)
- **Prefer silence to noise.** This runs on every pull request to the production
  branch. A false `⛔` trains people to ignore the comment. When the diff does
  not settle it, that is `⚠ at risk`, and when nothing is affected the correct
  output is an empty findings list.
- **`⚠ gap` items cannot be broken.** A gap item records missing documentation,
  not a property of the code — skip them.
- **Draft-doc caveats carry over.** If a matched item is tagged "per draft doc —
  confirm before building", repeat that caveat in the finding, because the item
  itself may not be settled.
