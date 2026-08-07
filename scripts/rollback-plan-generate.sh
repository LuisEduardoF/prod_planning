#!/usr/bin/env bash
#
# Runs the rollback-plan-generate skill through the Claude Code CLI, then posts
# the generated plan as a comment on the GitHub issue it was generated from.
#
# Sibling of scripts/checklist-generate.sh, but deliberately not the same
# ending: a rollback plan is needed in the incident thread, not in a pull
# request queue. The plan file is left in the working tree uncommitted — commit
# it yourself if you want it in the repo.
#
# The skill itself stays read-only against GitHub (see its SKILL.md). This
# script is what writes the comment.
#
# Usage:
#   scripts/rollback-plan-generate.sh CONTEXT_PATH ISSUE [OUTPUT_FILE]
#
#   CONTEXT_PATH   Folder holding business/, product/, data/input/,
#                  data/output/ (see its README.md). Must exist.
#   ISSUE          GitHub issue number (resolved against 'origin') or a full
#                  issue URL.
#   OUTPUT_FILE    File to write the plan into. Defaults to the skill's
#                  default, checklists/rollback-plan-issue-<N>.md.
#
# CONTEXT_PATH and ISSUE are required: the skill forbids guessing either.
#
# Environment:
#   ANTHROPIC_API_KEY   Optional. If unset, the CLI uses your existing login.
#   DRY_RUN=1           Generate the plan, print it, post nothing.
#   ASSUME_YES=1        Skip the confirmation prompt before commenting.
#   NEW_COMMENT=1       Always add a new comment instead of updating the
#                       previous generated one.

set -euo pipefail

usage() {
  echo "usage: scripts/rollback-plan-generate.sh CONTEXT_PATH ISSUE [OUTPUT_FILE]" >&2
  echo "  e.g. scripts/rollback-plan-generate.sh context 42" >&2
  echo "       scripts/rollback-plan-generate.sh context https://github.com/o/r/issues/42 checklists/rb-42.md" >&2
  exit 2
}

