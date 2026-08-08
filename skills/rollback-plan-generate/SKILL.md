---
name: rollback-plan-generate
description: Read a GitHub issue plus the project's context/ folder (and existing checklists, if present) and produce a rollback plan — trigger condition, impact, ordered rollback steps, validation, communication, and follow-up. Use when the user asks for a rollback plan, incident runbook, or "how do we proceed" instructions for a specific reported issue.
---

# Rollback plan generation from a GitHub issue

Turns a single GitHub issue into an actionable rollback plan: what broke, what it affects, the ordered steps to revert/mitigate it, how to confirm the rollback worked, who to notify, and the follow-up to prevent recurrence.

## Inputs

1. **Context folder path** — required. The folder holding `business/`, `product/`, `data/input/`, `data/output/` (see that folder's `README.md`). If not given, ask for it; do not assume a default location.
2. **GitHub issue** — required. A number (resolved against the repo's `origin` remote) or a full issue URL. If neither is given, ask for it.
3. **Output path** — where to write the plan. Default to `checklists/rollback-plan-issue-<N>.md` if the user doesn't say otherwise; confirm rather than silently picking a different location.

## Steps

1. **Resolve the issue reference.** If given a bare number, get `owner/repo` from `git remote get-url origin`. If given a URL, parse owner/repo/number from it directly.

2. **Fetch the issue.**
   - Try `gh issue view <N> --json title,body,labels,comments,url,state` first.
   - If `gh` is not installed or not authenticated, fall back to `WebFetch` against the public REST API: `https://api.github.com/repos/<owner>/<repo>/issues/<N>` for the issue body, and `.../issues/<N>/comments` for the discussion (works without auth for public repos; if it 404s/403s on a private repo, ask the user to paste the issue content instead).
   - This step is read-only — never comment on, label, or close the issue as part of this skill.

3. **Read the context folder** the same way `checklist-generate` does: everything under `business/`, `product/`, `data/input/`, `data/output/`, full documents (not just front matter), noting each doc's status (`draft`/`reviewed`/`authoritative`).

4. **Read existing checklists if present** — `checklists/checklist-code.md` and `checklists/checklist-data.md` in the repo. Pull any already-documented fallback behavior, NFR/SLA, or acceptance criterion relevant to the issue; these are the strongest source for rollback steps and validation checks.

5. **Map the issue to what it breaks.** From the issue's title/body/comments and labels, identify which functional requirement, business rule, dataset, interface, or NFR is implicated. Cite the specific source doc or checklist item.

6. **Draft the rollback steps.** Prefer steps traceable to a context doc or checklist entry (e.g., an already-documented fallback behavior). Where nothing documented covers the situation, infer a reasonable standard procedure (e.g., "revert to last known-good model version/data snapshot/config") — mark these `⚙ inferred` so they're never confused with a documented, agreed procedure.

7. **Write the rollback plan** at the output path, using `assets/rollback-plan.template.md` as the section skeleton:
   - **Trigger** — the condition that says "invoke this rollback," lifted from the issue's symptoms.
   - **Impact** — what's affected, each item traced to a context doc, checklist item, or marked `⚙ inferred`.
   - **Rollback steps** — ordered, concrete actions.
   - **Validation** — how to confirm the rollback worked, preferring existing acceptance criteria where they apply.
   - **Communication** — who to notify, drawn from roles/stakeholders named in the context docs.
   - **Follow-up** — root-cause action item(s), linked back to the GitHub issue number/URL.
   - **The closing `/execute` line** — keep the template's footer. It is how a
     reader learns the plan can be applied by commenting `/execute` on the issue
     (`rollback-plan-execute`). Keep it where the template puts it, at the end:
     that workflow triggers on a comment *starting with* `/execute`, so the plan
     must never open with the command it is describing.

8. **Report** the plan's file path plus a count of traced-vs-inferred steps, so the user knows how much of the plan is grounded versus assumed.

## Notes

- Every step must be labeled by provenance: `(source: product/<doc>)`, `(source: checklists/checklist-code.md)`, `(source: issue #N)`, or `⚙ inferred`. Never blend inferred and sourced content in one bullet without the tag.
- Re-running this skill for the same issue regenerates that issue's file from scratch — the issue thread and context docs are the source of truth, not the previous plan.
- Never take write actions against GitHub (no comments, no state changes) — this skill only reads the issue.
- If the issue's repo can't be resolved (no `origin` remote, ambiguous URL), ask rather than guessing.
