#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bootstrap-artifact.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

. "$ROOT/bin/commands/bootstrap_helpers.sh"

log_path="$TMP/stage1.log"
printf 'compiler claimed success\n' > "$log_path"

set +e
output="$(bootstrap_require_executable \
  "$TMP/missing-stage1" "$log_path" "stage 1 (C VM)" 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  printf 'FAIL: missing stage-1 executable was accepted\n' >&2
  exit 1
fi
if ! grep -Fq 'compiler claimed success' <<<"$output"; then
  printf 'FAIL: stage-1 log was not shown\n%s\n' "$output" >&2
  exit 1
fi
if ! grep -Fq 'returned success but produced no executable' <<<"$output"; then
  printf 'FAIL: missing-artifact diagnosis was not shown\n%s\n' "$output" >&2
  exit 1
fi

stage1="$TMP/stage1"
printf '#!/usr/bin/env bash\nexit 0\n' > "$stage1"
chmod 755 "$stage1"
bootstrap_require_executable "$stage1" "$log_path" "stage 1 (C VM)"

printf 'bootstrap stage-1 artifact contract: ok\n'
