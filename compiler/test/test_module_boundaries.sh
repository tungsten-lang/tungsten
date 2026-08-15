#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"

workers=(
  "$root/compiler/lib/driver"/*.w
  "$root/compiler/lib/emitter"/*.w
  "$root/compiler/lib/interpreter"/*.w
  "$root/compiler/lib/lexer"/*.w
  "$root/compiler/lib/lowering/literal_units"/*.w
  "$root/compiler/lib/metal_emitter"/*.w
  "$root/compiler/lib/parser"/*.w
)

for file in "${workers[@]}"; do
  lines="$(wc -l < "$file" | tr -d ' ')"
  if (( lines > 1800 )); then
    echo "worker exceeds 1800 lines: $file ($lines)" >&2
    exit 1
  fi
done

while read -r relative limit; do
  lines="$(wc -l < "$root/$relative" | tr -d ' ')"
  if (( lines > limit )); then
    echo "orchestrator exceeds boundary: $relative ($lines > $limit)" >&2
    exit 1
  fi
done <<'LIMITS'
compiler/lib/emitter.w 100
compiler/lib/interpreter.w 100
compiler/lib/lexer.w 100
compiler/lib/metal_emitter.w 500
compiler/lib/parser.w 100
compiler/lib/lowering/literals.w 1300
compiler/tungsten.w 700
compiler/tungsten_driver.w 900
LIMITS

# Type hints are declarations, not ordinary comments: they must move with
# their function. Leaving these in lexer.w silently boxes the raw buffers.
awk '
  /^## i64\[\]: lc, tokens, indents$/ { arrays = 1; next }
  /^## i64: count$/ { count = 1; next }
  /^-> / {
    if ($0 == "-> tungsten_tokenize_fast64(lc, count, tokens, indents)" && arrays && count) found = 1
    arrays = 0; count = 0
  }
  END { exit !found }
' "$root/compiler/lib/lexer/fast64.w" || {
  echo "packed lexer parameter annotations must accompany the worker function" >&2
  exit 1
}

echo "compiler module boundaries: PASS"
