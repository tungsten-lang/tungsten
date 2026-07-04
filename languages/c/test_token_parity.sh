#!/bin/bash
# Token-stream parity test: tokenize the same C source with all three
# lexer variants (Lex64 / Lex32 / Lex16) and assert byte-identical output.
#
# Implementation note: a single .w file can't import all three lexers
# because they share top-level constant names — the loader hangs on the
# duplicate definitions. So each lexer dumps its tokens to its own file
# and we diff externally.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

OUT64=$(mktemp)
OUT32=$(mktemp)
OUT16=$(mktemp)
trap "rm -f $OUT64 $OUT32 $OUT16 /tmp/dt64 /tmp/dt32 /tmp/dt16" EXIT

bin/tungsten compile languages/c/dump_tokens64.w --out /tmp/dt64 >/dev/null
bin/tungsten compile languages/c/dump_tokens32.w --out /tmp/dt32 >/dev/null
bin/tungsten compile languages/c/dump_tokens16.w --out /tmp/dt16 >/dev/null

/tmp/dt64 > "$OUT64"
/tmp/dt32 > "$OUT32"
/tmp/dt16 > "$OUT16"

if ! diff -q "$OUT64" "$OUT32" >/dev/null; then
  echo "FAIL: Lex64 vs Lex32 divergence"
  diff "$OUT64" "$OUT32" | head -20
  exit 1
fi
if ! diff -q "$OUT64" "$OUT16" >/dev/null; then
  echo "FAIL: Lex64 vs Lex16 divergence"
  diff "$OUT64" "$OUT16" | head -20
  exit 1
fi

count=$(wc -l < "$OUT64" | tr -d ' ')
echo "test_token_parity: PASS ($count tokens identical across Lex64 / Lex32 / Lex16)"
