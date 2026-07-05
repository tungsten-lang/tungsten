#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR="${OUT_DIR:-/tmp/tungsten-mlton-bench}"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"

BENCHES=("fib" "tak")

usage() {
  cat <<'EOF'
Usage: benchmarks/mlton/run.sh [bench]

Runs the current Tungsten ports of selected MLton benchmarks.

Available benches: fib tak

Environment:
  OUT_DIR    Directory for compiled binaries. Default: /tmp/tungsten-mlton-bench
  TUNGSTEN   Tungsten compiler path. Default: bin/tungsten-compiler
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" != "" ]]; then
  BENCHES=("$1")
fi

mkdir -p "$OUT_DIR"

for bench in "${BENCHES[@]}"; do
  src="$ROOT/benchmarks/mlton/tungsten/$bench.w"
  out="$OUT_DIR/$bench"

  if [[ ! -f "$src" ]]; then
    echo "Unknown benchmark: $bench" >&2
    usage >&2
    exit 1
  fi

  echo "== $bench =="
  "$TUNGSTEN" compile --release "$src" --out "$out"
  /usr/bin/time -p "$out"
  echo
done
