#!/bin/sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PACKAGE_ROOT=$(CDPATH= cd -- "$SELF_DIR/../.." && pwd)
REPO_ROOT=$(CDPATH= cd -- "$PACKAGE_ROOT/../.." && pwd)
DEFAULT_KERNEL_SOURCE="$PACKAGE_ROOT/lib/metaflip/kernels/simd/simdgroup_777.w"
KERNEL_SOURCE=${METAFLIP_777_KERNEL_SOURCE:-$DEFAULT_KERNEL_SOURCE}
HOST_SOURCE="$SELF_DIR/metaflip_cuda_777.cpp"
SEED="$PACKAGE_ROOT/lib/metaflip/seeds/gf2/matmul_7x7_rank247_d3094_three_flip_density_gf2.txt"

OUT=/tmp/metaflip-cuda-777
BUILD_DIR=${TMPDIR:-/tmp}/metaflip-cuda-777-build
EMIT_ONLY=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --out)
      [ "$#" -ge 2 ] || { echo "build_777.sh: --out requires a path" >&2; exit 2; }
      OUT=$2
      shift 2
      ;;
    --build-dir)
      [ "$#" -ge 2 ] || { echo "build_777.sh: --build-dir requires a path" >&2; exit 2; }
      BUILD_DIR=$2
      shift 2
      ;;
    --emit-only)
      EMIT_ONLY=1
      shift
      ;;
    -h|--help)
      echo "usage: cloud/cuda/build_777.sh [--out PATH] [--build-dir PATH] [--emit-only]"
      exit 0
      ;;
    *)
      echo "build_777.sh: unknown option $1" >&2
      exit 2
      ;;
  esac
done

TUNGSTEN=${METAFLIP_TUNGSTEN:-$REPO_ROOT/bin/tungsten}
if [ ! -x "$TUNGSTEN" ]; then
  TUNGSTEN=$(command -v tungsten 2>/dev/null || true)
fi
if [ -z "$TUNGSTEN" ] || [ ! -x "$TUNGSTEN" ]; then
  echo "build_777.sh: Tungsten compiler not found; set METAFLIP_TUNGSTEN" >&2
  exit 1
fi
if [ ! -f "$KERNEL_SOURCE" ] || [ ! -f "$HOST_SOURCE" ] || [ ! -f "$SEED" ]; then
  echo "build_777.sh: incomplete tungsten-metaflip source checkout" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"
CANONICAL_STEM="$BUILD_DIR/simdgroup_777_canonical"
SCAN_STEM="$BUILD_DIR/simdgroup_777_scan_kernel"
HASH_STEM="$BUILD_DIR/simdgroup_777_hash_kernel"

# Emit only the canonical @gpu section.  The remainder of simdgroup_777.w is
# its Metal host relay; including it would unnecessarily bind this cloud build
# to core/metal.  The marker is part of the checked package source.
awk '/^# ---------------- host ----------------$/ { found=1; exit } { print } END { if (!found) exit 3 }' \
  "$KERNEL_SOURCE" > "$CANONICAL_STEM.w"

# The split kernels are constant-mode specializations of that one canonical
# Tungsten source, never independently maintained copies.  Fail closed when
# its mode-control geometry changes so these two mechanical substitutions are
# reviewed before another cloud build can proceed.
SIGNATURE_COUNT=$(grep -c '@gpu fn flipwalk_simd(' "$CANONICAL_STEM.w")
MODE_ASSIGN_COUNT=$(grep -c 'mode = params\[6\] ## i32' "$CANONICAL_STEM.w")
SCAN_BRANCH_COUNT=$(grep -c 'if mode == 0' "$CANONICAL_STEM.w")
HASH_BRANCH_COUNT=$(grep -c 'if mode == 1' "$CANONICAL_STEM.w")
HEAD_DECL_COUNT=$(grep -c 'heads = gpu.shared_i32(1536)' "$CANONICAL_STEM.w")
NEXT_DECL_COUNT=$(grep -c 'nexts = gpu.shared_i32(1080)' "$CANONICAL_STEM.w")
if [ "$SIGNATURE_COUNT" -ne 1 ] || [ "$MODE_ASSIGN_COUNT" -ne 1 ] || \
   [ "$SCAN_BRANCH_COUNT" -ne 1 ] || [ "$HASH_BRANCH_COUNT" -ne 7 ] || \
   [ "$HEAD_DECL_COUNT" -ne 1 ] || [ "$NEXT_DECL_COUNT" -ne 1 ]; then
  echo "build_777.sh: canonical mode/shared-memory structure changed; refusing specialization" >&2
  exit 1
fi

