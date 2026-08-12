#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CALLER_PWD="$PWD"
COMPILER="$ROOT/bin/tungsten-compiler"
SOURCE="$ROOT/benchmarks/gpu/gpu_bench.w"
CACHE_DIR="${TUNGSTEN_CACHE_DIR:-$ROOT/build/cache}/gpu-bench"
BACKEND=auto
ELEMENTS=1048576
RUNS=50
WARMUP=5
STRICT=0
EMIT_ONLY=0
OUTPUT=""

usage() {
  cat <<'EOF'
Usage: tungsten gpu-bench [options]

Emit, compile, dispatch, verify, and time Tungsten's baseline GPU kernel.
Artifacts and a reproducibility record are stored under build/cache/gpu-bench.

Options:
  --backend NAME    auto or metal (default: auto)
  --elements N      f32 elements per dispatch (default: 1048576)
  --runs N          timed dispatches in each mode (default: 50)
  --warmup N        warmup dispatches (default: 5)
  --strict          disable Metal fast math
  --emit-only       compile and retain artifacts without dispatching
  --output PATH     JSON result path
  --cache-dir PATH  artifact/result root (default: build/cache/gpu-bench)
  -h, --help        show this help

The benchmark reports synchronous dispatch latency and batched throughput.
CUDA emission is supported by the compiler, but a standardized CUDA timing
host is not yet part of gpu-bench.
EOF
}

die() {
  echo "tungsten gpu-bench: $*" >&2
  exit 1
}

require_uint() {
  local name="$1"
  local value="$2"
  case "$value" in
    ''|*[!0-9]*) die "$name must be a non-negative integer, got '$value'" ;;
  esac
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --backend) shift; [[ "$#" -gt 0 ]] || die "--backend needs a value"; BACKEND="$1" ;;
    --backend=*) BACKEND="${1#--backend=}" ;;
    --elements) shift; [[ "$#" -gt 0 ]] || die "--elements needs a value"; ELEMENTS="$1" ;;
    --elements=*) ELEMENTS="${1#--elements=}" ;;
    --runs) shift; [[ "$#" -gt 0 ]] || die "--runs needs a value"; RUNS="$1" ;;
    --runs=*) RUNS="${1#--runs=}" ;;
    --warmup) shift; [[ "$#" -gt 0 ]] || die "--warmup needs a value"; WARMUP="$1" ;;
    --warmup=*) WARMUP="${1#--warmup=}" ;;
    --output) shift; [[ "$#" -gt 0 ]] || die "--output needs a value"; OUTPUT="$1" ;;
    --output=*) OUTPUT="${1#--output=}" ;;
    --cache-dir) shift; [[ "$#" -gt 0 ]] || die "--cache-dir needs a value"; CACHE_DIR="$1" ;;
    --cache-dir=*) CACHE_DIR="${1#--cache-dir=}" ;;
    --strict) STRICT=1 ;;
    --emit-only) EMIT_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option '$1' (try --help)" ;;
  esac
  shift
done

require_uint --elements "$ELEMENTS"
require_uint --runs "$RUNS"
require_uint --warmup "$WARMUP"
[[ "$ELEMENTS" -gt 0 ]] || die "--elements must be greater than zero"
[[ "$RUNS" -gt 0 ]] || die "--runs must be greater than zero"
[[ "$ELEMENTS" -le 100000000 ]] || die "--elements exceeds the 100000000 safety limit"

if [[ "$BACKEND" == auto ]]; then
  if [[ "$(uname -s)" == Darwin ]]; then
    BACKEND=metal
  else
    die "no supported benchmark backend was detected (the standardized host currently supports Metal)"
  fi
fi
[[ "$BACKEND" == metal ]] || die "unsupported backend '$BACKEND' (supported: metal)"
if [[ "$EMIT_ONLY" -ne 1 && "$(uname -s)" != Darwin ]]; then
  die "Metal dispatch requires macOS; use --emit-only to inspect artifacts"
fi
[[ -x "$COMPILER" ]] || die "no compiler at $COMPILER; run bin/tungsten bootstrap"

