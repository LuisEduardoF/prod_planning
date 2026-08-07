#!/usr/bin/env bash
#
# Runs the checklist-generate skill through the Claude Code CLI, then commits
# the two generated checklists on a fresh branch and opens a pull request.
#
# Companion to scripts/context-scaffold.sh — same shape, different skill.
#
# Usage:
#   scripts/checklist-generate.sh CONTEXT_PATH OUTPUT_PATH
#
#   CONTEXT_PATH   Folder holding business/, product/, data/input/,
#                  data/output/ (see its README.md). Must exist.
#   OUTPUT_PATH    Directory to write checklist-code.md and checklist-data.md
#                  into. Created if missing.
#
# Both arguments are required: the skill forbids guessing either location.
#
# Environment:
#   ANTHROPIC_API_KEY   Optional. If unset, the CLI uses your existing login.
#   RUN_ID              Optional. Branch suffix; defaults to a UTC timestamp.
#   SKIP_PR=1           Generate and commit, but skip push + gh pr create.

set -euo pipefail

usage() {
  echo "usage: scripts/checklist-generate.sh CONTEXT_PATH OUTPUT_PATH" >&2
  echo "  e.g. scripts/checklist-generate.sh context context/checklists" >&2
  exit 2
}

[[ $# -eq 2 ]] || usage
CONTEXT_PATH="$1"
OUTPUT_PATH="$2"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%d-%H%M%S)}"

# --- preconditions ----------------------------------------------------------

for cmd in claude git; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "error: '$cmd' not found in PATH" >&2
    exit 1
  }
done

if [[ "${SKIP_PR:-0}" != "1" ]]; then
  command -v gh >/dev/null 2>&1 || {
    echo "error: 'gh' not found in PATH (set SKIP_PR=1 to skip the pull request)" >&2
    exit 1
  }
  # `gh` has its own credentials — a working `git push` says nothing about it.
  # Check now rather than after the commit and push have already happened.
  gh auth status >/dev/null 2>&1 || {
    echo "error: 'gh' is not authenticated — run 'gh auth login' or set GH_TOKEN" >&2
    echo "       (or set SKIP_PR=1 to commit without opening a PR)" >&2
    exit 1
  }
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

[[ -d "$CONTEXT_PATH" ]] || {
  echo "error: context folder '$CONTEXT_PATH' does not exist" >&2
  echo "       run scripts/context-scaffold.sh first, or pass the right path" >&2
  exit 1
}

# Warn, don't stop: an empty subfolder is a gap the checklist should record.
for sub in business product data/input data/output; do
  if [[ ! -d "$CONTEXT_PATH/$sub" ]]; then
    echo "warning: '$CONTEXT_PATH/$sub' is missing — it will be reported as a gap" >&2
  elif [[ -z "$(find "$CONTEXT_PATH/$sub" -type f ! -name '.gitkeep' -print -quit)" ]]; then
    echo "warning: '$CONTEXT_PATH/$sub' has no documents — it will be reported as a gap" >&2
  fi
done

# Start from a clean checkout so the commit contains only the checklists.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is dirty — commit or stash first" >&2
  git status --short >&2
  exit 1
fi

mkdir -p "$OUTPUT_PATH"

DEFAULT_BRANCH="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
START_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
BRANCH="checklist-generate/run-${RUN_ID}"

# --- run the skill ----------------------------------------------------------

PROMPT=$(cat <<EOF
Read and follow the instructions in \`skills/checklist-generate/SKILL.md\`
(and its templates in \`assets/\`) to generate the code and data checklists.

Inputs — both are given, do not ask for them and do not substitute defaults:
- Context folder: \`${CONTEXT_PATH}\`
- Output path:    \`${OUTPUT_PATH}\`

Follow the skill's steps exactly: inventory the context folder, read every
document in full (all pages of every PDF), and write
\`${OUTPUT_PATH}/checklist-code.md\` and \`${OUTPUT_PATH}/checklist-data.md\`.

Regenerate both files from scratch — the context documents are the source of
truth, not any previous checklist. Record missing or empty context as \`⚠ gap\`
items rather than omitting them, and never invent requirements or schema
fields that are not in the documents.

Do not create a branch, commit, or pull request — the calling script handles
version control. Finish with the skill's one-line summary per checklist:
item count and gap count.
EOF
)

echo "==> Generating checklists from '${CONTEXT_PATH}' into '${OUTPUT_PATH}'"
claude -p "$PROMPT" \
  --allowedTools "Read,Write,Edit,Glob,Grep,Bash(mkdir:*),Bash(ls:*),Bash(find:*)"

for f in checklist-code.md checklist-data.md; do
  [[ -f "$OUTPUT_PATH/$f" ]] || {
    echo "error: expected '$OUTPUT_PATH/$f' was not produced" >&2
    exit 1
  }
done

# --- commit and open the PR -------------------------------------------------

if [[ -z "$(git status --porcelain)" ]]; then
  echo "==> Checklists are unchanged since the last run — nothing to commit."
  exit 0
fi

echo "==> Changes detected:"
git status --short

git config user.name "claude[bot]"
git config user.email "claude[bot]@users.noreply.github.com"

git checkout -b "$BRANCH"
git add -A
git commit -m "Generate code and data checklists from ${CONTEXT_PATH}"

if [[ "${SKIP_PR:-0}" == "1" ]]; then
  echo "==> SKIP_PR=1 — committed on '${BRANCH}', skipping push and pull request."
  exit 0
fi

git push -u origin "$BRANCH"

gh pr create \
  --base "$DEFAULT_BRANCH" \
  --head "$BRANCH" \
  --title "Generate code and data checklists" \
  --body "$(cat <<EOF
Regenerates the code and data checklists from \`${CONTEXT_PATH}\` by running the
\`skills/checklist-generate\` skill, writing into \`${OUTPUT_PATH}\`.

Files in this branch:

\`\`\`
$(git diff --name-status "${DEFAULT_BRANCH}...${BRANCH}")
\`\`\`

Both checklists are generated from scratch — fix the source context documents
and re-run rather than hand-editing an item closed.
EOF
)"

echo "==> Pull request opened against '${DEFAULT_BRANCH}'. Returning to '${START_BRANCH}'."
git checkout "$START_BRANCH"
