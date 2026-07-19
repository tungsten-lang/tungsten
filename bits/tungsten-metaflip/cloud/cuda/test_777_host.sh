#!/bin/sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PACKAGE_ROOT=$(CDPATH= cd -- "$SELF_DIR/../.." && pwd)
HOST_SOURCE="$SELF_DIR/metaflip_cuda_777.cpp"
SEED_DIR="$PACKAGE_ROOT/lib/metaflip/seeds/gf2"
PRIMARY_SEED="$SEED_DIR/matmul_7x7_rank247_d3094_three_flip_density_gf2.txt"
SEEDS="
$PRIMARY_SEED
$SEED_DIR/matmul_7x7_rank247_d3096_dynamic_syzygy_gf2.txt
$SEED_DIR/matmul_7x7_rank247_d3098_partial_auto_beam_far_gf2.txt
$SEED_DIR/matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt
$SEED_DIR/matmul_7x7_rank247_d3098_affine_code_gf2.txt
"
TEST_BIN=${TMPDIR:-/tmp}/metaflip-cuda-777-host-test-$$
ERROR_LOG=${TMPDIR:-/tmp}/metaflip-cuda-777-host-test-error-$$
EMIT_DIR=${TMPDIR:-/tmp}/metaflip-cuda-777-emit-test-$$
trap 'rm -f "$TEST_BIN" "$ERROR_LOG"; rm -rf "$EMIT_DIR"' EXIT HUP INT TERM

CXX=${CXX:-c++}
"$CXX" -x c++ -std=c++17 -O2 -Wall -Wextra -DMETAFLIP_HOST_ONLY_TEST \
  "$HOST_SOURCE" -o "$TEST_BIN"
for SEED in $SEEDS; do
  "$TEST_BIN" --self-test "$SEED"
done
POLICY_OUTPUT=$("$TEST_BIN" --policy-self-test $SEEDS)
printf '%s\n' "$POLICY_OUTPUT"
if ! printf '%s\n' "$POLICY_OUTPUT" | \
    grep -qx 'CUDA777_POLICY_RECIPE_SELF_TEST ok roots=5 best_source=0 rank=247 density=3094'; then
  echo "CUDA777_SELF_TEST five-root recipe did not select the d3094 objective leader" >&2
  exit 1
fi
if ! printf '%s\n' "$POLICY_OUTPUT" | \
    grep -qx 'CUDA777_HARVEST_SELF_TEST ok completed=5 improved=2 capture_groups=4 capture_sum=10'; then
  echo "CUDA777_SELF_TEST group-harvest telemetry regression did not run" >&2
  exit 1
fi

# The CUDA relay is permanently one warp per block.  Its build must specialize
# every conservative Tungsten block barrier, and must fail rather than silently
# retain a newly added barrier when the canonical kernel changes.
"$SELF_DIR/build_777.sh" --emit-only --build-dir "$EMIT_DIR" >/dev/null
SCAN_EMITTED="$EMIT_DIR/simdgroup_777_scan_kernel.cu"
HASH_EMITTED="$EMIT_DIR/simdgroup_777_hash_kernel.cu"

check_emitted_variant() {
  EMITTED=$1
  KERNEL=$2
  MODE=$3
  if [ ! -s "$EMITTED" ] || grep -q '__syncthreads()' "$EMITTED"; then
    echo "CUDA777_SELF_TEST $KERNEL missing or retained a block barrier" >&2
    exit 1
  fi
  SYNCWARP_COUNT=$(grep -o '__syncwarp(0xffffffffu)' "$EMITTED" | wc -l | tr -d ' ')
  SIGNATURE_COUNT=$(grep -c "extern \"C\" __global__ void $KERNEL" "$EMITTED")
  MODE_COUNT=$(grep -c "int mode = $MODE;" "$EMITTED")
  if [ "$SYNCWARP_COUNT" -ne 12 ] || [ "$SIGNATURE_COUNT" -ne 1 ] || \
     [ "$MODE_COUNT" -ne 1 ] || grep -q 'params\[6\]' "$EMITTED"; then
    echo "CUDA777_SELF_TEST malformed specialized CUDA kernel $KERNEL" >&2
    exit 1
  fi
}
check_emitted_variant "$SCAN_EMITTED" flipwalk_simd_scan 0
check_emitted_variant "$HASH_EMITTED" flipwalk_simd_hash 1

