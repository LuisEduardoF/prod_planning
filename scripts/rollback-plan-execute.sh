#!/usr/bin/env bash
#
# Second half of the rollback flow. scripts/rollback-plan-generate.sh posts a
# plan to the issue; once someone agrees to it, this applies the plan's code
# steps to the repository and opens a pull request that answers the issue.
#
# The skill edits files only. Git and GitHub writes all happen here, so the
# agent cannot commit, push, or open a pull request on its own.
#
# Usage:
#   scripts/rollback-plan-execute.sh ISSUE [CONTEXT_PATH]
#
#   ISSUE          GitHub issue number (resolved against 'origin') or a full
#                  issue URL. The rollback plan must already be posted there.
#   CONTEXT_PATH   Folder holding business/, product/, data/input/,
#                  data/output/. Defaults to 'context'.
#
# Environment:
#   ANTHROPIC_API_KEY   Optional. If unset, the CLI uses your existing login.
#   RUN_ID              Optional. Branch suffix; defaults to a UTC timestamp.
#   BASE_BRANCH         Optional. PR base; defaults to origin's default branch.
#   SKIP_PR=1           Apply and commit, but skip push + gh pr create.
#   DRY_RUN=1           Apply the changes, commit nothing, print the diff.

set -euo pipefail

usage() {
  echo "usage: scripts/rollback-plan-execute.sh ISSUE [CONTEXT_PATH]" >&2
  echo "  e.g. scripts/rollback-plan-execute.sh 42" >&2
  echo "       scripts/rollback-plan-execute.sh https://github.com/o/r/issues/42 context" >&2
  exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage
ISSUE_REF="$1"
CONTEXT_PATH="${2:-context}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%d-%H%M%S)}"

if [[ "$ISSUE_REF" =~ ^[0-9]+$ ]]; then
  ISSUE_NUMBER="$ISSUE_REF"
  ISSUE_REPO=""
elif [[ "$ISSUE_REF" =~ ^https?://[^/]+/([^/]+/[^/]+)/issues/([0-9]+)/?$ ]]; then
  ISSUE_REPO="${BASH_REMATCH[1]}"
  ISSUE_NUMBER="${BASH_REMATCH[2]}"
else
  echo "error: '$ISSUE_REF' is not an issue number or an issue URL" >&2
  usage
fi

# Must match the marker scripts/rollback-plan-generate.sh writes.
MARKER="<!-- rollback-plan-generate: issue-${ISSUE_NUMBER} -->"

# --- preconditions ----------------------------------------------------------

for cmd in claude git; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "error: '$cmd' not found in PATH" >&2
    exit 1
  }
done

GH_READY=1
if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  GH_READY=0
fi

if [[ "${SKIP_PR:-0}" != "1" && "${DRY_RUN:-0}" != "1" && "$GH_READY" != "1" ]]; then
  echo "error: opening a pull request needs an authenticated 'gh' — run 'gh auth login'" >&2
  echo "       or set GH_TOKEN (or set SKIP_PR=1 to commit without opening a PR)" >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

[[ -d "$CONTEXT_PATH" ]] || {
  echo "error: context folder '$CONTEXT_PATH' does not exist" >&2
  exit 1
}

if [[ -z "$ISSUE_REPO" ]]; then
  git remote get-url origin >/dev/null 2>&1 || {
    echo "error: no 'origin' remote — pass the full issue URL instead of a number" >&2
    exit 1
  }
  if [[ "$GH_READY" == "1" ]]; then
    ISSUE_REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
  fi
fi

# Refuse to run without a plan rather than letting the agent improvise one and
# apply it in the same breath.
PLAN_FILE="checklists/rollback-plan-issue-${ISSUE_NUMBER}.md"
PLAN_ON_ISSUE=0
if [[ "$GH_READY" == "1" && -n "$ISSUE_REPO" ]]; then
  # `gh api` writes its error body to stdout, so a 404 looks like output —
  # trust the exit status (pipefail carries it through `tail`), not the text.
  if PLAN_COMMENT_ID="$(gh api "repos/${ISSUE_REPO}/issues/${ISSUE_NUMBER}/comments" \
        --paginate --jq ".[] | select(.body | contains(\"${MARKER}\")) | .id" 2>/dev/null | tail -1)"; then
    [[ "$PLAN_COMMENT_ID" =~ ^[0-9]+$ ]] && PLAN_ON_ISSUE=1
  fi
fi
if [[ "$PLAN_ON_ISSUE" != "1" && ! -f "$PLAN_FILE" ]]; then
  echo "error: no rollback plan found for issue #${ISSUE_NUMBER}" >&2
  echo "       neither a generated comment on the issue nor '${PLAN_FILE}'" >&2
  echo "       run scripts/rollback-plan-generate.sh first" >&2
  exit 1
fi

# Start clean so the commit contains only the rollback change.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is dirty — commit or stash first" >&2
  git status --short >&2
  exit 1
fi

BASE_BRANCH="${BASE_BRANCH:-$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)}"
BASE_BRANCH="${BASE_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
START_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
BRANCH="rollback-execute/issue-${ISSUE_NUMBER}-${RUN_ID}"

# Kept outside the repo so `git add -A` cannot sweep it into the commit.
SUMMARY_FILE="$(mktemp -t rollback-summary-XXXXXX.md)"
trap 'rm -f "$SUMMARY_FILE"' EXIT

# --- run the skill ----------------------------------------------------------

PROMPT=$(cat <<EOF
Read and follow the instructions in \`skills/rollback-plan-execute/SKILL.md\`
(and its template in \`assets/\`) to apply the agreed rollback plan.

Inputs — all are given, do not ask for them and do not substitute defaults:
- GitHub issue:   ${ISSUE_REF}
- Context folder: \`${CONTEXT_PATH}\`
- Summary output: \`${SUMMARY_FILE}\`

Find the plan on the issue (the comment carrying the marker
\`${MARKER}\`), falling back to \`${PLAN_FILE}\`. If neither exists, stop and
say so — do not write a plan and execute it in the same run.

Classify every plan step as code / operational / already satisfied, apply only
the code steps to the repository's source, and write the execution summary to
\`${SUMMARY_FILE}\`.

Do not edit \`checklists/checklist-code.md\` or
\`checklists/checklist-data.md\` — they are generated. Record what they should
contain, and which context document must change to produce it, in the summary's
"Checklist follow-ups" section.

Reading the issue is the only GitHub interaction allowed: never comment on,
label, or close it, and do not create a branch, commit, or pull request — the
calling script handles version control. Finish with the skill's report: steps
applied versus deferred.
EOF
)

echo "==> Applying rollback plan for issue #${ISSUE_NUMBER}"
claude -p "$PROMPT" \
  --allowedTools "Read,Write,Edit,Glob,Grep,WebFetch,Bash(mkdir:*),Bash(ls:*),Bash(find:*),Bash(git remote get-url:*),Bash(git diff:*),Bash(git status:*),Bash(gh issue view:*),Bash(gh api:*),Bash(python:*),Bash(python3:*),Bash(pytest:*)"

[[ -s "$SUMMARY_FILE" ]] || {
  echo "error: the skill produced no execution summary — treating the run as failed" >&2
  exit 1
}

if [[ -z "$(git status --porcelain)" ]]; then
  echo "==> The plan produced no source changes. Summary:"
  echo
  cat "$SUMMARY_FILE"
  echo
  echo "==> Nothing to commit — the plan's steps are operational, already satisfied," >&2
  echo "    or needed a decision. Nothing was pushed." >&2
  exit 0
fi

echo "==> Changes:"
git status --short

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "==> DRY_RUN=1 — not committing. Diff:"
  git --no-pager diff
  echo
  echo "==> Summary that would become the pull request body:"
  cat "$SUMMARY_FILE"
  exit 0
fi

# --- commit and open the PR -------------------------------------------------

git config user.name "claude[bot]"
git config user.email "claude[bot]@users.noreply.github.com"

git checkout -b "$BRANCH"
git add -A
git commit -m "$(cat <<EOF
Apply rollback plan for issue #${ISSUE_NUMBER}

Applies the code-level steps of the rollback plan agreed on issue
#${ISSUE_NUMBER}. Operational steps and checklist follow-ups are listed in the
pull request body.
EOF
)"

if [[ "${SKIP_PR:-0}" == "1" ]]; then
  echo "==> SKIP_PR=1 — committed on '${BRANCH}', skipping push and pull request."
  exit 0
fi

git push -u origin "$BRANCH"

ISSUE_TITLE="$(gh issue view "$ISSUE_NUMBER" --repo "$ISSUE_REPO" --json title --jq .title)"

gh pr create \
  --base "$BASE_BRANCH" \
  --head "$BRANCH" \
  --title "Rollback: ${ISSUE_TITLE} (#${ISSUE_NUMBER})" \
  --body-file "$SUMMARY_FILE"

echo "==> Pull request opened against '${BASE_BRANCH}'. Returning to '${START_BRANCH}'."
git checkout "$START_BRANCH"
