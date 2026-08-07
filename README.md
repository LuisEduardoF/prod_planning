![prod-planning — hand-drawn wordmark with a rollback arrow and a green checkmark](static/logo.png)

# prod-planning

Five **reusable GitHub Actions workflows** that turn a repository's context documents into production-readiness checklists and drive a rollback loop off GitHub issues. Each workflow is `on: workflow_call` and acts on whichever repo invokes it — nothing here runs on this repository's own events. It supports any repo layout, wraps with any trigger you like (`push`, `issues`, `issue_comment`, `pull_request`, `workflow_dispatch`), and runs on either an Anthropic API key or a GitHub App identity.

> Get Together Hackaton — Grupo 43: gerar checklist de setup de produção e o plano de rollback.

```yaml
jobs:
  plan:
    uses: artefactory-br/prod_planning/.github/workflows/rollback-plan-generate.yml@v1
```

## Features

- 🎯 **Context scaffolding**: Creates or repairs the `context/` tree (`business/`, `product/`, `data/input/`, `data/output/` + README) and opens a PR with the result.
- 🤖 **Checklist generation**: Reads `context/` and produces `checklist-code.md` and `checklist-data.md`, regenerated from scratch so the context documents stay the single source of truth.
- 🔍 **Commit assistant**: Checks a PR diff against the generated checklists and comments on the items it breaks — one comment per PR, updated in place, never fails the job.
- ✨ **Rollback planning**: Reads an issue plus `context/` and the checklists, then posts a concrete rollback plan as an issue comment.
- 💬 **Chat-driven execution**: A `/execute-rollback` comment from a writer applies the agreed plan's code steps and opens a PR.
- 🛠️ **Skills, not prompts**: Agent instructions live in [`skills/`](skills) as versioned `SKILL.md` files with Markdown templates, checked out alongside your repo at run time.
- 📋 **Idempotent output**: Comments are matched on hidden markers and updated in place; byte-identical output means no branch, no PR, clean exit.
- 📊 **Two checklists per repo**: Code-side and data-side, generated from the same context so reviews and rollbacks reference the same facts.
- 🏃 **Fails closed**: `rollback-plan-execute` reads its three safety gates from `github.event.*` directly, so a mis-wrapped call is **skipped**, never run unguarded.
- ⚙️ **All secrets optional**: Every secret is declared `required: false`; a caller passes only what it has.

## 📦 Pin your reference

**Use `@v1` or a full commit SHA. Never `@main`.**

```yaml
uses: artefactory-br/prod_planning/.github/workflows/rollback-plan-generate.yml@v1        # ok
uses: artefactory-br/prod_planning/.github/workflows/rollback-plan-generate.yml@a1b2c3d   # better
uses: artefactory-br/prod_planning/.github/workflows/rollback-plan-generate.yml@main      # no
```

These workflows run an LLM agent with write access to your repository. `@main` means a change here silently changes what that agent does in your repo, on your next issue, with no review on your side. A SHA is immutable; a tag is at least deliberate.

## Quickstart

The easiest way to adopt this is to copy one wrapper into your repo and pin it. Just drop the file at `.github/workflows/rollback-plan.yml` and add `ANTHROPIC_API_KEY` to your repository secrets.

