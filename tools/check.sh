#!/usr/bin/env bash
# The single place that documents the gates: tools/check.sh [--force] [mode]
#
# Modes:
#   (none) = full  cargo fmt --check, clippy on all targets with -D warnings, cargo test --workspace (doc tests included).
#   quick          clippy and the tests of the crates whose files changed against main (falls back to full when none).
#   fmt            cargo fmt --check only.
#   db             the full gate plus the Postgres-backed server tests: starts this project's own container
#                  settler-island-db (docker compose, port 6436) if it is not running and stops it again afterwards;
#                  concurrent db gates from several worktrees take turns (a lock in the git common dir).
#                Fails fast, with the docker output, when docker or the container does not come up.
# Full mode exports SETTLER_REQUIRE_GODOT=1: the Godot tests must run, a missing Godot is a failure, not a skip.
# The repository is the git top level of the current directory, so running this inside an agent worktree gates (and
# stamps) that worktree, not the checkout the script file lives in.
# Tests run under tools/run_limited.sh (memory ceiling, .cargo/config.toml). Output is filtered to failures and totals;
# a failing step prints its last 60 lines, saves its full log as .build/logs/<step>-<time>.log (path printed), and the
# script exits nonzero.
# Stamps: a green full run is recorded in .build/gate-stamps with the hash of the exact tree (tracked and untracked
# files, uncommitted changes included); the same tree is not gated twice. --force runs it anyway.
# --help prints this header; --self-test checks that the repository is the current worktree.
set -euo pipefail
source "$(dirname "$0")/common.sh"

if [ "${1:-}" = "--self-test" ]; then
  script="$(cd "$(dirname "$0")" && pwd)/check.sh"
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' EXIT
  git init -q -b main "$scratch/repo"
  git -C "$scratch/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "chore: Start"
  git -C "$scratch/repo" worktree add -q -b agent/one "$scratch/worktree"
  resolved="$(cd "$scratch/worktree" && "$script" --print-repository)"
  if [ "$resolved" != "$(cd "$scratch/worktree" && pwd -P)" ]; then echo "self-test failed: resolved $resolved" >&2; exit 1; fi
  echo "check.sh self-test passed"
  exit 0
fi

cd "$(repository_root)"
main_branch="${SETTLER_MAIN_BRANCH:-main}"

force=0
mode="full"
for argument in "$@"; do
  case "$argument" in
    --force) force=1 ;;
    --help|-h) print_header "$0"; exit 0 ;;
    --print-repository) pwd -P; exit 0 ;;
    full|quick|fmt|db) mode="$argument" ;;
    *) echo "unknown argument $argument" >&2; exit 2 ;;
  esac
done

if command -v sccache >/dev/null 2>&1; then export RUSTC_WRAPPER="${RUSTC_WRAPPER:-sccache}"; fi

tree_hash() {
  local index
  index="$(mktemp)"
  cp "$(git rev-parse --git-path index)" "$index"
  GIT_INDEX_FILE="$index" git add -A >/dev/null 2>&1
  GIT_INDEX_FILE="$index" git write-tree
  rm -f "$index"
}

mkdir -p .build
stamps=.build/gate-stamps
hash="$(tree_hash)"
if [ "$mode" = "full" ] && [ "$force" -eq 0 ] && grep -qx "full $hash" "$stamps" 2>/dev/null; then
  echo "check.sh full: tree $hash already green, skipped (--force reruns)"
  exit 0
fi

start_seconds=$SECONDS
mkdir -p .build/logs
log="$(mktemp .build/logs/step.XXXXXX)"
trap 'rm -f "$log"' EXIT

run_step() {
  local name="$1"; shift
  local step_start=$SECONDS
  if "$@" >"$log" 2>&1; then
    echo "$name ok ($((SECONDS - step_start)) s)"
  else
    local saved=".build/logs/${name%% *}-$(date +%Y%m%d-%H%M%S).log"
    cp "$log" "$saved"
    tail -n 60 "$log"
    echo "$name FAILED ($((SECONDS - step_start)) s), full log: $saved"
    exit 1
  fi
}

test_totals() {
  grep -E "^test result:" "$log" | awk '{passed += $4; failed += $6; ignored += $8} END {printf "tests: %d passed, %d failed, %d ignored\n", passed, failed, ignored}'
}

# The Postgres tests run exactly when SETTLER_TEST_DATABASE_URL is set (they skip with a captured notice otherwise).
postgres_note() {
  if [ -n "${SETTLER_TEST_DATABASE_URL:-}" ]; then
    echo "postgres tests: ran against $SETTLER_TEST_DATABASE_URL"
  else
    echo "postgres tests: skipped (tools/check.sh db runs them)"
  fi
}

changed_packages() {
  { git diff --name-only "$main_branch"...HEAD; git diff --name-only HEAD; git ls-files --others --exclude-standard; } \
    | { grep -oE '^settler_island_[a-z_]+' || true; } | sort -u
}

case "$mode" in
  fmt)
    run_step "fmt" cargo fmt --all -- --check
    ;;
  quick)
    packages="$(changed_packages)"
    if [ -z "$packages" ]; then
      echo "no crate changed: running full gate"
      exec "$0" --force full
    fi
    package_arguments=()
    for package in $packages; do package_arguments+=(-p "$package"); done
    run_step "clippy (${packages//$'\n'/ })" cargo clippy "${package_arguments[@]}" --all-targets -- -D warnings
    run_step "tests" cargo test "${package_arguments[@]}"
    test_totals
    ;;
  db)
    # Worktrees share one settler-island-db: a second db gate waits, so neither stops the container under the other.
    exec 9>"$(git rev-parse --git-common-dir)/settler-db-gate.lock"
    if ! flock -n 9; then
      echo "db mode: another db gate holds the database, waiting"
      flock 9
    fi
    started_database=0
    if [ "$(docker inspect -f '{{.State.Running}}' settler-island-db 2>/dev/null)" != "true" ]; then
      if ! docker_output="$(docker compose up -d db 2>&1)"; then
        echo "db mode: docker compose could not start settler-island-db:" >&2
        echo "$docker_output" >&2
        exit 1
      fi
      started_database=1
    fi
    database_ready=0
    for _ in $(seq 1 30); do
      if docker exec settler-island-db pg_isready -U settler >/dev/null 2>&1; then database_ready=1; break; fi
      sleep 1
    done
    if [ "$database_ready" -eq 0 ]; then
      echo "db mode: settler-island-db is not accepting connections after 30 s (docker logs settler-island-db)" >&2
      if [ "$started_database" -eq 1 ]; then docker compose stop db >/dev/null 2>&1 || true; fi
      exit 1
    fi
    export SETTLER_TEST_DATABASE_URL="${SETTLER_TEST_DATABASE_URL:-postgres://settler:settler@127.0.0.1:6436/settler_island}"
    database_status=0
    "$0" --force full || database_status=$?
    if [ "$started_database" -eq 1 ]; then docker compose stop db >/dev/null 2>&1; fi
    exit "$database_status"
    ;;
  full)
    export SETTLER_REQUIRE_GODOT=1
    run_step "fmt" cargo fmt --all -- --check
    run_step "clippy" cargo clippy --workspace --all-targets -- -D warnings
    run_step "tests" cargo test --workspace
    test_totals
    postgres_note
    echo "full $hash" >> "$stamps"
    ;;
esac
echo "check.sh $mode: $((SECONDS - start_seconds)) s in total"
