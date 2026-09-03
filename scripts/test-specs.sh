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

# Isolated incremental cache for the spec suite. Shared across specs so
# Core/runtime/library work is reused. Leave incremental compile on: a
# PID-unique -o would key a distinct irbin slot and disable that reuse, so
# compiled binaries land at stable names under TUNGSTEN_SPECS_BIN_DIR.
# The cache lifecycle test still pins TUNGSTEN_INCREMENTAL per step against
# its own TUNGSTEN_CACHE_DIR.
if [[ -z "${TUNGSTEN_CACHE_DIR:-}" ]]; then
  export TUNGSTEN_CACHE_DIR="$ROOT/build/cache/specs"
fi
TUNGSTEN_SPECS_BIN_DIR="${TUNGSTEN_SPECS_BIN_DIR:-$TUNGSTEN_CACHE_DIR/bin}"
mkdir -p "$TUNGSTEN_CACHE_DIR" "$TUNGSTEN_SPECS_BIN_DIR"
export TUNGSTEN_SPECS_BIN_DIR

# Parallelism: specs are independent (per-spec outputs), so the
# compile+run stages fan out across JOBS workers via self-exec (--job-*
# modes below). Results land in a shared directory and are aggregated in
# list order, so output and failure attribution stay deterministic. The
# cache-lifecycle test and the gated tails (metal, PTY, api) stay serial.
# Default compiled and interpreted lanes stay sequential waves; overlapping
# them has been measured as a wall-time regression. JOBS=1 restores fully
# serial workers per lane. FAST=1 overlaps its small compiled+interp pins
# and skips the serial tails. Set
# TUNGSTEN_SPECS_PROFILE_FILE to append tab-separated mode/path/seconds rows
# from each worker; this is used to maintain the longest-first schedule below.
JOBS="${JOBS:-auto}"
if [[ "$JOBS" == "auto" ]]; then
  JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
  JOBS=$(( JOBS - 2 ))
  (( JOBS < 1 )) && JOBS=1
fi
if [[ -n "${TUNGSTEN_SPECS_JOBS_DIR:-}" ]]; then
  JOB_RESULT_DIR="$TUNGSTEN_SPECS_JOBS_DIR"
else
  JOB_RESULT_DIR=""
  export TUNGSTEN_SPECS_JOBS_DIR="$TMP_ROOT/job-results"
  mkdir -p "$TUNGSTEN_SPECS_JOBS_DIR"
fi

record_result() {
  local name="$1"
  local output="$2"
  local status="$3"

  # Job mode: persist for the parent's ordered aggregation instead of
  # printing/flagging here.
  if [[ -n "$JOB_RESULT_DIR" ]]; then
    local key="${TUNGSTEN_SPECS_KEY_PREFIX:-}${name//\//__}"
    printf '%s\n' "$output" > "$JOB_RESULT_DIR/$key.out"
    echo "$status" > "$JOB_RESULT_DIR/$key.status"
    return
  fi

  if [[ "$status" -ne 0 ]]; then
    printf '%s\n' "$output"
    echo "FAIL [$name] exited $status" >&2
    fail=1
  elif printf '%s\n' "$output" | grep -Eq '^FAIL([ :]|$)'; then
    printf '%s\n' "$output"
    echo "FAIL [$name] emitted failing checks" >&2
    fail=1
  elif [[ "${TUNGSTEN_SPECS_VERBOSE:-0}" == "1" ]]; then
    printf '%s\n' "$output"
  else
    echo "PASS [$name]"
  fi
}

# Early-exit failures (compile failed, ...) that bypass record_result:
# in job mode persist a note the parent replays verbatim, so failure
# lines keep their exact serial-mode format.
record_failure_note() {
  local name="$1"
  local why="$2"
  if [[ -n "$JOB_RESULT_DIR" ]]; then
    printf '%s\n' "$why" > "$JOB_RESULT_DIR/${TUNGSTEN_SPECS_KEY_PREFIX:-}${name//\//__}.note"
    return
  fi
  echo "FAIL [$name] $why" >&2
  fail=1
}

