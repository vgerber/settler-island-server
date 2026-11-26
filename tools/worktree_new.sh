#!/usr/bin/env bash
# Creates an agent worktree: tools/worktree_new.sh <tag> [--base <commit>]
#
# - worktree .claude/worktrees/<tag> on a new branch agent/<tag>, from local main (or --base), in the main copy
# - .build/<tag> (created) linked as <worktree>/target, so the build directory is deleted with the agent
# - durable handoff .handoffs/<tag>.md at the repository root of the main copy (git-ignored, survives the worktree)
# Prints three lines for the agent brief: worktree path, handoff path, the prove_test_bites.sh command.
# SETTLER_MAIN_BRANCH overrides the branch name "main". Never deletes anything.
# --help prints this header; --self-test runs the script against a temporary repository.
set -e
source "$(dirname "$0")/common.sh"

main_branch="${SETTLER_MAIN_BRANCH:-main}"

usage() { print_header "$0"; }

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then usage; exit 0; fi

if [ "$1" = "--self-test" ]; then
  script="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' EXIT
  git init -q -b main "$scratch/repo"
  git -C "$scratch/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "chore: Start"
  cd "$scratch/repo"
  "$script" selftest-tag >/dev/null
  test -d "$scratch/repo/.claude/worktrees/selftest-tag"
  test -L "$scratch/repo/.claude/worktrees/selftest-tag/target"
  test -f "$scratch/repo/.handoffs/selftest-tag.md"
  if "$script" selftest-tag 2>/dev/null; then echo "self-test failed: duplicate tag accepted" >&2; exit 1; fi
  echo "worktree_new.sh self-test passed"
  exit 0
fi

tag=""
base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="${2:?--base needs a commit}"; shift 2 ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) if [ -n "$tag" ]; then echo "only one tag allowed" >&2; exit 2; fi; tag="$1"; shift ;;
  esac
done
if [ -z "$tag" ]; then usage >&2; exit 2; fi
if ! [[ "$tag" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then echo "tag may only hold letters, digits, . _ -" >&2; exit 2; fi

root="$(git rev-parse --git-common-dir)"
root="$(cd "$root/.." && pwd)"
base="${base:-$main_branch}"
worktree="$root/.claude/worktrees/$tag"
build="$root/.build/$tag"
handoff="$root/.handoffs/$tag.md"

if [ -e "$worktree" ]; then echo "worktree $worktree already exists" >&2; exit 1; fi
if [ -e "$handoff" ]; then echo "handoff $handoff already exists (tag reused?)" >&2; exit 1; fi
if ! git -C "$root" rev-parse --verify --quiet "$base^{commit}" >/dev/null; then echo "base $base is not a commit" >&2; exit 1; fi

mkdir -p "$root/.claude/worktrees" "$build" "$root/.handoffs"
git -C "$root" worktree add -q -b "agent/$tag" "$worktree" "$base"
ln -s "$build" "$worktree/target"

cat > "$handoff" <<TEMPLATE
# Handoff $tag
Goal: <one line and the plan section>
Branch: agent/$tag   Worktree: .claude/worktrees/$tag   Base: $(git -C "$root" rev-parse --short "$base")

## Commits
<id, subject, gated tree hash, gate mode and result with test counts>

## Done
-

## Remaining steps
1.

## Hypothesis with evidence
-

## Dead ends
-

## Pins, goldens, regression files changed
-

## Decisions needed
-
TEMPLATE

echo "worktree: $worktree"
echo "handoff: $handoff"
echo "sabotage check: tools/prove_test_bites.sh --help"
