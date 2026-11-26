#!/usr/bin/env bash
# Sourced by the other tools: print_header <script> prints its leading comment block (after the shebang).
# repository_root prints the top level of the checkout (or agent worktree) the current directory is in.

print_header() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$1"
}

repository_root() {
  git rev-parse --show-toplevel
}
