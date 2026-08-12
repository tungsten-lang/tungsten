#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TUNGSTEN="$ROOT/bin/tungsten"
VALID="$ROOT/spec/compiler/string_buffer_dynamic_append_spec.w"
TYPED_SIGNATURE_VALID="$ROOT/spec/compiler/small_array_stack_escape_spec.w"
INVALID="$ROOT/spec/cli/check_type_error.w"
INVALID_CAMEL="$ROOT/spec/cli/camel_case_invalid.w"
INVALID_STR_TYPE="$ROOT/spec/cli/str_type_invalid.w"
INVALID_GPU="$ROOT/spec/cli/gpu_check_missing_hint.w"
MULTI_INVALID_GPU="$ROOT/spec/cli/gpu_check_multiple_errors.w"
UNSUPPORTED_GPU_TYPE="$ROOT/spec/cli/gpu_check_unsupported_type.w"
UNSUPPORTED_CUDA_TYPE="$ROOT/spec/cli/gpu_check_cuda_type.w"
UNSUPPORTED_WGSL_TYPE="$ROOT/spec/cli/gpu_check_wgsl_type.w"
INVALID_SHARED_SHAPE="$ROOT/spec/cli/gpu_check_shared_shape.w"
INVALID_SHARED_BOUNDS="$ROOT/spec/cli/gpu_check_shared_bounds.w"
INVALID_GPU_ADDRESS_SPACE="$ROOT/spec/cli/gpu_check_address_space.w"
UNSUPPORTED_WGSL_SHARED="$ROOT/spec/cli/gpu_check_wgsl_shared_type.w"
VALID_GPU="$ROOT/spec/compiler/gpu_wgsl_emit_spec.w"
CUDA_GPU="$ROOT/spec/compiler/gpu_cuda_tg_reduce_reject_spec.w"
EXIT_7="$ROOT/spec/cli/exit_7.w"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-cli-contracts.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

"$TUNGSTEN" -c "$VALID" >"$TMP/check-short.out"
grep -qx '200 OK' "$TMP/check-short.out"

"$TUNGSTEN" check "$VALID" >"$TMP/check-command.out"
grep -qx '200 OK' "$TMP/check-command.out"

"$TUNGSTEN" -c "$TYPED_SIGNATURE_VALID" >"$TMP/check-typed-signature.out"
grep -qx '200 OK' "$TMP/check-typed-signature.out"

if "$TUNGSTEN" --check "$INVALID" >"$TMP/check-error.out" 2>&1; then
  printf 'tungsten --check accepted a lowering error\n' >&2
  exit 1
fi
grep -q 'E_LOWER_CTOR_ARITY' "$TMP/check-error.out"

if "$TUNGSTEN" --check "$INVALID_CAMEL" >"$TMP/check-camel-error.out" 2>&1; then
  printf 'tungsten --check accepted a camelCase identifier\n' >&2
  exit 1
fi
grep -q 'E_LEX_INVALID_IDENTIFIER' "$TMP/check-camel-error.out"
grep -q "uppercase ASCII is not valid in identifiers: 'camelCase'" "$TMP/check-camel-error.out"

if "$TUNGSTEN" --check "$INVALID_STR_TYPE" >"$TMP/check-str-type-error.out" 2>&1; then
  printf 'tungsten --check accepted str as a type name\n' >&2
  exit 1
fi
grep -q 'E_PARSE_INVALID_TYPE_NAME' "$TMP/check-str-type-error.out"
grep -q "unknown type 'str'.*type is 'string'" "$TMP/check-str-type-error.out"
"$TUNGSTEN" --check -e 'value = "text" ## string' >"$TMP/check-string-type.out"
grep -qx '200 OK' "$TMP/check-string-type.out"

if "$TUNGSTEN" -c "$INVALID_GPU" >"$TMP/check-gpu-error.out" 2>&1; then
  printf 'tungsten -c accepted an invalid @gpu fn\n' >&2
  exit 1
fi
grep -q 'E_GPU_KERNEL_UNSUPPORTED' "$TMP/check-gpu-error.out"
grep -q 'gpu_check_missing_hint.w:4:' "$TMP/check-gpu-error.out"
[[ ! -e "${INVALID_GPU%.w}.metal" ]]
[[ ! -e "${INVALID_GPU%.w}.cu" ]]
[[ ! -e "${INVALID_GPU%.w}.wgsl" ]]

TUNGSTEN_GPU_DIALECTS=wgsl "$TUNGSTEN" -c "$VALID_GPU" >"$TMP/check-gpu-valid.out"
grep -qx '200 OK' "$TMP/check-gpu-valid.out"
[[ ! -e "${VALID_GPU%.w}.metal" ]]
[[ ! -e "${VALID_GPU%.w}.cu" ]]
[[ ! -e "${VALID_GPU%.w}.wgsl" ]]

if TUNGSTEN_GPU_DIALECTS=cuda "$TUNGSTEN" -c "$CUDA_GPU" \
    >"$TMP/check-gpu-cuda-error.out" 2>&1; then
  printf 'tungsten -c accepted a CUDA-incompatible @gpu fn\n' >&2
  exit 1