```yaml
name: Rollback plan

on:
  issues:
    types: [opened]

permissions:
  contents: read
  issues: write

jobs:
  plan:
    uses: artefactory-br/prod_planning/.github/workflows/rollback-plan-generate.yml@v1
    with:
      issue_number: ${{ github.event.issue.number }}
    secrets:
      anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

This posts a rollback plan on every newly opened issue. Wrappers for the other four are in [`.github/workflows/examples/`](.github/workflows/examples) — they sit under `examples/` so GitHub never runs them from this repo.

**Note**:

* Declare at least the `permissions:` the workflow needs in *your* wrapper — GitHub grants the intersection, not the union (see **Two things that will bite you** below).
* `rollback-plan-execute` only works wrapped with `issue_comment`; any other trigger makes it skip.

## 📚 The workflows

| Workflow | Purpose | Wrap it with | Required inputs | Optional inputs | Secrets |
|---|---|---|---|---|---|
| [`context-scaffold.yml`](.github/workflows/context-scaffold.yml) | Creates or repairs the `context/` tree (business/, product/, data/input/, data/output/ + README) and opens a PR | `workflow_dispatch` | — | `target_path` (`.`) | all optional |
| [`checklist-generate.yml`](.github/workflows/checklist-generate.yml) | Reads `context/` and generates `checklist-code.md` + `checklist-data.md`, opens a PR | `push` on `context/**`, or `workflow_dispatch` | — | `context_path` (`context`), `output_path` (`checklists`), `checklist_length` (`medium`), `detail_level` (`medium`), `notes` (`""`), `notes_path` (`context/NOTES.md`) | all optional |
| [`rollback-plan-generate.yml`](.github/workflows/rollback-plan-generate.yml) | Reads an issue + `context/` + checklists, posts a rollback plan as an issue comment | `issues: [opened]` | `issue_number` | `context_path`, `output_path`, `new_comment`, `plan_length` (`medium`), `detail_level` (`medium`), `notes` (`""`), `notes_path` (`context/NOTES.md`) | all optional |
| [`rollback-plan-execute.yml`](.github/workflows/rollback-plan-execute.yml) | On `/execute-rollback`, applies the agreed plan's code steps and opens a PR | `issue_comment: [created]` | `issue_number` | `context_path` | all optional |
| [`commit-assistant.yml`](.github/workflows/commit-assistant.yml) | Checks a PR diff against the checklists and comments on items it breaks | `pull_request` on your production branch | `pr_number` | `target_branch`, `checklist_path`, `context_path` | all optional |

Every workflow also takes `workflows_repo` and `workflows_ref` — see **Where the skills come from** below. You will not normally set either.

### 📏 Sizing the output

`checklist-generate` and `rollback-plan-generate` take two independent sizing knobs, both defaulting to `medium`:

| Input | Values | What it changes |
|---|---|---|
| `checklist_length` / `plan_length` | `short` \| `medium` \| `long` | **How many items.** `short` keeps `must` requirements only (~15–25 items) or the minimum viable runbook (~5–8 steps); `medium` is the full documented breakdown; `long` adds `could` requirements, per-field items, per-step fallbacks. |
| `detail_level` | `brief` \| `medium` \| `deep` | **How much prose per item.** `brief` is one line plus its source; `medium` adds a clarifying line where an item carries a caveat or threshold; `deep` adds why it matters, how to verify it, and the exact value quoted from the doc. |

They compose: `short` + `deep` gives a few thoroughly-explained items — the right shape for a runbook someone reads mid-incident. `long` + `brief` gives a wide, scannable index.

Neither knob can switch off a `⚠ gap` item, an `⚙ inferred` tag, or a source citation, and no length drops a rollback plan's Trigger / Rollback steps / Validation sections. The sizes are budgets, not quotas: a thin `context/` is not padded to reach one, and a `must` requirement is never dropped to stay under one. An unrecognised value **fails the run** rather than being coerced to the default, so a typo can't silently resize your output.

### 📝 Operator notes

Both workflows accept free-text notes — the place to say what the documents bury, omit, or get wrong: *"the sample CSV in `data/input` is stale, use appendix B"*, *"last known-good model is v4.2"*, *"add an item for the LGPD review"*. Two channels, and they merge when both are present:

- **`notes`** — an inline string, for one run. Wrap the workflow with `workflow_dispatch` and expose it as a form field.
- **`notes_path`** — a file in your repo (default `context/NOTES.md`), for standing guidance. This is the channel that works on `push`- and `issues`-triggered runs, where there is no form to type into.

Notes shape the output but never outrank a document. Something a note asks for that no document supports is emitted cited `(source: operator note)` on a checklist, or `⚙ inferred (operator note)` on a rollback plan — so it reads as operator-requested, not document-backed. Where a note **contradicts** a document, the document wins and the conflict is recorded as a `⚠ gap` item (or a Follow-up entry) for a human to settle.

Notes reach the agent as a file, never interpolated into the prompt or a shell command, and the skills treat their contents as data rather than instructions — so a note cannot talk the agent into skipping steps, writing elsewhere, or dropping the citation rules.

### 🔒 Secrets

All three are declared `required: false` on every workflow, so a caller passes only what it has.

| Secret | What it does |
|---|---|
| `anthropic_api_key` | Anthropic API key for `anthropics/claude-code-action`. Pass this unless your runner is authenticated another way. |
| `github_app_id` | GitHub App id. Set together with `github_app_pem`. |
| `github_app_pem` | GitHub App private key (PEM). |

When both App values are set, each workflow mints a short-lived App token and uses it everywhere instead of `GITHUB_TOKEN`. **Worth doing for the three workflows that open pull requests** (`context-scaffold`, `checklist-generate`, `rollback-plan-execute`): a pull request created with the default `GITHUB_TOKEN` does *not* trigger your other workflows, so the generated PR arrives with no CI on it. With App credentials it does.

## ⚠️ Two things that will bite you

**1. Permissions are intersected, not inherited.** A reusable workflow declares its own `permissions:`, but GitHub grants the *intersection* of that and the calling job's token. If your wrapper omits `permissions:` — or declares less than the table above — the job runs with too little access and fails on the first `gh` call. Declare at least as much in your wrapper as the workflow needs.

**2. Trigger contracts.** Data the workflows operate on comes from `inputs.*`, so you can wrap most of them with any event, including `workflow_dispatch`. The exception is `rollback-plan-execute`, whose three safety gates (comment is on an issue not a PR, contains `/execute-rollback`, author has write access) read `github.event.*` directly so a wrapper cannot weaken them. Wrapped with anything other than `issue_comment`, those gates evaluate empty and the job is **skipped** rather than run unguarded. That is deliberate: it pushes code, so it fails closed.

## 🔄 Behavior on re-runs

| Workflow | On a repo that already has the output |
|---|---|
| `context-scaffold` | **Repairs.** Creates only what is missing; never overwrites an existing `context/README.md`. Nothing to do → no branch, no PR, clean exit. |
| `checklist-generate` | **Regenerates from scratch.** Hand-edits to a checklist are discarded by design — the context documents are the source of truth. Byte-identical output → no branch, no PR, clean exit. A missing `context_path` fails loudly. |
| `rollback-plan-generate` | **Updates its own comment in place**, matched on `<!-- rollback-plan-generate: issue-<N> -->`. Pass `new_comment: true` to stack a new one instead. |
| `rollback-plan-execute` | Refuses to run unless a plan comment (or `checklists/rollback-plan-issue-<N>.md`) already exists. No source changes → comments the summary, opens no PR. |
| `commit-assistant` | One comment per PR, updated in place on later pushes. Findings cleared → the comment is rewritten to say so. Never fails the job, so it cannot block a merge. |

## 🛠️ Where the skills come from

The agent instructions live in [`skills/`](skills) in *this* repo, not in yours. Each workflow checks out your repository at the workspace root and this one into `.prod-planning/`, then points the agent at `.prod-planning/skills/<name>/`. Your repo needs nothing beyond the wrapper.

The skills checkout defaults to `github.job_workflow_sha` — the exact commit of the workflow file you pinned — so `@v1` always loads v1's skills. Override with `workflows_ref`, or point `workflows_repo` at your own fork.

> If this repository is ever made **private**, callers' `GITHUB_TOKEN` will not be able to check it out. The skills checkout uses the App token when `github_app_id`/`github_app_pem` are supplied, so a private hub works only if every consumer installs a GitHub App with read access here. Keeping it public is the cheaper path.

## Documentation

* **[`.github/workflows/examples/`](.github/workflows/examples)** — **🎯 Copy-pasteable wrappers for all five workflows; start here.**
* **[`skills/`](skills)** — **⭐ What the agent is actually told to do, one `SKILL.md` per workflow.**
* [`skills/context-scaffold/SKILL.md`](skills/context-scaffold/SKILL.md) — how the `context/` tree is created and repaired, plus its [README template](skills/context-scaffold/assets/README.template.md).
* [`skills/checklist-generate/SKILL.md`](skills/checklist-generate/SKILL.md) — checklist rules, with the [code](skills/checklist-generate/assets/checklist-code.template.md) and [data](skills/checklist-generate/assets/checklist-data.template.md) templates.
* [`skills/rollback-plan-generate/SKILL.md`](skills/rollback-plan-generate/SKILL.md) — how an issue becomes a plan, and the [plan template](skills/rollback-plan-generate/assets/rollback-plan.template.md).
* [`skills/rollback-plan-execute/SKILL.md`](skills/rollback-plan-execute/SKILL.md) — what `/execute-rollback` is allowed to touch, and the [summary template](skills/rollback-plan-execute/assets/execution-summary.template.md).
* [`skills/commit-assistant/SKILL.md`](skills/commit-assistant/SKILL.md) — diff-vs-checklist review rules and the [comment template](skills/commit-assistant/assets/commit-assistant-comment.template.md).
* [`scripts/`](scripts) — the same four skills as local CLI scripts, for running them outside Actions.
* [`.github/actionlint.yaml`](.github/actionlint.yaml) — lint config for the workflow files.

## 🗂️ Repo layout

```
.github/workflows/           the five reusable workflows
.github/workflows/examples/  copy-pasteable wrappers (never run from here)
skills/                      agent instructions + templates, loaded by the workflows
scripts/                     the same four skills as local CLI scripts (see below)
static/                      logo and other README assets
```

`scripts/*.sh` are the local-development path: they shell out to the `claude` CLI and expect `skills/` at the repo root, so they work when run from a clone of *this* repo, not from a consumer repo. The workflows do not use them.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
