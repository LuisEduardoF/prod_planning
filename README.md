# prod_planning

Get Together Hackaton — Grupo 43: gerar checklist de setup de produção e o plano de rollback.

Five **reusable GitHub Actions workflows** that other repositories call to
scaffold their project context, turn it into checklists, and drive a rollback
loop off GitHub issues. Nothing here runs on this repository's own events — each
workflow is `on: workflow_call` and acts on whichever repo invokes it.

```yaml
jobs:
  plan:
    uses: artefactory-br/prod_planning/.github/workflows/rollback-plan-generate.yml@v1
```

## The workflows

| Workflow | Purpose | Wrap it with | Required inputs | Optional inputs | Secrets |
|---|---|---|---|---|---|
| [`context-scaffold.yml`](.github/workflows/context-scaffold.yml) | Creates or repairs the `context/` tree (business/, product/, data/input/, data/output/ + README) and opens a PR | `workflow_dispatch` | — | `target_path` (`.`) | all optional |
| [`checklist-generate.yml`](.github/workflows/checklist-generate.yml) | Reads `context/` and generates `checklist-code.md` + `checklist-data.md`, opens a PR | `push` on `context/**`, or `workflow_dispatch` | — | `context_path` (`context`), `output_path` (`checklists`) | all optional |
| [`rollback-plan-generate.yml`](.github/workflows/rollback-plan-generate.yml) | Reads an issue + `context/` + checklists, posts a rollback plan as an issue comment | `issues: [opened]` | `issue_number` | `context_path`, `output_path`, `new_comment` | all optional |
| [`rollback-plan-execute.yml`](.github/workflows/rollback-plan-execute.yml) | On `/execute-rollback`, applies the agreed plan's code steps and opens a PR | `issue_comment: [created]` | `issue_number` | `context_path` | all optional |
| [`commit-assistant.yml`](.github/workflows/commit-assistant.yml) | Checks a PR diff against the checklists and comments on items it breaks | `pull_request` on your production branch | `pr_number` | `target_branch`, `checklist_path`, `context_path` | all optional |

Every workflow also takes `workflows_repo` and `workflows_ref` — see
[Where the skills come from](#where-the-skills-come-from). You will not normally
set either.

### Secrets

All three are declared `required: false` on every workflow, so a caller passes
only what it has.

| Secret | What it does |
|---|---|
| `anthropic_api_key` | Anthropic API key for `anthropics/claude-code-action`. Pass this unless your runner is authenticated another way. |
| `github_app_id` | GitHub App id. Set together with `github_app_pem`. |
| `github_app_pem` | GitHub App private key (PEM). |

When both App values are set, each workflow mints a short-lived App token and
uses it everywhere instead of `GITHUB_TOKEN`. **Worth doing for the two
workflows that open pull requests** (`context-scaffold`, `checklist-generate`,
`rollback-plan-execute`): a pull request created with the default `GITHUB_TOKEN`
does *not* trigger your other workflows, so the generated PR arrives with no CI
on it. With App credentials it does.

## Complete example

Copy this into your repo at `.github/workflows/rollback-plan.yml`. It posts a
rollback plan on every newly opened issue.

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

Wrappers for the other four are in
[`.github/workflows/examples/`](.github/workflows/examples) — they sit under
`examples/` so GitHub never runs them from this repo.

## Pin your reference

**Use `@v1` or a full commit SHA. Never `@main`.**

```yaml
uses: artefactory-br/prod_planning/.github/workflows/rollback-plan-generate.yml@v1        # ok
uses: artefactory-br/prod_planning/.github/workflows/rollback-plan-generate.yml@a1b2c3d   # better
uses: artefactory-br/prod_planning/.github/workflows/rollback-plan-generate.yml@main      # no
```

These workflows run an LLM agent with write access to your repository. `@main`
means a change here silently changes what that agent does in your repo, on your
next issue, with no review on your side. A SHA is immutable; a tag is at least
deliberate.

## Two things that will bite you

**1. Permissions are intersected, not inherited.** A reusable workflow declares
its own `permissions:`, but GitHub grants the *intersection* of that and the
calling job's token. If your wrapper omits `permissions:` — or declares less
than the table above — the job runs with too little access and fails on the
first `gh` call. Declare at least as much in your wrapper as the workflow needs.

**2. Trigger contracts.** Data the workflows operate on comes from `inputs.*`,
so you can wrap most of them with any event, including `workflow_dispatch`.
The exception is `rollback-plan-execute`, whose three safety gates (comment is
on an issue not a PR, contains `/execute-rollback`, author has write access)
read `github.event.*` directly so a wrapper cannot weaken them. Wrapped with
anything other than `issue_comment`, those gates evaluate empty and the job is
**skipped** rather than run unguarded. That is deliberate: it pushes code, so it
fails closed.

## Behavior on re-runs

| Workflow | On a repo that already has the output |
|---|---|
| `context-scaffold` | **Repairs.** Creates only what is missing; never overwrites an existing `context/README.md`. Nothing to do → no branch, no PR, clean exit. |
| `checklist-generate` | **Regenerates from scratch.** Hand-edits to a checklist are discarded by design — the context documents are the source of truth. Byte-identical output → no branch, no PR, clean exit. A missing `context_path` fails loudly. |
| `rollback-plan-generate` | **Updates its own comment in place**, matched on `<!-- rollback-plan-generate: issue-<N> -->`. Pass `new_comment: true` to stack a new one instead. |
| `rollback-plan-execute` | Refuses to run unless a plan comment (or `checklists/rollback-plan-issue-<N>.md`) already exists. No source changes → comments the summary, opens no PR. |
| `commit-assistant` | One comment per PR, updated in place on later pushes. Findings cleared → the comment is rewritten to say so. Never fails the job, so it cannot block a merge. |

## Where the skills come from

The agent instructions live in [`skills/`](skills) in *this* repo, not in yours.
Each workflow checks out your repository at the workspace root and this one into
`.prod-planning/`, then points the agent at `.prod-planning/skills/<name>/`.
Your repo needs nothing beyond the wrapper.

The skills checkout defaults to `github.job_workflow_sha` — the exact commit of
the workflow file you pinned — so `@v1` always loads v1's skills. Override with
`workflows_ref`, or point `workflows_repo` at your own fork.

> If this repository is ever made **private**, callers' `GITHUB_TOKEN` will not
> be able to check it out. The skills checkout uses the App token when
> `github_app_id`/`github_app_pem` are supplied, so a private hub works only if
> every consumer installs a GitHub App with read access here. Keeping it public
> is the cheaper path.

## Repo layout

```
.github/workflows/       the five reusable workflows
.github/workflows/examples/  copy-pasteable wrappers (never run from here)
skills/                  agent instructions + templates, loaded by the workflows
scripts/                 the same four skills as local CLI scripts (see below)
```

`scripts/*.sh` are the local-development path: they shell out to the `claude`
CLI and expect `skills/` at the repo root, so they work when run from a clone of
*this* repo, not from a consumer repo. The workflows do not use them.

## License

[MIT](LICENSE)