fi
grep -q 'E_GPU_KERNEL_UNSUPPORTED' "$TMP/check-gpu-cuda-error.out"
grep -q 'tg_sum.*not supported by the CUDA dialect' "$TMP/check-gpu-cuda-error.out"

if TUNGSTEN_GPU_DIALECTS=cuda "$TUNGSTEN" -c "$MULTI_INVALID_GPU" \
    >"$TMP/check-gpu-multiple-error.out" 2>&1; then
  printf 'tungsten -c accepted multiple invalid @gpu functions\n' >&2
  exit 1
fi
grep -q '3 independent @gpu functions failed preflight' "$TMP/check-gpu-multiple-error.out"
grep -q '`missing_input_hint` \[metal\]' "$TMP/check-gpu-multiple-error.out"
grep -q '`unsupported_expression` \[metal\]' "$TMP/check-gpu-multiple-error.out"
grep -q '`cuda_reduction_error` \[cuda\]' "$TMP/check-gpu-multiple-error.out"
[[ ! -e "${MULTI_INVALID_GPU%.w}.metal" ]]
[[ ! -e "${MULTI_INVALID_GPU%.w}.cu" ]]

if "$TUNGSTEN" -c "$UNSUPPORTED_GPU_TYPE" >"$TMP/check-gpu-type-error.out" 2>&1; then
  printf 'tungsten -c accepted an unsupported GPU parameter type\n' >&2
  exit 1
fi
grep -q 'E_GPU_KERNEL_UNSUPPORTED' "$TMP/check-gpu-type-error.out"
grep -q 'parameter `input` has unsupported type `string`' "$TMP/check-gpu-type-error.out"
grep -q 'gpu_check_unsupported_type.w:4:1' "$TMP/check-gpu-type-error.out"
[[ ! -e "${UNSUPPORTED_GPU_TYPE%.w}.metal" ]]
[[ ! -e "${UNSUPPORTED_GPU_TYPE%.w}.cu" ]]

if TUNGSTEN_GPU_DIALECTS=cuda "$TUNGSTEN" -c "$UNSUPPORTED_CUDA_TYPE" \
    >"$TMP/check-gpu-cuda-type-error.out" 2>&1; then
  printf 'tungsten -c accepted a Metal-only CUDA parameter type\n' >&2
  exit 1
fi
grep -q 'E_GPU_KERNEL_UNSUPPORTED' "$TMP/check-gpu-cuda-type-error.out"
grep -q 'mat4.*not supported by the CUDA dialect' "$TMP/check-gpu-cuda-type-error.out"
grep -q 'gpu_check_cuda_type.w:5:1' "$TMP/check-gpu-cuda-type-error.out"
[[ ! -e "${UNSUPPORTED_CUDA_TYPE%.w}.metal" ]]
[[ ! -e "${UNSUPPORTED_CUDA_TYPE%.w}.cu" ]]

if TUNGSTEN_GPU_DIALECTS=wgsl "$TUNGSTEN" -c "$UNSUPPORTED_WGSL_TYPE" \
    >"$TMP/check-gpu-wgsl-type-error.out" 2>&1; then
  printf 'tungsten -c silently skipped an unsupported WGSL parameter type\n' >&2
  exit 1
fi
grep -q 'E_GPU_KERNEL_UNSUPPORTED' "$TMP/check-gpu-wgsl-type-error.out"
grep -q 'f16\[\].*not supported by the WGSL dialect' "$TMP/check-gpu-wgsl-type-error.out"
grep -q 'gpu_check_wgsl_type.w:5:1' "$TMP/check-gpu-wgsl-type-error.out"
[[ ! -e "${UNSUPPORTED_WGSL_TYPE%.w}.metal" ]]
[[ ! -e "${UNSUPPORTED_WGSL_TYPE%.w}.wgsl" ]]

if "$TUNGSTEN" -c "$INVALID_SHARED_SHAPE" \
    >"$TMP/check-gpu-shared-shape-error.out" 2>&1; then
  printf 'tungsten -c accepted a zero-sized GPU workgroup array\n' >&2
  exit 1
fi
grep -q 'E_GPU_KERNEL_UNSUPPORTED' "$TMP/check-gpu-shared-shape-error.out"
grep -q 'gpu.shared_f32 size must be positive (got 0)' "$TMP/check-gpu-shared-shape-error.out"
grep -q 'gpu_check_shared_shape.w:4:1' "$TMP/check-gpu-shared-shape-error.out"
[[ ! -e "${INVALID_SHARED_SHAPE%.w}.metal" ]]
[[ ! -e "${INVALID_SHARED_SHAPE%.w}.cu" ]]

if "$TUNGSTEN" -c "$INVALID_SHARED_BOUNDS" \
    >"$TMP/check-gpu-shared-bounds-error.out" 2>&1; then
  printf 'tungsten -c accepted an out-of-bounds GPU workgroup access\n' >&2
  exit 1
