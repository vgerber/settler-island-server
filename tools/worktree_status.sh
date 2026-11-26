#!/usr/bin/env bash
# Lists every git worktree for the daily cleanup: tools/worktree_status.sh
#
# Columns: tag (directory name), branch, ahead (commits not in main by patch id, git cherry, so cherry-picked commits
# count as merged), dirty (uncommitted changes, the target link ignored), build (size of .build/<tag>), last commit age,
# locked, handoff (.handoffs/<tag>.md exists). Read-only. SETTLER_MAIN_BRANCH overrides "main".
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
  git -C .claude/worktrees/one add file
  git -C .claude/worktrees/one -c user.name=t -c user.email=t@t commit -q -m "feat: X"
  echo y > .claude/worktrees/one/other
  output="$("$here/worktree_status.sh")"
  echo "$output" | grep -E '^one +agent/one +1 +dirty' >/dev/null || { echo "self-test failed:"; echo "$output"; exit 1; }
  git -c user.name=t -c user.email=t@t cherry-pick agent/one >/dev/null
  output="$("$here/worktree_status.sh")"
  echo "$output" | grep -E '^one +agent/one +0 ' >/dev/null || { echo "self-test failed after cherry-pick:"; echo "$output"; exit 1; }
  echo "worktree_status.sh self-test passed"
  exit 0
fi

root="$(git rev-parse --git-common-dir)"
root="$(cd "$root/.." && pwd)"

print_row() { printf '%-28s %-34s %5s %-6s %8s %-14s %-6s %s\n' "$@"; }

print_row tag branch ahead dirty build "last commit" locked handoff

emit_worktree() {
  local path="$1" branch="$2" locked="$3"
  [ -n "$path" ] || return 0
  local tag ahead dirty build age handoff
  tag="$(basename "$path")"
  if [ "$path" = "$root" ]; then tag="(main copy)"; fi
  if [ -d "$path" ]; then
    ahead="$(git -C "$path" cherry "$main_branch" HEAD 2>/dev/null | grep -c '^+' || true)"
    dirty="$(git -C "$path" status --short 2>/dev/null | grep -v '^?? target$' | head -1)"
    if [ -n "$dirty" ]; then dirty=dirty; else dirty=clean; fi
    age="$(git -C "$path" log -1 --format=%cr 2>/dev/null | sed 's/ ago//')"
  else
    ahead="?"; dirty="gone"; age="?"
  fi
  build="-"
  if [ -d "$root/.build/$tag" ]; then build="$(du -sh "$root/.build/$tag" 2>/dev/null | cut -f1)"; fi
  handoff=no
  if [ -f "$root/.handoffs/$tag.md" ]; then handoff=yes; fi
  print_row "$tag" "${branch:-detached}" "$ahead" "$dirty" "$build" "$age" "$locked" "$handoff"
}

path=""; branch=""; locked="no"
while IFS= read -r line; do
  case "$line" in
    "worktree "*) emit_worktree "$path" "$branch" "$locked"; path="${line#worktree }"; branch=""; locked="no" ;;
    "branch "*) branch="${line#branch refs/heads/}" ;;
    "locked"*) locked="yes" ;;
  esac
done < <(git -C "$root" worktree list --porcelain)
emit_worktree "$path" "$branch" "$locked"
