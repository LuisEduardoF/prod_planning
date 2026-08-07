---
name: rollback-plan-execute
description: Take a rollback plan already posted on a GitHub issue and apply its code-level steps to the repository's source, then report which steps were applied, which need a human, and which checklist items the change implies. Use when the user asks to execute, apply, or action a rollback plan for a specific issue.
---

# Rollback plan execution

Turns an agreed rollback plan into an actual source change. The plan says what
should happen; this skill makes the parts of it that are code happen, and is
explicit about the parts that aren't.

Read-only against GitHub: this skill fetches the issue and its comments and
writes files in the working tree. It never comments, labels, closes, branches,
commits, or opens a pull request — the calling script or workflow does that.

## Inputs

1. **GitHub issue** — required. A number (resolved against the repo's `origin`
   remote) or a full issue URL. If not given, ask for it.
2. **Context folder path** — required, same folder `rollback-plan-generate`
   used. If not given, ask; do not assume a default location.
3. **Summary output path** — required. Where to write the execution summary
   the caller turns into a pull request body.
4. **Source root** — optional. The package the change belongs in. Infer it from
   the repository layout if not given.

## Steps

1. **Find the plan.** Read the issue's comments (`gh issue view <N> --json
   comments`, falling back to the public REST API) and take the most recent
   comment carrying the marker `<!-- rollback-plan-generate: issue-<N> -->`.
   - If no such comment exists, check for a local
     `checklists/rollback-plan-issue-<N>.md`.
   - If neither exists, stop and report that the plan must be generated first —
     never invent a plan and execute it in the same run.

2. **Read the grounding.** The plan's provenance tags point at real files: read
   every context document and checklist item the plan cites, plus the issue
   body itself. A step's cited source is what tells you the intended behavior;
   the plan's one-line summary of it is not enough to code from.

3. **Classify every rollback step** before changing anything:
   - **code** — a change to source, config, or tests in this repository.
   - **operational** — a deploy, a data-snapshot restore, a feature-flag flip,
     a notification. Real work, but not a file in this repo.
   - **already satisfied** — the code already does this; the plan step is
     describing existing fallback behavior.
   Only `code` steps are yours to implement.

4. **Apply the code steps**, smallest change that satisfies the step.
   - Prefer restoring documented behavior over inventing new behavior: a
     rollback returns the system to an agreed state, it is not a redesign.
   - A step tagged `⚙ inferred` in the plan has no documented procedure behind
     it. Implement it only when the code change is unambiguous, and record it
     in the summary under a heading that asks for reviewer sign-off. When it is
     ambiguous, leave the code alone and report it as needing a decision.
   - Follow the conventions of the file you are editing. Add or update tests
     when the repository has tests covering the touched behavior.

5. **Derive checklist implications — do not hand-edit the checklists.**
   `checklists/checklist-code.md` and `checklists/checklist-data.md` are
   generated artifacts that say so in their own headers; an edit here is
   overwritten by the next `checklist-generate` run. Instead, for each item the
   rollback shows to be missing, wrong, or unverifiable, record in the summary:
   - the checklist item text that *should* exist (or the existing item that is
     now wrong), and
   - the context document under `<context>/business/` or `<context>/product/`
     that has to change for a regenerated checklist to contain it.
   Propose the context-doc edit as concrete replacement wording. Leave applying
   it to the reviewer unless the user explicitly asked for the docs to change.

6. **Write the summary** at the summary output path:
   - **What changed** — file-by-file, each tied to the plan step it came from.
   - **Plan steps applied** — the `code` steps, with their provenance tags
     carried over from the plan.
   - **Needs sign-off** — code steps implemented from `⚙ inferred` plan steps.
   - **Not code — do these by hand** — the `operational` steps, in plan order,
     so nothing silently drops off the rollback.
   - **Already satisfied** — steps the code already met, with the file proving
     it.
   - **Checklist follow-ups** — from step 5, or "none" if the rollback changed
     nothing a checklist should track.

7. **Report** the summary path, the count of steps applied versus deferred, and
   whether any step needed a decision you could not make.

## Notes

- Never weaken or delete a test to make a rollback step pass. A step that
  requires a test to change means the expected behavior changed — say so in the
  summary and let the reviewer confirm it.
- If applying a step would revert a change that is unrelated to the issue, stop
  at that step and report it rather than widening the blast radius.
- The plan is the instruction, but the cited sources outrank it: where a plan
  step contradicts the context doc it claims as its source, follow the doc and
  flag the contradiction in the summary.
- Re-running this skill for the same issue starts from the current working tree
  — check whether a previous run's changes are already present before applying
  a step twice.
