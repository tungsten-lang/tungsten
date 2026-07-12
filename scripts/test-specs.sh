#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-"$ROOT/bin/tungsten"}"
COMPILER="$ROOT/bin/tungsten-compiler"
TMP_ROOT="${TMPDIR:-/tmp}/tungsten-specs.$$"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

cd "$ROOT"
mkdir -p "$TMP_ROOT"
fail=0

if [[ ! -x "$COMPILER" ]]; then
  echo "bin/tungsten-compiler is missing; run bin/tungsten build first." >&2
  exit 1
fi

record_result() {
  local name="$1"
  local output="$2"
  local status="$3"

  printf '%s\n' "$output"

  if [[ "$status" -ne 0 ]]; then
    echo "FAIL [$name] exited $status" >&2
    fail=1
  elif printf '%s\n' "$output" | grep -Eq '^FAIL([ :]|$)'; then
    echo "FAIL [$name] emitted failing checks" >&2
    fail=1
  fi
}

run_compiled_spec() {
  local path="$1"
  local name
  local out
  local output
  local status

  name="$(basename "${path%.w}")"
  out="$TMP_ROOT/$name"

  echo "compile+run $path"
  if ! "$TUNGSTEN" compile "$path" --out "$out" >/dev/null; then
    echo "FAIL [$name] compile failed" >&2
    fail=1
    return
  fi

  set +e
  output="$("$out" 2>&1)"
  status=$?
  set -e
  record_result "$name" "$output" "$status"
}

run_interpreter_spec() {
  local path="$1"
  local name
  local output
  local status

  name="$(basename "${path%.w}")"
  echo "run $path"
  set +e
  output="$("$TUNGSTEN" run "$path" 2>&1)"
  status=$?
  set -e
  record_result "$name" "$output" "$status"
}

run_metal_spec() {
  local path="$1"
  local name
  local out
  local ll_path
  local metal_path
  local output
  local status

  name="$(basename "${path%.w}")"
  out="$TMP_ROOT/$name"
  ll_path="$ROOT/${path%.w}.ll"
  metal_path="$ROOT/${path%.w}.metal"

  echo "compile+run $path"
  if ! TUNGSTEN_LL_PATH="$ll_path" "$TUNGSTEN" compile "$path" --out "$out" >/dev/null; then
    echo "FAIL [$name] compile failed" >&2
    fail=1
    rm -f "$ll_path" "$ll_path.done" "$metal_path"
    return
  fi

  set +e
  output="$("$out" 2>&1)"
  status=$?
  set -e
  record_result "$name" "$output" "$status"
  rm -f "$ll_path" "$ll_path.done" "$metal_path"
}

# Emit-only CUDA dialect check: compiles with TUNGSTEN_GPU_DIALECTS=cuda so a
# sibling .cu is written next to the source; the binary reads that text. No
# CUDA toolkit or GPU is required. Always cleans metal/cu/ll sidecars.
run_cuda_emit_spec() {
  local path="$1"
  local name
  local out
  local ll_path
  local metal_path
  local cuda_path
  local output
  local status

  name="$(basename "${path%.w}")"
  out="$TMP_ROOT/$name"
  ll_path="$ROOT/${path%.w}.ll"
  metal_path="$ROOT/${path%.w}.metal"
  cuda_path="$ROOT/${path%.w}.cu"

  echo "compile+run $path (TUNGSTEN_GPU_DIALECTS=cuda)"
  if ! TUNGSTEN_GPU_DIALECTS=cuda TUNGSTEN_LL_PATH="$ll_path" \
      "$TUNGSTEN" compile "$path" --out "$out" >/dev/null; then
    echo "FAIL [$name] compile failed" >&2
    fail=1
    rm -f "$ll_path" "$ll_path.done" "$metal_path" "$cuda_path"
    return
  fi

  set +e
  output="$("$out" 2>&1)"
  status=$?
  set -e
  record_result "$name" "$output" "$status"
  rm -f "$ll_path" "$ll_path.done" "$metal_path" "$cuda_path"
}

compiled_specs=(
  spec/compiler/ast_body_native_spec.w
  spec/compiler/block_passthrough_spec.w
  spec/compiler/elementwise_fusion_spec.w
  spec/compiler/recase_spec.w
  spec/compiler/typed_overload_spec.w
  spec/compiler/view_field_var_spec.w
  spec/core/basics_spec.w
  spec/core/base64_native_spec.w
  spec/core/string_native_spec.w
  spec/core/control_flow_spec.w
  spec/core/classes_spec.w
  spec/core/arrays_hashes_spec.w
  spec/core/enumerable_native_spec.w
  spec/core/network_native_spec.w
  spec/numeric/complex_spec.w
  spec/numeric/fp_math_mode_spec.w
  spec/numeric/matrix_spec.w
  spec/numeric/operator_overload_spec.w
  spec/numeric/vector_spec.w
)

# Emit-only GPU dialect specs (no hardware). Run always with make specs.
cuda_emit_specs=(
  spec/compiler/gpu_cuda_emit_spec.w
)

interpreter_specs=(
  spec/interpreter/slab_decl_spec.w
  spec/core/base64_native_spec.w
)

core_specs=(
  spec/core/byte_array_equality_spec.w
  spec/core/byte_array_slice_spec.w
  spec/core/byte_array_view_flatten_spec.w
  spec/core/byte_array_view_reallocation_spec.w
  spec/core/memory_mapped_view_spec.w
)

metal_specs=(
  spec/core/metal_dispatch_n_spec.w
  spec/core/metal_f16_buffer_spec.w
  spec/core/metal_kernel_spec.w
  spec/core/metal_q8_matvec_spec.w
  spec/core/schedule_unroll_spec.w
)

for spec in "${compiled_specs[@]}"; do
  run_compiled_spec "$spec"
done

for spec in "${cuda_emit_specs[@]}"; do
  run_cuda_emit_spec "$spec"
done

for spec in "${interpreter_specs[@]}"; do
  run_interpreter_spec "$spec"
done

if [[ "${RUN_CORE_SPECS:-0}" == "1" ]]; then
  ruby -e 'File.binwrite("/tmp/tungsten-mmap-view-smoke.bin", [1, 2, 3, 4].pack("V*"))'
  for spec in "${core_specs[@]}"; do
    run_compiled_spec "$spec"
  done
else
  echo "skip core runtime specs (set RUN_CORE_SPECS=1 to run)"
fi

if [[ "${RUN_METAL_SPECS:-0}" == "1" ]]; then
  for spec in "${metal_specs[@]}"; do
    run_metal_spec "$spec"
  done
else
  echo "skip Metal specs (set RUN_METAL_SPECS=1 to run)"
fi

if [[ "${RUN_REPL_SPECS:-0}" == "1" ]]; then
  echo "python3 spec/repl/scrub_pty_spec.py"
  set +e
  output="$(python3 spec/repl/scrub_pty_spec.py 2>&1)"
  status=$?
  set -e
  record_result "scrub_pty_spec.py" "$output" "$status"
else
  echo "skip REPL PTY spec (set RUN_REPL_SPECS=1 to run)"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "test-specs: FAIL"
  exit 1
fi

echo "test-specs: PASS"
