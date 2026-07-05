#!/bin/bash
# Comparison benchmark harness — runs Lex64 / Lex32 / Lex16 on a given
# C source file and prints a markdown table.
#
# Usage: bench_all.sh <file.c> [rounds]
#
# Like the parity test, this is shell-driven because a single .w file
# can't import multiple lexers — they share top-level constants and the
# loader hangs on the duplicates.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [ $# -lt 1 ]; then
  echo "usage: $0 <file.c> [rounds]"
  exit 1
fi
FILE="$1"
ROUNDS="${2:-200}"

# Build the per-width benchmark binaries (cached if up-to-date).
bin/tungsten compile languages/c/bench_fast.w   --out /tmp/bench_lex64 >/dev/null
bin/tungsten compile languages/c/bench_fast32.w --out /tmp/bench_lex32 >/dev/null
bin/tungsten compile languages/c/bench_fast16.w --out /tmp/bench_lex16 >/dev/null

extract_mb() { awk '/throughput:/ {print $2}' "$1"; }
extract_tokens() { awk '/tokens\/round:/ {print $2}' "$1"; }

T64=$(mktemp); T32=$(mktemp); T16=$(mktemp)
trap "rm -f $T64 $T32 $T16" EXIT

/tmp/bench_lex64 "$FILE" "$ROUNDS" > "$T64"
/tmp/bench_lex32 "$FILE" "$ROUNDS" > "$T32"
/tmp/bench_lex16 "$FILE" "$ROUNDS" > "$T16"

mb64=$(extract_mb "$T64"); tk64=$(extract_tokens "$T64")
mb32=$(extract_mb "$T32"); tk32=$(extract_tokens "$T32")
mb16=$(extract_mb "$T16"); tk16=$(extract_tokens "$T16")

bytes=$(wc -c < "$FILE" | tr -d ' ')

echo
echo "## C Lexer Comparison: $FILE"
echo
echo "Source: ${bytes} bytes, ${ROUNDS} rounds, scalar dispatch only"
echo
echo "| Variant | Throughput | Tokens/round |"
echo "|---------|-----------:|-------------:|"
echo "| Lex64   | ${mb64} MB/s | ${tk64} |"
echo "| Lex32   | ${mb32} MB/s | ${tk32} |"
echo "| Lex16   | ${mb16} MB/s | ${tk16} |"
echo

if [ "$tk64" != "$tk32" ] || [ "$tk64" != "$tk16" ]; then
  echo "WARNING: token count mismatch (Lex64=$tk64 Lex32=$tk32 Lex16=$tk16)"
  exit 1
fi