[[ $# -ge 2 && $# -le 3 ]] || usage
CONTEXT_PATH="$1"
ISSUE_REF="$2"

# Accept a bare number or an issue URL; everything else is a typo, not a guess
# the skill should be asked to resolve.
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

OUTPUT_FILE="${3:-checklists/rollback-plan-issue-${ISSUE_NUMBER}.md}"

# Lets a re-run find and update its own previous comment instead of stacking
# near-identical plans onto the thread.
MARKER="<!-- rollback-plan-generate: issue-${ISSUE_NUMBER} -->"

# --- preconditions ----------------------------------------------------------

for cmd in claude git; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "error: '$cmd' not found in PATH" >&2
    exit 1
  }
done

# Both halves of this script need `gh`: the skill reads the issue through it
# (falling back to the public REST API), and posting the comment has no
# fallback at all.
GH_READY=1
if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  GH_READY=0
fi

if [[ "${DRY_RUN:-0}" != "1" && "$GH_READY" != "1" ]]; then
  echo "error: posting the comment needs an authenticated 'gh' — run 'gh auth login'" >&2
  echo "       or set GH_TOKEN (or set DRY_RUN=1 to generate the plan without posting)" >&2
  exit 1
fi

if [[ "$GH_READY" != "1" ]]; then
  echo "warning: 'gh' is missing or unauthenticated — the skill will fall back to" >&2
  echo "         the public GitHub API, which only works for public repos" >&2
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

[[ -d "$CONTEXT_PATH" ]] || {
  echo "error: context folder '$CONTEXT_PATH' does not exist" >&2
  echo "       run scripts/context-scaffold.sh first, or pass the right path" >&2
  exit 1
}

# A bare number is resolved against 'origin' — fail here rather than making the
# skill stop mid-run to ask.
if [[ -z "$ISSUE_REPO" ]]; then
  git remote get-url origin >/dev/null 2>&1 || {
    echo "error: no 'origin' remote — pass the full issue URL instead of a number" >&2
    exit 1
  }
  if [[ "$GH_READY" == "1" ]]; then
    ISSUE_REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
  fi
fi

# Warn, don't stop: thin context just means more steps come back ⚙ inferred.
for sub in business product data/input data/output; do
  if [[ ! -d "$CONTEXT_PATH/$sub" ]]; then
    echo "warning: '$CONTEXT_PATH/$sub' is missing — related steps will be marked inferred" >&2
  elif [[ -z "$(find "$CONTEXT_PATH/$sub" -type f ! -name '.gitkeep' -print -quit)" ]]; then
    echo "warning: '$CONTEXT_PATH/$sub' has no documents — related steps will be marked inferred" >&2
  fi
done

for f in checklists/checklist-code.md checklists/checklist-data.md; do
  [[ -f "$f" ]] || echo "warning: '$f' not found — rollback steps lose their strongest source" >&2
done

mkdir -p "$(dirname "$OUTPUT_FILE")"

# --- run the skill ----------------------------------------------------------

PROMPT=$(cat <<EOF
Read and follow the instructions in \`skills/rollback-plan-generate/SKILL.md\`
(and its template in \`assets/\`) to generate the rollback plan.

Inputs — all are given, do not ask for them and do not substitute defaults:
- Context folder: \`${CONTEXT_PATH}\`
- GitHub issue:   ${ISSUE_REF}
- Output path:    \`${OUTPUT_FILE}\`

Follow the skill's steps exactly: resolve and fetch the issue, read every
document under the context folder in full (all pages of every PDF), read
\`checklists/checklist-code.md\` and \`checklists/checklist-data.md\` if they
exist, and write \`${OUTPUT_FILE}\`.

Regenerate the file from scratch — the issue thread and context documents are
the source of truth, not any previous plan. Label every item by provenance and
mark anything not backed by a document or checklist entry as \`⚙ inferred\`.

Reading the issue is the only GitHub interaction allowed: never comment on,
label, or close it. The calling script posts the plan to the issue itself.
Finish with the skill's report: the file path plus the traced-vs-inferred step
counts.
EOF
)

echo "==> Generating rollback plan for issue #${ISSUE_NUMBER} into '${OUTPUT_FILE}'"
claude -p "$PROMPT" \
  --allowedTools "Read,Write,Edit,Glob,Grep,WebFetch,Bash(mkdir:*),Bash(ls:*),Bash(find:*),Bash(git remote get-url:*),Bash(gh issue view:*)"

[[ -s "$OUTPUT_FILE" ]] || {
  echo "error: expected '$OUTPUT_FILE' was not produced" >&2
  exit 1
}

# --- post the plan to the issue ---------------------------------------------

BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT
{
  echo "$MARKER"
  cat "$OUTPUT_FILE"
  echo
  echo "---"
  echo "Generated by \`scripts/rollback-plan-generate.sh\` from \`${CONTEXT_PATH}\`. Steps tagged \`⚙ inferred\` have no documented procedure behind them and need a human decision before use."
} >"$BODY_FILE"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "==> DRY_RUN=1 — plan written to '${OUTPUT_FILE}', not posted. Comment body:"
  echo
  cat "$BODY_FILE"
  exit 0
fi

# A comment on an issue is public and notifies everyone watching the thread —
# confirm unless the caller has already said yes or there is nobody to ask.
if [[ "${ASSUME_YES:-0}" != "1" && -t 0 ]]; then
  echo
  cat "$BODY_FILE"
  echo
  read -r -p "Post this comment to ${ISSUE_REPO}#${ISSUE_NUMBER}? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || {
    echo "==> Aborted. Plan is still at '${OUTPUT_FILE}'."
    exit 0
  }
fi

EXISTING_ID=""
if [[ "${NEW_COMMENT:-0}" != "1" ]]; then
  # `gh api` writes its error body to stdout, so a failed lookup would come back
  # looking like a comment id. Require both a clean exit and a numeric id.
  if ! EXISTING_ID="$(gh api "repos/${ISSUE_REPO}/issues/${ISSUE_NUMBER}/comments" \
      --paginate --jq ".[] | select(.body | contains(\"${MARKER}\")) | .id" 2>/dev/null | tail -1)"; then
    EXISTING_ID=""
  fi
  [[ "$EXISTING_ID" =~ ^[0-9]+$ ]] || EXISTING_ID=""
fi

if [[ -n "$EXISTING_ID" ]]; then
  COMMENT_URL="$(gh api --method PATCH \
    "repos/${ISSUE_REPO}/issues/comments/${EXISTING_ID}" \
    -F "body=@${BODY_FILE}" --jq .html_url)"
  echo "==> Updated the existing rollback-plan comment: ${COMMENT_URL}"
else
  COMMENT_URL="$(gh issue comment "$ISSUE_NUMBER" --repo "$ISSUE_REPO" --body-file "$BODY_FILE")"
  echo "==> Posted rollback plan to ${ISSUE_REPO}#${ISSUE_NUMBER}: ${COMMENT_URL}"
fi

echo "==> Plan also left uncommitted at '${OUTPUT_FILE}'."
