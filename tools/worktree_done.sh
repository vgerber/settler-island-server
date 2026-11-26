#!/usr/bin/env bash
# Removes a finished agent worktree: tools/worktree_done.sh <tag> [--force]
#
# Refuses (exit 1) when the worktree has uncommitted changes, when a process runs inside it, or when it holds commits
# that are neither in main (by patch id, git cherry) nor in any remote branch. --force skips these refusals.
# Then: copies the handoff to <root>/.handoffs/<tag>.md if missing (from the worktree, else a stub), unlocks and removes
# the worktree, deletes .build/<tag>, and deletes its branch when every commit is in main (never with --force).
# Only deletes the worktree and .build/<tag> it was asked about. SETTLER_MAIN_BRANCH overrides "main".
# --help prints this header; --self-test runs against a temporary repository.
set -e
source "$(dirname "$0")/common.sh"

main_branch="${SETTLER_MAIN_BRANCH:-main}"

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then print_header "$0"; exit 0; fi

if [ "$1" = "--self-test" ]; then
  here="$(cd "$(dirname "$0")" && pwd)"
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' EXIT
  git init -q -b main "$scratch/repo"
  cd "$scratch/repo"
  git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "chore: Start"
  "$here/worktree_new.sh" one >/dev/null
  echo x > .claude/worktrees/one/file
  if "$here/worktree_done.sh" one 2>/dev/null; then echo "self-test failed: dirty worktree removed" >&2; exit 1; fi
  git -C .claude/worktrees/one add file
  git -C .claude/worktrees/one -c user.name=t -c user.email=t@t commit -q -m "feat: X"
  if "$here/worktree_done.sh" one 2>/dev/null; then echo "self-test failed: unmerged commit lost" >&2; exit 1; fi
  "$here/worktree_done.sh" one --force >/dev/null
  test ! -e .claude/worktrees/one
  test ! -e .build/one
  test -f .handoffs/one.md
  git rev-parse --verify --quiet agent/one >/dev/null
  "$here/worktree_new.sh" two >/dev/null
  "$here/worktree_done.sh" two >/dev/null
  if git rev-parse --verify --quiet agent/two >/dev/null; then echo "self-test failed: merged branch kept" >&2; exit 1; fi
  echo "worktree_done.sh self-test passed"
  exit 0
fi

tag=""
force=0
for argument in "$@"; do
  case "$argument" in
    --force) force=1 ;;
    -*) echo "unknown option $argument" >&2; exit 2 ;;
    *) tag="$argument" ;;
  esac
done
if [ -z "$tag" ]; then echo "usage: worktree_done.sh <tag> [--force]" >&2; exit 2; fi

root="$(git rev-parse --git-common-dir)"
root="$(cd "$root/.." && pwd)"
worktree="$root/.claude/worktrees/$tag"
build="$root/.build/$tag"
handoff="$root/.handoffs/$tag.md"

if [ ! -d "$worktree" ]; then echo "no worktree at $worktree" >&2; exit 1; fi
real_worktree="$(cd "$worktree" && pwd -P)"
case "$(pwd -P)/" in "$real_worktree/"*) echo "run this from outside the worktree" >&2; exit 1 ;; esac

branch="$(git -C "$worktree" rev-parse --abbrev-ref HEAD)"
unmerged="$(git -C "$worktree" cherry "$main_branch" HEAD | awk '$1=="+"{print $2}')"

unpushed=""
for commit in $unmerged; do
  if [ -z "$(git -C "$root" branch -r --contains "$commit" 2>/dev/null)" ]; then unpushed="$unpushed $commit"; fi
done

problems=""
dirty="$(git -C "$worktree" status --short | grep -v "^?? target$" || true)"
if [ -n "$dirty" ]; then problems="uncommitted changes:
$dirty
"; fi
if [ -n "$unpushed" ]; then problems="${problems}commits in no remote branch and not in $main_branch:$unpushed
"; fi
for process_directory in /proc/[0-9]*; do
  process_cwd="$(readlink "$process_directory/cwd" 2>/dev/null || true)"
  case "$process_cwd/" in "$real_worktree/"*) problems="${problems}process ${process_directory#/proc/} runs inside the worktree
" ;; esac
done

if [ -n "$problems" ] && [ "$force" -eq 0 ]; then
  printf 'refusing to remove %s:\n%s(use --force to remove anyway)\n' "$tag" "$problems" >&2
  exit 1
fi

mkdir -p "$root/.handoffs"
if [ ! -f "$handoff" ]; then
  if [ -f "$worktree/.handoffs/$tag.md" ]; then
    cp "$worktree/.handoffs/$tag.md" "$handoff"
  else
    { echo "# Handoff $tag (written by worktree_done.sh, none existed)"; echo "Branch: $branch"; echo "Last commits:"; git -C "$worktree" log -5 --format='- %h %s'; } > "$handoff"
  fi
  echo "handoff written to $handoff"
fi

git -C "$root" worktree unlock "$worktree" 2>/dev/null || true
git -C "$root" worktree remove --force "$worktree"
if [ -d "$build" ]; then rm -rf "$build"; fi
if [ -z "$unmerged" ] && [ "$force" -eq 0 ] && [ "$branch" != "HEAD" ] && [ "$branch" != "$main_branch" ]; then
  git -C "$root" branch -D "$branch" >/dev/null
  echo "deleted branch $branch (all commits in $main_branch)"
fi
echo "removed worktree $worktree and $build"