fi
grep -q 'E_GPU_KERNEL_UNSUPPORTED' "$TMP/check-gpu-shared-bounds-error.out"
grep -q 'array `tile` literal index 4 is outside 0...4' "$TMP/check-gpu-shared-bounds-error.out"
grep -q 'gpu_check_shared_bounds.w:5:1' "$TMP/check-gpu-shared-bounds-error.out"
[[ ! -e "${INVALID_SHARED_BOUNDS%.w}.metal" ]]
[[ ! -e "${INVALID_SHARED_BOUNDS%.w}.cu" ]]

if "$TUNGSTEN" -c "$INVALID_GPU_ADDRESS_SPACE" \
    >"$TMP/check-gpu-address-space-error.out" 2>&1; then
  printf 'tungsten -c accepted a mismatched GPU helper address space\n' >&2
  exit 1
fi
grep -q 'E_GPU_KERNEL_UNSUPPORTED' "$TMP/check-gpu-address-space-error.out"
grep -q 'expects device memory, but `tile` is threadgroup memory' "$TMP/check-gpu-address-space-error.out"
grep -q 'gpu_check_address_space.w:10:1' "$TMP/check-gpu-address-space-error.out"
[[ ! -e "${INVALID_GPU_ADDRESS_SPACE%.w}.metal" ]]
[[ ! -e "${INVALID_GPU_ADDRESS_SPACE%.w}.cu" ]]

if TUNGSTEN_GPU_DIALECTS=wgsl "$TUNGSTEN" -c "$UNSUPPORTED_WGSL_SHARED" \
    >"$TMP/check-gpu-wgsl-shared-error.out" 2>&1; then
  printf 'tungsten -c accepted i64 WGSL workgroup storage\n' >&2
  exit 1
fi
grep -q 'E_GPU_KERNEL_UNSUPPORTED' "$TMP/check-gpu-wgsl-shared-error.out"
grep -q 'gpu.shared_i64 is not supported by the WGSL dialect' "$TMP/check-gpu-wgsl-shared-error.out"
grep -q 'gpu_check_wgsl_shared_type.w:4:1' "$TMP/check-gpu-wgsl-shared-error.out"
[[ ! -e "${UNSUPPORTED_WGSL_SHARED%.w}.metal" ]]
[[ ! -e "${UNSUPPORTED_WGSL_SHARED%.w}.wgsl" ]]

for spelling in _camelCase @camelCase @@camelCase '$camelCase'; do
  if "$TUNGSTEN" --check -e "$spelling = 1" >"$TMP/check-camel-variant.out" 2>&1; then
    printf 'tungsten --check accepted invalid identifier %s\n' "$spelling" >&2
    exit 1
  fi
  grep -q 'E_LEX_INVALID_IDENTIFIER' "$TMP/check-camel-variant.out"
  grep -Fq "uppercase ASCII is not valid in identifiers: '$spelling'" "$TMP/check-camel-variant.out"
done

set +e
"$TUNGSTEN" run "$EXIT_7" >"$TMP/run.out" 2>&1
run_status=$?
set -e
if [[ "$run_status" -ne 7 ]]; then
  printf 'tungsten run collapsed exit 7 to %s\n' "$run_status" >&2
  cat "$TMP/run.out" >&2
  exit 1
fi

"$TUNGSTEN" explain E_PARSE_UNEXPECTED_TOKEN >"$TMP/explain.out"
grep -q '^E_PARSE_UNEXPECTED_TOKEN$' "$TMP/explain.out"
if "$TUNGSTEN" explain NO_SUCH_CODE >"$TMP/explain-missing.out" 2>&1; then
  printf 'tungsten explain accepted an unknown code\n' >&2
  exit 1
fi

"$TUNGSTEN" gpu-bench --help >"$TMP/gpu-bench-help.out"
grep -q '^Usage: tungsten gpu-bench' "$TMP/gpu-bench-help.out"
if "$TUNGSTEN" gpu-bench --backend bogus >"$TMP/gpu-bench-error.out" 2>&1; then
  printf 'tungsten gpu-bench accepted an unknown backend\n' >&2
  exit 1
fi
grep -q "unsupported backend 'bogus'" "$TMP/gpu-bench-error.out"

"$TUNGSTEN" debug --help >"$TMP/debug-help.out"
grep -q '^Usage: tungsten debug' "$TMP/debug-help.out"
set +e
"$TUNGSTEN" debug --run --output "$TMP/debug-exit" "$EXIT_7" \
  >"$TMP/debug-build.out" 2>&1
debug_child_status=$?
set -e
[[ -x "$TMP/debug-exit" ]]
[[ -s "$TMP/debug-exit.sidemap" ]]
if [[ "$(uname -s)" == Darwin ]]; then
  [[ -d "$TMP/debug-exit.dSYM" ]]
fi
if [[ "$debug_child_status" -ne 7 ]]; then
  printf 'tungsten debug build changed child exit 7 to %s\n' "$debug_child_status" >&2
  exit 1
fi

printf 'CLI check, GPU preflight, debug, explain, gpu-bench, and exit-status contracts: ok\n'