# Aggregate one job's captured result through the normal reporting path.
# Results are CONSUMED: the same spec name can run in more than one lane
# (compiled and interpreted), and a stale note or output from an earlier
# lane must never shadow the next lane's fresh result.
finish_job() {
  local name="$1"
  local key="${2:-}${name//\//__}"
  local out status
  if [[ -f "$TUNGSTEN_SPECS_JOBS_DIR/$key.note" ]]; then
    echo "FAIL [$name] $(cat "$TUNGSTEN_SPECS_JOBS_DIR/$key.note")" >&2
    fail=1
    rm -f "$TUNGSTEN_SPECS_JOBS_DIR/$key.note" "$TUNGSTEN_SPECS_JOBS_DIR/$key.out" "$TUNGSTEN_SPECS_JOBS_DIR/$key.status"
    return
  fi
  out="$(cat "$TUNGSTEN_SPECS_JOBS_DIR/$key.out" 2>/dev/null || echo "MISSING JOB OUTPUT for $name")"
  status="$(cat "$TUNGSTEN_SPECS_JOBS_DIR/$key.status" 2>/dev/null || echo 99)"
  rm -f "$TUNGSTEN_SPECS_JOBS_DIR/$key.out" "$TUNGSTEN_SPECS_JOBS_DIR/$key.status"
  record_result "$name" "$out" "$status"
}

