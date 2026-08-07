#!/usr/bin/env bash
#
# Local equivalent of .github/workflows/context-scaffold.yml
#
# Runs the context-scaffold skill through the Claude Code CLI, then commits the
# result on a fresh branch and opens a pull request.
#
# Usage:
#   scripts/context-scaffold.sh [TARGET_PATH]
#
#   TARGET_PATH   Directory to scaffold context/ under, relative to the repo
#                 root. Defaults to "." (same as the workflow input).
#
# Environment:
#   ANTHROPIC_API_KEY   Optional. If unset, the CLI uses your existing login.
#   RUN_ID              Optional. Branch suffix; defaults to a UTC timestamp.
#   SKIP_PR=1           Do the scaffold and commit, but skip push + gh pr create.

set -euo pipefail

TARGET_PATH="${1:-.}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%d-%H%M%S)}"

# --- preconditions ----------------------------------------------------------

for cmd in claude git; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "error: '$cmd' not found in PATH" >&2
    exit 1
  }
done

if [[ "${SKIP_PR:-0}" != "1" ]] && ! command -v gh >/dev/null 2>&1; then
  echo "error: 'gh' not found in PATH (set SKIP_PR=1 to skip the pull request)" >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# The workflow starts from a clean checkout; refuse to mix in unrelated edits.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is dirty — commit or stash first" >&2
  git status --short >&2
  exit 1
fi

DEFAULT_BRANCH="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
START_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
BRANCH="context-scaffold/run-${RUN_ID}"

# --- run the skill ----------------------------------------------------------

PROMPT=$(cat <<EOF
Read and follow the instructions in \`skills/context-scaffold/SKILL.md\`
(and its \`assets/README.template.md\`) to scaffold or repair the
\`context/\` documentation tree under \`${TARGET_PATH}\`.

Follow the skill's steps exactly: inspect before writing, create only
missing directories/.gitkeep files, and never overwrite an existing
\`context/README.md\` (offer a merge instead, as the skill describes).

Do not create a branch, commit, or pull request — the calling script
handles version control. Finish by reporting which items you created
versus which already existed.
EOF
)

echo "==> Running context-scaffold skill under '${TARGET_PATH}'"
claude -p "$PROMPT" \
  --allowedTools "Read,Write,Edit,Glob,Bash(mkdir:*)"

# --- commit and open the PR -------------------------------------------------

if [[ -z "$(git status --porcelain)" ]]; then
  echo "==> context/ is already fully scaffolded — nothing to commit."
  exit 0
fi

echo "==> Changes detected:"
git status --short

git config user.name "claude[bot]"
git config user.email "claude[bot]@users.noreply.github.com"

git checkout -b "$BRANCH"
git add -A
git commit -m "Scaffold context/ folder"

if [[ "${SKIP_PR:-0}" == "1" ]]; then
  echo "==> SKIP_PR=1 — committed on '${BRANCH}', skipping push and pull request."
  exit 0
fi

git push -u origin "$BRANCH"

gh pr create \
  --base "$DEFAULT_BRANCH" \
  --head "$BRANCH" \
  --title "Scaffold context/ folder" \
  --body "$(cat <<EOF
Scaffolds the \`context/\` documentation tree under \`${TARGET_PATH}\` by running
the \`skills/context-scaffold\` skill.

Files in this branch:

\`\`\`
$(git diff --name-status "${DEFAULT_BRANCH}...${BRANCH}")
\`\`\`

Anything not listed above was already present and was left untouched.
EOF
)"

echo "==> Pull request opened against '${DEFAULT_BRANCH}'. Returning to '${START_BRANCH}'."
git checkout "$START_BRANCH"
