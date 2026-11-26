#!/usr/bin/env bash
# Takes an agent's commits onto the current branch: tools/merge_agent.sh <branch> [commit ...]
#
# Cherry-picks the explicit commits in the order given; without any, the commits `git cherry main <branch>` lists as
# not yet in main (by patch id), oldest first. Needs a clean working tree. Never pushes (the lead does).
# Any conflict stops with the file list and leaves the state for the lead (git reset --hard HEAD drops it).
# A pick that stages anything in .claude/, .build/, .handoffs/ or .vscode/settings.json is dropped and the script stops.
# At the end it compares the tree hash with the branch's: identical means the agent's gated tree needs no second gate.
# SETTLER_MAIN_BRANCH overrides "main". --help prints this header.
set -e
source "$(dirname "$0")/common.sh"

main_branch="${SETTLER_MAIN_BRANCH:-main}"
forbidden_pattern='^(\.claude/.*|\.build/.*|\.handoffs/.*|\.vscode/settings\.json)$'

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then print_header "$0"; exit 0; fi
if [ $# -lt 1 ]; then echo "usage: merge_agent.sh <branch> [commit ...]" >&2; exit 2; fi
branch="$1"
shift
git rev-parse --verify --quiet "$branch^{commit}" >/dev/null || { echo "$branch is not a branch or commit" >&2; exit 2; }

cd "$(git rev-parse --show-toplevel)"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "refusing: tracked files have uncommitted changes (the lead's checkout must be clean)" >&2
  git status --short --untracked-files=no >&2
  exit 1
fi

commits=("$@")
if [ ${#commits[@]} -eq 0 ]; then
  mapfile -t commits < <(git cherry "$main_branch" "$branch" | awk '$1=="+"{print $2}')
fi
if [ ${#commits[@]} -eq 0 ]; then echo "nothing to pick: $branch has no commits outside $main_branch" >&2; exit 0; fi

for commit in "${commits[@]}"; do
  echo "picking $(git log -1 --format='%h %s' "$commit")"
  if ! git cherry-pick --no-commit "$commit" >/dev/null 2>&1; then
    echo "stopping: conflicts in $commit:" >&2
    git diff --name-only --diff-filter=U >&2
    echo "resolve by hand, or drop with: git reset --hard HEAD" >&2
    exit 4
  fi
  staged="$(git diff --cached --name-only | grep -E "$forbidden_pattern" || true)"
  if [ -n "$staged" ]; then
    echo "refusing: the pick stages files that never get committed:" >&2
    echo "$staged" >&2
    git reset -q --hard HEAD
    exit 3
  fi
  if git diff --cached --quiet; then echo "  empty after applying, skipped"; continue; fi
  git commit -q -C "$commit"
done

head_tree="$(git rev-parse 'HEAD^{tree}')"
echo "tree hash: $head_tree"
if [ "$head_tree" = "$(git rev-parse "$branch^{tree}")" ]; then
  echo "tree identical to the agent's gated tree: a second gate is not needed"
else
  echo "tree differs: gate needed (tools/check.sh)"
fi