# Fan a spec list out across JOBS self-exec workers, then aggregate in
# the original order. Extra args after the mode are forwarded to every
# job (the wassat CLI path rides this).
run_parallel() {
  local mode="$1"; shift
  local -a specs=()
  local -a extra=()
  local seen_sep=0 a
  for a in "$@"; do
    if [[ "$a" == "--" ]]; then seen_sep=1; continue; fi
    if [[ "$seen_sep" -eq 1 ]]; then extra+=("$a"); else specs+=("$a"); fi
  done
  [[ ${#specs[@]} -eq 0 ]] && return 0
  printf '%s\n' "${specs[@]}" | TUNGSTEN_SPECS_KEY_PREFIX="$mode." xargs -P "$JOBS" -I{} "$0" "--job-$mode" {} "${extra[@]:-}"
  run_parallel_aggregate "$mode" "${specs[@]}"
}

# Launch a lane without blocking (results aggregated later); pair every
# call with run_parallel_aggregate after wait. Keys are mode-prefixed, so
# overlapping lanes never collide even when spec names repeat.
run_parallel_launch() {
  local mode="$1"; shift
  [[ $# -eq 0 ]] && return 0
  printf '%s\n' "$@" | TUNGSTEN_SPECS_KEY_PREFIX="$mode." xargs -P "$JOBS" -I{} "$0" "--job-$mode" {} &
}

run_parallel_aggregate() {
  local mode="$1"; shift
  local spec name
  for spec in "$@"; do
    name="$(basename "${spec%.w}")"
    if [[ "$mode" == "wassat" ]]; then
      name="wassat/$name"
    fi
    finish_job "$name" "$mode."
  done
}

# Exact duplicate paths launch two workers against the same binary and result
# files; basename collisions do the same even when the source paths differ.
# Fail before starting work instead of reporting a misleading missing status.
assert_unique_spec_lane() {
  local lane="$1"
  shift
  local duplicate_paths
  local duplicate_names
  local source_path
  local spec_name

  duplicate_paths="$(printf '%s\n' "$@" | LC_ALL=C sort | uniq -d)"
  duplicate_names="$({
    for source_path in "$@"; do
      spec_name="${source_path##*/}"
      printf '%s\n' "${spec_name%.w}"
    done
  } | LC_ALL=C sort | uniq -d)"
  if [[ -n "$duplicate_paths" || -n "$duplicate_names" ]]; then
    echo "duplicate $lane spec jobs" >&2
    [[ -z "$duplicate_paths" ]] || printf '  path: %s\n' "$duplicate_paths" >&2
    [[ -z "$duplicate_names" ]] || printf '  result name: %s\n' "$duplicate_names" >&2
    exit 1
  fi
}

run_compiled_spec() {
  local path="$1"
  local name
  local out
  local output
  local status
  local -a compile_cmd

  name="$(basename "${path%.w}")"
  out="$TUNGSTEN_SPECS_BIN_DIR/$name"

  echo "compile+run $path"
  if [[ "$path" == spec/compiler/big_array_cap_empty_no_use_*_spec.w ]]; then
    compile_cmd=(env "TUNGSTEN_C_INCLUDES=$ROOT/benchmarks/runtime_ports/big_array_cap_empty_revisit_ref.c" "$TUNGSTEN")
  else
    compile_cmd=("$TUNGSTEN")
  fi
  if ! "${compile_cmd[@]}" compile "$path" --out "$out" >/dev/null; then
    record_failure_note "$name" "compile failed"
    return
  fi

  set +e
  output="$(TUNGSTEN_SPEC_QUIET=1 "$out" 2>&1)"
  status=$?
  set -e
  record_result "$name" "$output" "$status"
}

# Compatible compiled specs share Core/runtime/library work. compile-batch
# emits in parallel and now links in parallel; binaries land in the isolated
# spec bin dir so source trees stay clean. Per-spec run/attribution is
# unchanged. Specs that need extra C includes stay on the one-at-a-time path.
run_compiled_batch() {
  local -a specs=("$@")
  local -a batch=()
  local -a solo=()
  local spec name out output status
  local batch_log="$TMP_ROOT/compile-batch.log"
  local saved_job_dir="$JOB_RESULT_DIR"

  [[ ${#specs[@]} -eq 0 ]] && return 0
  # This runs in the parent, not a --job-* worker. Report immediately.
  JOB_RESULT_DIR=""
  for spec in "${specs[@]}"; do
    if [[ "$spec" == spec/compiler/big_array_cap_empty_no_use_*_spec.w ]]; then
      solo+=("$spec")
    else
      batch+=("$spec")
    fi
  done

  if [[ ${#batch[@]} -gt 0 ]]; then
    echo "compile-batch ${#batch[@]} specs (--batch-out-dir $TUNGSTEN_SPECS_BIN_DIR)"
    set +e
    "$TUNGSTEN" compile-batch --jobs "$JOBS" --no-lto \
      --batch-out-dir "$TUNGSTEN_SPECS_BIN_DIR" \
      "${batch[@]}" >"$batch_log" 2>&1
    status=$?
    set -e
    if [[ "$status" -ne 0 ]]; then
      cat "$batch_log" >&2
      for spec in "${batch[@]}"; do
        record_failure_note "$(basename "${spec%.w}")" "compile-batch failed"
      done
    else
      for spec in "${batch[@]}"; do
        name="$(basename "${spec%.w}")"
        out="$TUNGSTEN_SPECS_BIN_DIR/$name"
        if [[ ! -x "$out" ]]; then
          record_failure_note "$name" "compile-batch produced no binary"
          continue
        fi
        set +e
        output="$(TUNGSTEN_SPEC_QUIET=1 "$out" 2>&1)"
        status=$?
        set -e
        record_result "$name" "$output" "$status"
      done
    fi
  fi

  if [[ ${#solo[@]} -gt 0 ]]; then
    JOB_RESULT_DIR="$saved_job_dir"
    run_parallel compiled "${solo[@]}"
    return
  fi
  JOB_RESULT_DIR="$saved_job_dir"
}

run_interpreter_spec() {
  local path="$1"
  local name
  local output
  local status

  name="$(basename "${path%.w}")"
  echo "interpret $path"
  set +e
  output="$(TUNGSTEN_INTERPRETED_SPEC=1 TUNGSTEN_SPEC_QUIET=1 "$TUNGSTEN" run --interpret "$path" 2>&1)"
  status=$?
  set -e
  record_result "$name" "$output" "$status"
}

# Expected runtime failures pin invalid public shapes that used to create
# malformed values. Both engines must reject with the same useful diagnostic;
# a signal or a successful nil result is always a failure.
run_compiled_reject_spec() {
  local path="$1"
  local name="$(basename "${path%.w}")"
  local out="$TMP_ROOT/$name"
  local output
  local status
  local needle

  case "$name" in
    date_invalid_constructor) needle='Date.new expects one to seven arguments' ;;
    decimal_invalid_constructor|decimal_invalid_zero_constructor) needle='Decimal.new is not a supported scalar constructor' ;;
    *) record_failure_note "$name" "missing expected compiled rejection diagnostic"; return ;;
  esac

  echo "compile+reject $path"
  if ! "$TUNGSTEN" compile "$path" --out "$out" >/dev/null; then
    record_failure_note "$name" "compile failed before runtime rejection"
    return
  fi
  set +e
  output="$("$out" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    record_failure_note "$name" "invalid program unexpectedly succeeded"
  elif [[ "$status" -gt 128 ]]; then
    record_result "$name" "$output" 1
  elif ! grep -Fq "$needle" <<<"$output"; then
    record_result "$name" "$output" 1
  else
    record_result "$name" "PASS $name" 0
  fi
}

run_interpreter_reject_spec() {
  local path="$1"
  local name="$(basename "${path%.w}")"
  local output
  local status
  local needle

  case "$name" in
    date_invalid_constructor) needle="'new' takes 1..7 arguments, got 0" ;;
    decimal_invalid_constructor|decimal_invalid_zero_constructor) needle='Decimal.new is not a supported scalar constructor' ;;
    *) record_failure_note "$name" "missing expected interpreted rejection diagnostic"; return ;;
  esac

  echo "run+reject $path"
  set +e
  output="$(TUNGSTEN_INTERPRETED_SPEC=1 "$TUNGSTEN" run --interpret "$path" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    record_failure_note "$name" "invalid program unexpectedly succeeded"
  elif [[ "$status" -gt 128 ]]; then
    record_result "$name" "$output" 1
  elif ! grep -Fq "$needle" <<<"$output"; then
    record_result "$name" "$output" 1
  else
    record_result "$name" "PASS $name" 0
  fi
}

run_wassat_spec() {
  local path="$1"
  local wassat_bin="$2"
  local name
  local spec_bin
  local output
  local status
  local summary
  local total
  local passed
  local failed

  name="$(basename "${path%.w}")"
  # Compile only suites whose contract or practical runtime requires native
  # code: the CLI/process portfolio, atomic-CAS solver paths, and the few
  # exhaustive recognizer searches that are prohibitively slow in the tree
  # walker. Ordinary recognizer/solver semantics use the interpreter plus the
  # native-parser-shaped test double in cnf.w; their end-to-end CLI examples
  # still invoke the separately compiled Wassat binary.
  case "$name" in
    solver_spec|portfolio_spec|ternary_affine_spec|covering_spec|directed_kernel_spec|latin_csp_spec|hantzsche_wendt_spec|knight_tour_spec)
      compile_wassat_spec=1 ;;
    *)
      compile_wassat_spec=0 ;;
  esac
  if [[ "$compile_wassat_spec" == "1" ]]; then
    spec_bin="$TMP_ROOT/wassat-$name"
    echo "compile+run $path (WASSAT_TEST_BIN=$wassat_bin)"
    if ! "$TUNGSTEN" compile "$path" --out "$spec_bin" --no-lto >/dev/null; then
      record_failure_note "wassat/$name" "compile failed"
      return
    fi
    set +e
    output="$(TUNGSTEN_SPEC_QUIET=1 WASSAT_TEST_BIN="$wassat_bin" "$spec_bin" 2>&1)"
    status=$?
    set -e
  else
    echo "interpret $path (WASSAT_TEST_BIN=$wassat_bin)"
    set +e
    # Specs launch the compiled CLI for end-to-end assertions. Keep the
    # interpreter-only parser double out of that child process: it needs the
    # real flat native parser result, even though its parent spec is walking
    # the source tree.
    output="$(TUNGSTEN_INTERPRETED_SPEC=1 TUNGSTEN_SPEC_QUIET=1 \
      TUNGSTEN_WASSAT_PARSE_STUB=1 \
      WASSAT_TEST_BIN="env -u TUNGSTEN_WASSAT_PARSE_STUB -u TUNGSTEN_INTERPRETED_SPEC $wassat_bin" \
      "$TUNGSTEN" run --interpret "$path" 2>&1)"
    status=$?
    set -e
  fi

  # A compiler/runtime failure has previously produced an executable that
  # silently exited zero. Do not let that look like a green spec: a successful
  # Wassat job must report an internally consistent, zero-failure summary.
  if [[ "$status" -eq 0 ]]; then
    summary="$(printf '%s\n' "$output" | grep -E '^[0-9]+ examples: [0-9]+ passed, [0-9]+ failed$' | tail -1 || true)"
    if [[ -z "$summary" ]]; then
      output="${output}${output:+$'\n'}FAIL: missing valid Wassat spec summary"
      status=1
    else
      total="$(printf '%s\n' "$summary" | sed -nE 's/^([0-9]+) examples:.*/\1/p')"
      passed="$(printf '%s\n' "$summary" | sed -nE 's/^[0-9]+ examples: ([0-9]+) passed,.*/\1/p')"
      failed="$(printf '%s\n' "$summary" | sed -nE 's/.*, ([0-9]+) failed$/\1/p')"
      if [[ "$failed" -ne 0 || "$total" -ne $((passed + failed)) ]]; then
        output="${output}${output:+$'\n'}FAIL: inconsistent or failing Wassat spec summary"
        status=1
      fi
    fi
  fi
  record_result "wassat/$name" "$output" "$status"
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
    record_failure_note "$name" "compile failed"
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

# WGSL dialect check. The binary pins expected source markers; when NAGA_BIN is
# set (CI pins naga-cli), Naga also parses and semantically validates the actual
# emitted sidecar. No browser, WebGPU implementation, or GPU is required.
run_wgsl_emit_spec() {
  local path="$1"
  local name
  local out
  local ll_path
  local metal_path
  local cuda_path
  local wgsl_path
  local output
  local status
  local validator

  name="$(basename "${path%.w}")"
  out="$TMP_ROOT/$name"
  ll_path="$ROOT/${path%.w}.ll"
  metal_path="$ROOT/${path%.w}.metal"
  cuda_path="$ROOT/${path%.w}.cu"
  wgsl_path="$ROOT/${path%.w}.wgsl"

  echo "compile+run $path (TUNGSTEN_GPU_DIALECTS=wgsl)"
  if ! TUNGSTEN_GPU_DIALECTS=wgsl TUNGSTEN_LL_PATH="$ll_path" \
      "$TUNGSTEN" compile "$path" --out "$out" >/dev/null; then
    record_failure_note "$name" "compile failed"
    rm -f "$ll_path" "$ll_path.done" "$metal_path" "$cuda_path" "$wgsl_path"
    return
  fi

  validator="${NAGA_BIN:-}"
  if [[ -z "$validator" ]] && command -v naga >/dev/null 2>&1; then
    validator="$(command -v naga)"
  fi
  if [[ -n "$validator" ]]; then
    if [[ ! -x "$validator" ]]; then
      record_failure_note "$name" "NAGA_BIN is not executable: $validator"
      rm -f "$ll_path" "$ll_path.done" "$metal_path" "$cuda_path" "$wgsl_path"
      return
    fi
    set +e
    output="$("$validator" "$wgsl_path" 2>&1)"
    status=$?
    set -e
    if [[ "$status" -ne 0 ]]; then
      record_result "$name" "$output" "$status"
      rm -f "$ll_path" "$ll_path.done" "$metal_path" "$cuda_path" "$wgsl_path"
      return
    fi
  fi

  set +e
  output="$("$out" 2>&1)"
  status=$?
  set -e
  record_result "$name" "$output" "$status"
  rm -f "$ll_path" "$ll_path.done" "$metal_path" "$cuda_path" "$wgsl_path"
}

# CUDA expected-rejection checks. These prove a Metal-only intrinsic fails in
# Tungsten's dialect emitter with a useful diagnostic, before an invalid .cu
# reaches nvcc. No CUDA toolkit or GPU is required.
run_cuda_reject_spec() {
  local path="$1"
  local name
  local out
  local ll_path
  local metal_path
  local cuda_path
  local needle
  local output
  local status

  name="$(basename "${path%.w}")"
  out="$TMP_ROOT/$name"
  ll_path="$ROOT/${path%.w}.ll"
  metal_path="$ROOT/${path%.w}.metal"
  cuda_path="$ROOT/${path%.w}.cu"
  case "$name" in
    gpu_cuda_tg_reduce_reject_spec) needle='`tg_sum` is not supported by the CUDA dialect' ;;
    gpu_cuda_simdgroup_reject_spec) needle='`simdgroup_load` is Metal-only' ;;
    *) record_failure_note "$name" "missing expected CUDA diagnostic"; return ;;
  esac

  echo "compile-reject $path (TUNGSTEN_GPU_DIALECTS=cuda)"
  set +e
  output="$(TUNGSTEN_GPU_DIALECTS=cuda TUNGSTEN_LL_PATH="$ll_path" \
    "$TUNGSTEN" compile "$path" --out "$out" 2>&1)"
  status=$?
  set -e
  rm -f "$ll_path" "$ll_path.done" "$metal_path" "$cuda_path" "$out"

  if [[ "$status" -eq 0 ]]; then
    record_failure_note "$name" "compile unexpectedly accepted Metal-only CUDA intrinsic"
  elif ! grep -Fq "$needle" <<<"$output"; then
    record_result "$name" "$output" 1
  else
    record_result "$name" "PASS $name" 0
  fi
}

# ── Incremental binary cache lifecycle ────────────────────────────────────
# One compile step of the lifecycle test: expects a cache hit ("(cache)" in
# the driver output) or a miss, with TUNGSTEN_INCREMENTAL set explicitly so
# the suite-wide export above does not leak in.
cache_lifecycle_step() {
  local label="$1"
  local expect="$2"   # yes|no — whether "(cache)" must appear
  local inc="$3"      # TUNGSTEN_INCREMENTAL value for this step
  local src="$4"
  local out="$5"
  local output
  local status
  local hit

  set +e
  output="$(TUNGSTEN_CACHE_DIR="$cache_lifecycle_dir" TUNGSTEN_INCREMENTAL="$inc" \
    "$TUNGSTEN" compile "$src" --out "$out" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL [cache_lifecycle] $label: compile exited $status" >&2
    printf '%s\n' "$output" >&2
    fail=1
    return
  fi
  hit="no"
  if printf '%s\n' "$output" | grep -qF "(cache)"; then
    hit="yes"
  fi
  if [[ "$hit" != "$expect" ]]; then
    echo "FAIL [cache_lifecycle] $label: expected cache=$expect, got cache=$hit" >&2
    fail=1
  else
    echo "PASS [cache_lifecycle] $label (cache=$hit)"
  fi
}

run_cache_lifecycle_test() {
  local dir="$TMP_ROOT/cache-test"
  local src="$dir/prog.w"
  local out="$dir/prog"
  local deep
  local i

  cache_lifecycle_dir="$dir/cache"
  mkdir -p "$dir"
  printf '<< "cache lifecycle probe"\n' > "$src"
  echo "cache lifecycle test (TUNGSTEN_CACHE_DIR=$cache_lifecycle_dir)"

  cache_lifecycle_step "cold compile misses" no 1 "$src" "$out"
  cache_lifecycle_step "identical recompile hits" yes 1 "$src" "$out"

  touch "$src"
  cache_lifecycle_step "touched source misses" no 1 "$src" "$out"

  touch "$ROOT/runtime/runtime.c"
  cache_lifecycle_step "touched runtime source misses" no 1 "$src" "$out"

  cache_lifecycle_step "TUNGSTEN_INCREMENTAL=0 misses" no 0 "$src" "$out"

  # A ~200-char nested output path: slot names hash the absolute paths, so
  # storing must not overflow NAME_MAX and the second compile must hit.
  deep="$dir"
  for i in 1 2 3 4 5 6 7 8 9 10; do
    deep="$deep/deep-cache-path-seg"
  done
  mkdir -p "$deep"
  cache_lifecycle_step "deep output path cold compile misses" no 1 "$src" "$deep/prog"
  cache_lifecycle_step "deep output path recompile hits" yes 1 "$src" "$deep/prog"
}

# Self-exec worker entry: run exactly one spec. Parallel children persist their
# result for the parent and leave `fail` at zero; a directly invoked job has no
# parent aggregator, so return its recorded failure status to the caller.
if [[ "${1:-}" == --job-* ]]; then
  job_started_seconds=$SECONDS
  case "$1" in
    --job-compiled) run_compiled_spec "$2" ;;
    --job-interp)   run_interpreter_spec "$2" ;;
    --job-compiled-reject) run_compiled_reject_spec "$2" ;;
    --job-interp-reject) run_interpreter_reject_spec "$2" ;;
    --job-cuda)     run_cuda_emit_spec "$2" ;;
    --job-wgsl)     run_wgsl_emit_spec "$2" ;;
    --job-cuda-reject) run_cuda_reject_spec "$2" ;;
    --job-wassat)   run_wassat_spec "$2" "$3" ;;
    *) echo "unknown job mode $1" >&2; exit 2 ;;
  esac
  if [[ -n "${TUNGSTEN_SPECS_PROFILE_FILE:-}" ]]; then
    printf '%s\t%s\t%s\n' "$1" "$2" "$((SECONDS - job_started_seconds))" >> "$TUNGSTEN_SPECS_PROFILE_FILE"
  fi
  exit "$fail"