# Prove that each Tungsten input differs from the extracted canonical source
# only in kernel name and constant mode.  This catches accidental hand edits
# to a generated variant even before CUDA emission.
sed -e 's/@gpu fn flipwalk_simd_scan(/@gpu fn flipwalk_simd(/' \
    -e 's/mode = 0 ## i32/mode = params[6] ## i32/' \
    "$EMIT_DIR/simdgroup_777_scan_kernel.w" > "$EMIT_DIR/recovered-scan.w"
sed -e 's/@gpu fn flipwalk_simd_hash(/@gpu fn flipwalk_simd(/' \
    -e 's/mode = 1 ## i32/mode = params[6] ## i32/' \
    "$EMIT_DIR/simdgroup_777_hash_kernel.w" > "$EMIT_DIR/recovered-hash.w"
if ! cmp -s "$EMIT_DIR/simdgroup_777_canonical.w" "$EMIT_DIR/recovered-scan.w" || \
   ! cmp -s "$EMIT_DIR/simdgroup_777_canonical.w" "$EMIT_DIR/recovered-hash.w"; then
  echo "CUDA777_SELF_TEST specialized Tungsten kernel diverged from canonical source" >&2
  exit 1
fi

# Exercise the build's fail-closed source geometry guard. One changed hash
# branch must stop before either specialized kernel is compiled.
sed '1,/if mode == 1/{s/if mode == 1/if mode == 2/;}' \
  "$PACKAGE_ROOT/lib/metaflip/kernels/simd/simdgroup_777.w" > "$EMIT_DIR/tampered.w"
if METAFLIP_777_KERNEL_SOURCE="$EMIT_DIR/tampered.w" \
    "$SELF_DIR/build_777.sh" --emit-only --build-dir "$EMIT_DIR/tampered" \
    >"$ERROR_LOG" 2>&1; then
  echo "CUDA777_SELF_TEST build accepted changed canonical mode geometry" >&2
  exit 1
fi
if ! grep -q 'canonical mode/shared-memory structure changed' "$ERROR_LOG"; then
  echo "CUDA777_SELF_TEST fail-closed build produced the wrong diagnostic" >&2
  exit 1
fi

# Oversized values must be rejected before an implementation-defined i64-to-i32
# cast can turn them into a plausible launch size.
if "$TEST_BIN" --seed "$PRIMARY_SEED" \
    --out /tmp/unused --groups 2147483648 >/dev/null 2>&1; then
  echo "CUDA777_SELF_TEST oversized i32 option was accepted" >&2
  exit 1
fi

# Status and archive files must not be able to alias and overwrite the exact
# objective checkpoint.  Exercise both direct and lexically equivalent paths.
if "$TEST_BIN" --seed "$PRIMARY_SEED" \
    --out /tmp/cuda777-path-collision --status /tmp/./cuda777-path-collision \
    >"$ERROR_LOG" 2>&1; then
  echo "CUDA777_SELF_TEST output/status path collision was accepted" >&2
  exit 1
fi
if ! grep -q -- '--out and --status must name different paths' "$ERROR_LOG"; then
  echo "CUDA777_SELF_TEST output/status collision produced the wrong failure" >&2
  exit 1
fi
if "$TEST_BIN" --seed "$PRIMARY_SEED" \
    --out /tmp/cuda777-path-collision --status /tmp/cuda777-status \
    --archive-dir /tmp/../tmp/cuda777-status >"$ERROR_LOG" 2>&1; then
  echo "CUDA777_SELF_TEST status/archive path collision was accepted" >&2
  exit 1
fi
if ! grep -q -- '--archive-dir must differ from --out and --status' "$ERROR_LOG"; then
  echo "CUDA777_SELF_TEST status/archive collision produced the wrong failure" >&2
  exit 1
fi
