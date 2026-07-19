#!/usr/bin/env bash

# A successful compiler process is not enough: callers need an executable
# artifact before publishing it into the bootstrap cache.
bootstrap_require_executable() {
  local artifact="$1"
  local log_path="$2"
  local label="${3:-command}"

  if [ -x "$artifact" ]; then
    return 0
  fi

  if [ -f "$log_path" ]; then
    cat "$log_path" >&2
  else
    printf '(no log was written at %s)\n' "$log_path" >&2
  fi
  printf 'error: %s returned success but produced no executable at %s (log: %s)\n' \
    "$label" "$artifact" "$log_path" >&2
  return 1
}
