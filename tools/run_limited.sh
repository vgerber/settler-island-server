#!/usr/bin/env bash
# Cargo's test runner (see .cargo/config.toml): every test and example binary runs under a virtual memory ceiling and
# is the kernel's first choice to kill, so a runaway allocation ends that one process instead of the desktop session.
set -e
ulimit -v "${SETTLER_TEST_VIRTUAL_MEMORY_KILOBYTES:-16000000}"
echo 1000 > /proc/self/oom_score_adj 2>/dev/null || true
exec "$@"