fi

# Lane lists live in spec-lanes.sh so a file-list probe can fail closed
# without compiling. Discovery is tracked-only: uncommitted scratch specs
# must not change the suite.
SPEC_LANES_ROOT="$ROOT"
# shellcheck source=spec-lanes.sh
. "$ROOT/scripts/spec-lanes.sh"

if [[ "${BIT_SPECS_ONLY:-0}" != "1" ]]; then
  spec_classify_tracked
fi

if [[ "${1:-}" == "--compiled-slice" ]]; then
  shift
  if [[ $# -eq 0 ]]; then
    slice_specs=("${fast_compiled[@]}")
  else
    slice_specs=("$@")
  fi
  assert_unique_spec_lane "compiled slice" "${slice_specs[@]}"
  if [[ "${TUNGSTEN_SPECS_COMPILE_BATCH:-0}" == "1" ]]; then
    run_compiled_batch "${slice_specs[@]}"
  else
    run_parallel compiled "${slice_specs[@]}"
  fi
  if [[ "$fail" -ne 0 ]]; then
    echo "test-specs: FAIL (compiled slice)"
    exit 1
  fi
  echo "test-specs: OK (compiled slice)"
  exit 0
fi

# Longest-processing-time first keeps the parallel worker pool busy while the
# expensive compiler/Core programs run. These paths are a deliberately small,
# measured scheduling tier; compiled_specs remains the coverage manifest.
assert_unique_spec_lane "compiled" "${compiled_specs[@]}"
assert_unique_spec_lane "compiled priority" "${compiled_priority_specs[@]}"
scheduled_compiled_specs=()
for priority_path in "${compiled_priority_specs[@]}"; do
  found=0
  for source_path in "${compiled_specs[@]}"; do
    if [[ "$source_path" == "$priority_path" ]]; then
      found=1
      break
    fi
  done
  if [[ "$found" != "1" ]]; then
    echo "missing priority compiled spec: $priority_path" >&2
    exit 1
  fi
  scheduled_compiled_specs+=("$priority_path")
done
for source_path in "${compiled_specs[@]}"; do
  prioritized=0
  for priority_path in "${compiled_priority_specs[@]}"; do
    if [[ "$source_path" == "$priority_path" ]]; then
      prioritized=1
      break
    fi
  done
  if [[ "$prioritized" != "1" ]]; then
    scheduled_compiled_specs+=("$source_path")
  fi
done
compiled_specs=("${scheduled_compiled_specs[@]}")

run_special_bit_specs() {
  # Wassat has a deliberate compiled/interpreted split: its native parser,
  # process portfolio, and atomic ABI are not meaningful through the
  # interpreter, while a few proof-library specs intentionally stay there.
  # Keep this lane here, but let `rake spec:bits` own when it runs so every bit
  # spec is executed exactly once by the default root suite.
  local wassat_bin="$TMP_ROOT/wassat"
  echo "compile bits/tungsten-wassat/bin/wassat.w"
  if "$TUNGSTEN" compile bits/tungsten-wassat/bin/wassat.w --out "$wassat_bin" --no-lto >/dev/null; then
    run_parallel wassat "${wassat_specs[@]}" -- "$wassat_bin"
  else
    echo "FAIL [wassat] CLI compile failed" >&2
    fail=1
  fi

  # The independent proof checker has no shared parsing/checking code and does
  # not need compiled runtime builtins, so its contract stays interpreted.
  run_parallel interp "${wrat_specs[@]}"
}

# Narrow entry point used by `rake spec:bits`. All ordinary bit suites are run
# by scripts/test-bit-specs.sh; this file retains the two suites that need its
# specialized execution modes and result validation.
if [[ "${BIT_SPECS_ONLY:-0}" == "1" ]]; then
  run_special_bit_specs
  if [[ "$fail" -ne 0 ]]; then
    echo "test-specs: FAIL (special bit specs)"
    exit 1
  fi
  echo "test-specs: PASS (special bit specs)"
  exit 0
fi

# FAST=1: the curated inner-loop slice — the engine-parity and bignum
# pins that gate day-to-day compiler work — in parallel, skipping the
# serial tails. The full battery remains the commit gate.
if [[ "${FAST:-0}" == "1" ]]; then
  run_parallel_launch compiled "${fast_compiled[@]}"
  run_parallel_launch interp "${fast_interp[@]}"
  wait
  run_parallel_aggregate compiled "${fast_compiled[@]}"
  run_parallel_aggregate interp "${fast_interp[@]}"
  if [[ "$fail" -ne 0 ]]; then
    echo "test-specs: FAIL (fast tier)"
    exit 1
  fi
  echo "test-specs: OK (fast tier)"
  exit 0
fi

# Do not overlap the full compiled and interpreted lanes: that
# oversubscribes the machine and has been measured as a regression.
run_parallel compiled "${compiled_specs[@]}"
run_parallel compiled-reject "${compiled_reject_specs[@]}"

run_cache_lifecycle_test

run_parallel cuda "${cuda_emit_specs[@]}"
run_parallel wgsl "${wgsl_emit_specs[@]}"
run_parallel cuda-reject "${cuda_reject_specs[@]}"

run_parallel interp "${interpreter_specs[@]}"
run_parallel interp-reject "${interpreter_reject_specs[@]}"

# ── Cross-engine parity (scripts/parity.sh) ───────────────────────────────
# Every spec/parity/*_spec.w runs through the interpreter and the compiled
# path; the transcripts must agree byte-for-byte (see doc/PARITY.md).
# RUN_PARITY_SPECS=0 skips the stage.
if [[ "${RUN_PARITY_SPECS:-1}" != "0" ]]; then
  echo "parity scripts/parity.sh (spec/parity, interp vs compiled)"
  set +e
  output="$("$ROOT/scripts/parity.sh" --jobs "$JOBS" 2>&1)"
  status=$?
  set -e
  record_result "parity" "$output" "$status"
else
  echo "skip parity specs (set RUN_PARITY_SPECS=1 to run)"
fi
# ── end parity ────────────────────────────────────────────────────────────

if [[ "${RUN_CORE_SPECS:-0}" == "1" ]]; then
  # High-bit words pin the SIGNED view encodings (as_i32/as_i64 vs as_u32):
  # a positive-only fixture decodes identically under the old unsigned
  # encodings and cannot catch a sign-extension regression.
  ruby -e 'File.binwrite("/tmp/tungsten-mmap-view-smoke.bin", [1, 2, 3, 4, 0xFFFFFFFF, 0xFFFFFFFE, 0x89ABCDEF, 0x01234567].pack("V*"))'
  run_parallel compiled "${core_specs[@]}"
else
  echo "skip core runtime specs (set RUN_CORE_SPECS=1 to run)"
fi

if [[ "${RUN_METAL_SPECS:-0}" == "1" ]]; then
  for spec in "${metal_specs[@]}"; do
    run_metal_spec "$spec"
  done
  echo "bin/tungsten gpu-bench (hardware smoke)"
  set +e
  output="$("$TUNGSTEN" gpu-bench --elements 65536 --runs 3 --warmup 1 \
    --output "$TMP_ROOT/gpu-bench.json" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]] && ! ruby -rjson -e \
      'r = JSON.parse(File.read(ARGV.fetch(0))); exit(r.dig("verification", "passed") ? 0 : 1)' \
      "$TMP_ROOT/gpu-bench.json"; then
    output="${output}${output:+$'\n'}FAIL: gpu-bench result did not verify"
    status=1
  fi
  record_result "gpu-bench" "$output" "$status"
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

# Response-shape contract for the /api/run + /api/check engine
# (services/api/lib/exec.w). Opt-in because each check compiles and runs a small
# program of its own, so it is slower than a normal spec.
if [[ "${RUN_API_SPECS:-0}" == "1" ]]; then
  run_parallel compiled "${api_specs[@]}"
else
  echo "skip API contract spec (set RUN_API_SPECS=1 to run)"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "test-specs: FAIL"
  exit 1
fi

echo "test-specs: PASS"