sed -e 's/@gpu fn flipwalk_simd(/@gpu fn flipwalk_simd_scan(/' \
    -e 's/mode = params\[6\] ## i32/mode = 0 ## i32/' \
    "$CANONICAL_STEM.w" > "$SCAN_STEM.w"
sed -e 's/@gpu fn flipwalk_simd(/@gpu fn flipwalk_simd_hash(/' \
    -e 's/mode = params\[6\] ## i32/mode = 1 ## i32/' \
    "$CANONICAL_STEM.w" > "$HASH_STEM.w"

emit_variant() {
  STEM=$1
  KERNEL_NAME=$2
  MODE_VALUE=$3

  TUNGSTEN_GPU_DIALECTS=cuda \
  TUNGSTEN_METAL_PATH="$STEM.metal" \
  TUNGSTEN_LL_PATH="$STEM.ll" \
    "$TUNGSTEN" compile "$STEM.w" --out "$STEM.stub" --release --fast --lto

  if [ ! -s "$STEM.cu" ]; then
    echo "build_777.sh: Tungsten did not emit $KERNEL_NAME" >&2
    exit 1
  fi
  EMITTED_SIGNATURES=$(grep -c "extern \"C\" __global__ void $KERNEL_NAME" "$STEM.cu")
  EMITTED_MODES=$(grep -c "int mode = $MODE_VALUE;" "$STEM.cu")
  HELPER_COUNT=$(grep -o '__w_gpu_barrier' "$STEM.cu" | wc -l | tr -d ' ')
  if [ "$EMITTED_SIGNATURES" -ne 1 ] || [ "$EMITTED_MODES" -ne 1 ] || \
     [ "$HELPER_COUNT" -ne 1 ]; then
    echo "build_777.sh: emitted $KERNEL_NAME structure changed; refusing specialization" >&2
    exit 1
  fi
  if grep -q 'params\[6\]' "$STEM.cu" || grep -q 'skipped: CUDA' "$STEM.cu"; then
    echo "build_777.sh: emitted $KERNEL_NAME retained dynamic mode or skipped CUDA" >&2
    exit 1
  fi

  # This relay launches exactly one complete 32-lane CUDA warp per block. The
  # canonical Tungsten kernel therefore has no cross-warp state.  Specialize
  # every conservative block barrier, including the emitter's unused helper,
  # and uniquely name that helper so both emitted variants share one host TU.
  BARRIER_COUNT=$(grep -o '__syncthreads()' "$STEM.cu" | wc -l | tr -d ' ')
  if [ "$BARRIER_COUNT" -ne 12 ]; then
    echo "build_777.sh: expected 12 emitted barriers in $KERNEL_NAME, found $BARRIER_COUNT" >&2
    exit 1
  fi
  awk -v helper="__w_gpu_barrier_${MODE_VALUE}" \
    '{ gsub(/__w_gpu_barrier/, helper); gsub(/__syncthreads\(\)/, "__syncwarp(0xffffffffu)"); print }' \
    "$STEM.cu" > "$STEM.cu.warp"
  mv "$STEM.cu.warp" "$STEM.cu"
  if grep -q '__syncthreads()' "$STEM.cu" || grep -q '__w_gpu_barrier(' "$STEM.cu"; then
    echo "build_777.sh: emitted $KERNEL_NAME specialization was incomplete" >&2
    exit 1
  fi
}

emit_variant "$SCAN_STEM" flipwalk_simd_scan 0
emit_variant "$HASH_STEM" flipwalk_simd_hash 1

if [ "$EMIT_ONLY" -eq 1 ]; then
  echo "$SCAN_STEM.cu"
  echo "$HASH_STEM.cu"
  exit 0
fi

NVCC=${NVCC:-$(command -v nvcc 2>/dev/null || true)}
if [ -z "$NVCC" ] || [ ! -x "$NVCC" ]; then
  echo "build_777.sh: nvcc not found; use a CUDA-devel image and run cloud/cuda/setup_runpod.sh" >&2
  exit 1
fi

mkdir -p "$(dirname -- "$OUT")"
CUDA_ARCH=${METAFLIP_CUDA_ARCH:-native}
"$NVCC" -x cu -std=c++17 -O3 -lineinfo --ptxas-options=-v -arch="$CUDA_ARCH" \
  -Xcompiler -Wall -Xcompiler -Wextra -Xcompiler -Werror \
  -I"$BUILD_DIR" "$HOST_SOURCE" -o "$OUT"

# This path exercises parsing, exhaustive 7^6 reconstruction, controlled
# corruption rejection, and atomic checkpoint round-trip without touching the
# device.  It also runs on a pod before a billable long campaign begins.
"$OUT" --self-test "$SEED"
"$OUT" --policy-self-test
echo "built $OUT"
