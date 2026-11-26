#!/usr/bin/env bash
# Proves a test bites: tools/prove_test_bites.sh -c '<test command>' <sabotage.patch> [<sabotage.patch> ...]
#
# Applies the patches in order (git apply, relative to the repository root; write one with `git diff` after breaking
# the fix by hand, or `git diff -R` of the fix), runs the test command once and expects it to FAIL. Exit 0 = the test
# bit (it failed under sabotage). Exit 1 = the test still passed, so it does not guard the fix. Exit 2 = usage or a patch
# that does not apply. Every touched file is saved first and restored from the copy in a trap (also on Ctrl-C or error),
# files a patch created are removed, and the script checks that `git status` and `git diff` match their state before.
# Uncommitted work in the touched files is safe. Example:
#   tools/prove_test_bites.sh -c 'cargo test -p settler_island_game longest_road' .build/revert-fix.patch
# --help prints this header; --self-test runs against a temporary repository.
set -e
source "$(dirname "$0")/common.sh"

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then print_header "$0"; exit 0; fi

if [ "$1" = "--self-test" ]; then
  script="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' EXIT
  git init -q -b main "$scratch/repo"
  cd "$scratch/repo"
  echo good > value.txt
  git add value.txt
  git -c user.name=t -c user.email=t@t commit -q -m "chore: Start"
  echo bad > value.txt
  git diff > "$scratch/break.patch"
  git checkout -q value.txt
  checker='test "$(cat value.txt)" = good'
  if ! "$script" -c "$checker" "$scratch/break.patch" >/dev/null; then echo "self-test failed: a biting test was rejected" >&2; exit 1; fi
  test "$(cat value.txt)" = good || { echo "self-test failed: file not restored" >&2; exit 1; }
  if "$script" -c "true" "$scratch/break.patch" >/dev/null 2>&1; then echo "self-test failed: a test that never fails was accepted" >&2; exit 1; fi
  test "$(cat value.txt)" = good || { echo "self-test failed: file not restored after a pass" >&2; exit 1; }
  if "$script" -c "$checker" "$scratch/missing.patch" >/dev/null 2>&1; then echo "self-test failed: missing patch accepted" >&2; exit 1; fi
  echo "prove_test_bites.sh self-test passed"
  exit 0
fi

test_command=""
patches=()
while [ $# -gt 0 ]; do
  case "$1" in
    -c) test_command="${2:?-c needs a test command}"; shift 2 ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) patches+=("$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")"); shift ;;
  esac
done
if [ -z "$test_command" ] || [ ${#patches[@]} -eq 0 ]; then print_header "$0" >&2; exit 2; fi
for patch in "${patches[@]}"; do
  if [ ! -f "$patch" ]; then echo "patch $patch not found" >&2; exit 2; fi
done

cd "$(repository_root)"
backup="$(mktemp -d)"
before="$(git status --porcelain=v1 --untracked-files=no; git diff | sha256sum)"
touched=()

restore() {
  local file
  for file in "${touched[@]}"; do
    if [ -e "$backup/saved/$file" ]; then
      mkdir -p "$(dirname "$file")"
      cp -p "$backup/saved/$file" "$file"
    else
      rm -f "$file"
    fi
  done
  rm -rf "$backup"
}
trap restore EXIT

for patch in "${patches[@]}"; do
  while IFS= read -r file; do
    touched+=("$file")
    if [ -e "$file" ]; then mkdir -p "$backup/saved/$(dirname "$file")"; cp -p "$file" "$backup/saved/$file"; fi
  done < <(git apply --numstat "$patch" | awk -F'\t' '{print $3}')
  git apply "$patch" || { echo "patch $patch does not apply" >&2; exit 2; }
done

echo "sabotage applied (${#patches[@]} patch(es)); running: $test_command"
if bash -c "$test_command" >"$backup/output.log" 2>&1; then
  tail -n 20 "$backup/output.log"
  echo "NOT PROVEN: the test passed with the fix sabotaged" >&2
  result=1
else
  echo "proven: the test failed under sabotage"
  result=0
fi

restore
trap - EXIT
after="$(git status --porcelain=v1 --untracked-files=no; git diff | sha256sum)"
if [ "$before" != "$after" ]; then echo "restore left a different git state, check git diff" >&2; exit 1; fi
exit "$result"