case "$CACHE_DIR" in
  /*) ;;
  *) CACHE_DIR="$CALLER_PWD/$CACHE_DIR" ;;
esac

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$CACHE_DIR/runs/$STAMP-$$"
RESULT_DIR="$CACHE_DIR/results"
mkdir -p "$RUN_DIR" "$RESULT_DIR"

WORK_SOURCE="$RUN_DIR/gpu_bench.w"
METAL_PATH="$RUN_DIR/gpu_bench.metal"
BINARY="$RUN_DIR/gpu_bench"
cp "$SOURCE" "$WORK_SOURCE"

echo "==> Emit + compile (Metal, release)"
TUNGSTEN_GPU_DIALECTS=none TUNGSTEN_METAL_PATH="$METAL_PATH" \
  "$ROOT/bin/tungsten" compile "$WORK_SOURCE" --release --out "$BINARY"

[[ -s "$METAL_PATH" ]] || die "compiler did not emit $METAL_PATH"
[[ -x "$BINARY" ]] || die "compiler did not build $BINARY"

if [[ "$EMIT_ONLY" -eq 1 ]]; then
  echo "emitted: $METAL_PATH"
  echo "compiled: $BINARY"
  exit 0
fi

if [[ -z "$OUTPUT" ]]; then
  OUTPUT="$RESULT_DIR/$STAMP-$$-metal.json"
elif [[ "$OUTPUT" != /* ]]; then
  OUTPUT="$CALLER_PWD/$OUTPUT"
fi
mkdir -p "$(dirname "$OUTPUT")"

GIT_COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
GIT_DIRTY=false
if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=normal 2>/dev/null)" ]]; then
  GIT_DIRTY=true
fi
DEVICE="$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Chipset Model:/{print $2; exit}')"
[[ -n "$DEVICE" ]] || DEVICE=unknown
TOOLCHAIN="$(xcodebuild -version 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
[[ -n "$TOOLCHAIN" ]] || TOOLCHAIN=unknown
COMPILER_VERSION="$("$ROOT/bin/tungsten" --version 2>/dev/null | head -n 1)"
HOST="$(uname -srvmp 2>/dev/null || uname -a)"

echo "==> Dispatch + time ($ELEMENTS elements, $RUNS runs, $WARMUP warmups)"
TUNGSTEN_GPU_BENCH_ELEMENTS="$ELEMENTS" \
TUNGSTEN_GPU_BENCH_RUNS="$RUNS" \
TUNGSTEN_GPU_BENCH_WARMUP="$WARMUP" \
TUNGSTEN_GPU_BENCH_STRICT="$STRICT" \
TUNGSTEN_GPU_BENCH_METAL="$METAL_PATH" \
TUNGSTEN_GPU_BENCH_RESULT="$OUTPUT" \
TUNGSTEN_GPU_BENCH_TIMESTAMP="$STAMP" \
TUNGSTEN_GPU_BENCH_GIT_COMMIT="$GIT_COMMIT" \
TUNGSTEN_GPU_BENCH_GIT_DIRTY="$GIT_DIRTY" \
TUNGSTEN_GPU_BENCH_SOURCE_SHA256="$(sha256_file "$SOURCE")" \
TUNGSTEN_GPU_BENCH_SIDECAR_SHA256="$(sha256_file "$METAL_PATH")" \
TUNGSTEN_GPU_BENCH_COMPILER_SHA256="$(sha256_file "$COMPILER")" \
TUNGSTEN_GPU_BENCH_COMPILER_VERSION="$COMPILER_VERSION" \
TUNGSTEN_GPU_BENCH_DEVICE="$DEVICE" \
TUNGSTEN_GPU_BENCH_TOOLCHAIN="$TOOLCHAIN" \
TUNGSTEN_GPU_BENCH_HOST="$HOST" \
TUNGSTEN_GPU_BENCH_BINARY="$BINARY" \
  "$BINARY"

[[ -s "$OUTPUT" ]] || die "benchmark did not write $OUTPUT"
echo "result: $OUTPUT"
