#!/usr/bin/env bash
# The single place that documents the gates: tools/check.sh [--force] [mode]
#
# Modes:
#   (none) = full  cargo fmt --check, clippy on all targets with -D warnings, cargo test --workspace (doc tests included).
#   quick          clippy and the tests of the crates whose files changed against main (falls back to full when none).
#   fmt            cargo fmt --check only.
#   db             the full gate plus the Postgres-backed server tests: starts this project's own container
#                  settler-island-db (docker compose, port 6436) if it is not running and stops it again afterwards.
# Tests run under tools/run_limited.sh (memory ceiling, .cargo/config.toml). Output is filtered to failures and totals;
# a failing step prints its last 60 lines and the script exits nonzero.
# Stamps: a green full run is recorded in .build/gate-stamps with the hash of the exact tree (tracked and untracked
# files, uncommitted changes included); the same tree is not gated twice. --force runs it anyway.
# --help prints this header.
set -euo pipefail
# sqlx macros compile against the committed .sqlx cache, never a live database.
export SQLX_OFFLINE="${SQLX_OFFLINE:-true}"

repository="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository"
main_branch="${SETTLER_MAIN_BRANCH:-main}"

force=0
mode="full"
for argument in "$@"; do
  case "$argument" in
    --force) force=1 ;;
    --help|-h) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

run_step() {
  local name="$1"; shift
  local step_start=$SECONDS
  if "$@" >"$log" 2>&1; then
    echo "$name ok ($((SECONDS - step_start)) s)"
  else
    tail -n 60 "$log"
    echo "$name FAILED ($((SECONDS - step_start)) s)"
    exit 1
  fi
}

test_totals() {
  grep -E "^test result:" "$log" | awk '{passed += $4; failed += $6; ignored += $8} END {printf "tests: %d passed, %d failed, %d ignored\n", passed, failed, ignored}'
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
    started_database=0
    if [ "$(docker inspect -f '{{.State.Running}}' settler-island-db 2>/dev/null)" != "true" ]; then
      docker compose up -d db >/dev/null 2>&1
      started_database=1
    fi
    for _ in $(seq 1 30); do
      if docker exec settler-island-db pg_isready -U settler >/dev/null 2>&1; then break; fi
      sleep 1
    done
    export SETTLER_TEST_DATABASE_URL="${SETTLER_TEST_DATABASE_URL:-postgres://settler:settler@127.0.0.1:6436/settler_island}"
    database_status=0
    "$0" --force full || database_status=$?
    if [ "$started_database" -eq 1 ]; then docker compose stop db >/dev/null 2>&1; fi
    exit "$database_status"
    ;;
  full)
    run_step "fmt" cargo fmt --all -- --check
    run_step "clippy" cargo clippy --workspace --all-targets -- -D warnings
    run_step "tests" cargo test --workspace
    test_totals
    echo "full $hash" >> "$stamps"
    ;;
esac
echo "check.sh $mode: $((SECONDS - start_seconds)) s in total"
