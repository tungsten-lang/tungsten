#!/usr/bin/env bash
# Cross-language linear-algebra benchmark harness.
#
# Runs every available implementation and writes results.csv with one
# row per (implementation, N) pair. Missing toolchains are skipped with
# a warning, not an error.
#
# Usage:
#   ./run.sh                                       # default: N=4,256,2048  iters=1000,100,10
#   ./run.sh --only tungsten                       # single implementation
#   ./run.sh --sizes 4,256,2048 --iters 1000,100,10
#   ./run.sh --output /tmp/results.csv

set -euo pipefail
SCRIPT_NAME="$(basename "$0")"
cd "$(dirname "$0")"

SIZES=(4 256 2048)
ITERS=(1000 100 10)
ONLY=""
OUTPUT="results.csv"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sizes)   IFS=',' read -ra SIZES <<< "$2"; shift 2 ;;
    --iters)   IFS=',' read -ra ITERS <<< "$2"; shift 2 ;;
    --only)    ONLY="$2"; shift 2 ;;
    --output)  OUTPUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set/p' "$SCRIPT_NAME" | sed -n 's/^# *//p'; exit 0 ;;
    *)         echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ ${#SIZES[@]} -eq ${#ITERS[@]} ]] || { echo "sizes and iters must match in length" >&2; exit 1; }

echo "impl,N,K,median_ms,gflops" > "$OUTPUT"

run_impl() {
  local impl="$1" cmd="$2"
  for i in "${!SIZES[@]}"; do
    local n="${SIZES[$i]}" k="${ITERS[$i]}"
    if ! eval "$cmd" 2>/dev/null | python3 -c '
import json, sys
line = sys.stdin.readline().strip()
if not line: sys.exit(1)
d = json.loads(line)
print(f"{d[\"impl\"]},{d[\"N\"]},{d[\"K\"]},{d[\"median_ms\"]},{d[\"gflops\"]}")
' >> "$OUTPUT" 2>/dev/null; then
      echo "  [skip] $impl  N=$n  (toolchain unavailable or failed)" >&2
    else
      echo "  [done] $impl  N=$n" >&2
    fi
  done
}

want() { [[ -z "$ONLY" || "$ONLY" == "$1" ]]; }

# --- C (naive) ---
if want "c-naive" && command -v clang >/dev/null; then
  (cd c && clang -O3 -march=native -ffast-math -o /tmp/matmul_naive matmul.c) || true
  if [[ -x /tmp/matmul_naive ]]; then
    run_impl "c-naive" '/tmp/matmul_naive $n $k'
  fi
fi

# --- C + Accelerate (macOS only) ---
if want "c-accelerate" && [[ "$OSTYPE" == "darwin"* ]]; then
  (cd c && clang -O3 -framework Accelerate -o /tmp/matmul_accel matmul_accel.c) || true
  if [[ -x /tmp/matmul_accel ]]; then
    run_impl "c-accelerate" '/tmp/matmul_accel $n $k'
  fi
fi

# --- Rust ---
if want "rust-ndarray" && command -v cargo >/dev/null; then
  (cd rust && cargo build --release --quiet) || true
  if [[ -x rust/target/release/matmul ]]; then
    run_impl "rust-ndarray" 'rust/target/release/matmul $n $k'
  fi
fi

# --- Python (numpy) ---
if want "python-numpy" && command -v python3 >/dev/null; then
  if python3 -c "import numpy" 2>/dev/null; then
    run_impl "python-numpy" 'python3 python/matmul.py --N $n --K $k'
  fi
fi

# --- Julia ---
if want "julia" && command -v julia >/dev/null; then
  run_impl "julia" 'julia --project=julia julia/matmul.jl $n $k'
fi

# --- Go ---
if want "go-gonum" && command -v go >/dev/null; then
  (cd go && go run matmul.go) || true
  run_impl "go-gonum" '(cd go && go run matmul.go $n $k)'
fi

# --- Swift (Accelerate + MLX) ---
if want "swift-accelerate" && command -v swift >/dev/null; then
  (cd swift && swift build -c release --quiet) || true
  if [[ -x swift/.build/release/matmul ]]; then
    run_impl "swift-accelerate" 'swift/.build/release/matmul accelerate $n $k'
    run_impl "swift-mlx"        'swift/.build/release/matmul mlx $n $k'
  fi
fi

# --- Tungsten ---
# Compile with --fast (fast-FP + auto-vectorization), matching the C baseline's
# -O3 -march=native -ffast-math. The old form interpreted matmul.w through the
# front door — no native compile, no vectorization — which was neither fair nor
# representative.
if want "tungsten-scalar-f32" && [[ -x ../../bin/tungsten ]]; then
  ../../bin/tungsten --fast -o /tmp/tt_matmul tungsten/matmul.w >/dev/null 2>&1 || true
  if [[ -x /tmp/tt_matmul ]]; then
    run_impl "tungsten-scalar-f32" '/tmp/tt_matmul $n $k'
  fi
fi

echo ""
echo "Results written to $OUTPUT"
echo ""
column -t -s , "$OUTPUT"
