#!/usr/bin/env bash
# Parity test: compile fixtures, run them,
# compare output against the Ruby interpreter (ground truth).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TUNGSTEN="$ROOT/bin/tungsten"
FIXTURES="$ROOT/compiler/test/fixtures"
TMP="$(mktemp -d)"

# Fixtures currently supported by the WIRE pipeline
SUPPORTED=(
  hello simple add arithmetic variables
  ifelse elsif while countdown break
  fib fib0 fib1 fib2 fib3
  func func_if innercall innercall_arg
  nocall othercall selfcall fib_norun
  fn_fib
  class class_var
  case
  rescue
  array
  block
  method_call
  classes
  capture
  closure_call
  yield
  hash
  range
  with
  multi_assign
  currency
  quantity
  duration
  short_circuit
  magic_constants
  case_value
  goroutine_basic
  block_item_shadow
  trailing_ro
  unit_convert
  unit_dim_algebra
  unit_prefixed_convert
  implicit_new
  unit_pipes
  goroutine_channel
  math_notation
)

PASS=0
FAIL=0
SKIP=0
ERRORS=""

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "==> Generating ground truth (${#SUPPORTED[@]} fixtures)..."
# Phase 1: Generate ground truth for fixtures without .expected files
for name in "${SUPPORTED[@]}"; do
  fixture="$FIXTURES/${name}.w"
  if [ ! -f "$fixture" ]; then
    continue
  fi
  if grep -q '## expect skip' "$fixture"; then
    echo "SKIP  $name (expect skip)"
    SKIP=$((SKIP + 1))
    continue
  fi
  expected="$TMP/${name}.expected"
  if [ -f "$FIXTURES/${name}.expected" ]; then
    cp "$FIXTURES/${name}.expected" "$expected"
  elif ! "$TUNGSTEN" run --ruby "$fixture" > "$expected" 2>/dev/null; then
    echo "SKIP  $name (interpreter error)"
    SKIP=$((SKIP + 1))
  fi
done

# Phase 2: Batch compile all fixtures in one stage compiler invocation
COMPILE_LIST=()
for name in "${SUPPORTED[@]}"; do
  fixture="$FIXTURES/${name}.w"
  if [ ! -f "$fixture" ]; then
    continue
  fi
  if [ ! -f "$TMP/${name}.expected" ]; then
    continue  # skipped in phase 1
  fi
  # Copy fixture to TMP so output binary lands there
  cp "$fixture" "$TMP/${name}.w"
  COMPILE_LIST+=("$TMP/${name}.w")
done

if [ ${#COMPILE_LIST[@]} -gt 0 ]; then
  echo "==> Compiling ${#COMPILE_LIST[@]} fixtures..."
  compile_out="$TMP/batch_compile.log"
  # --no-lto: parity checks output equivalence, not performance, so LTO is
  # pointless here — and on a constrained CI runner (2 cores) the LTO links are
  # slow enough that the 600s batch budget expires after only a fraction of the
  # fixtures, leaving the rest binary-less ("compile error"). Non-LTO links keep
  # the whole batch well under budget; the produced output is identical.
  perl -e 'alarm shift; exec @ARGV' 600 \
    "$TUNGSTEN" compile-batch --no-lto "${COMPILE_LIST[@]}" \
    > "$compile_out" 2>&1 || true
  echo "    done"
fi

echo "==> Running and comparing..."
# Phase 3: Run each compiled binary and diff
for name in "${SUPPORTED[@]}"; do
  fixture="$FIXTURES/${name}.w"
  if [ ! -f "$fixture" ]; then
    echo "SKIP  $name (file not found)"
    SKIP=$((SKIP + 1))
    continue
  fi

  expected="$TMP/${name}.expected"
  if [ ! -f "$expected" ]; then
    continue  # already counted as skip
  fi

  binary="$TMP/${name}.wc"
  if [ ! -f "$binary" ]; then
    echo "FAIL  $name (compile error)"
    FAIL=$((FAIL + 1))
    continue
  fi

  # Run compiled binary (10s timeout)
  actual="$TMP/${name}.actual"
  if ! perl -e 'alarm shift; exec @ARGV' 10 "$binary" > "$actual" 2>&1; then
    echo "FAIL  $name (runtime error)"
    ERRORS="${ERRORS}\n--- $name (runtime) ---\n$(cat "$actual")"
    FAIL=$((FAIL + 1))
    continue
  fi

  # Diff
  if diff -q "$expected" "$actual" > /dev/null 2>&1; then
    echo "PASS  $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $name (output mismatch)"
    ERRORS="${ERRORS}\n--- $name (diff) ---\nexpected: $(cat "$expected")\nactual:   $(cat "$actual")"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "Results: $PASS pass, $FAIL fail, $SKIP skip (${#SUPPORTED[@]} total)"

# Phase 4: the same fixtures through the compiled TREE-WALK INTERPRETER
# (`tungsten run`), diffed against the same expected output. Known gaps are
# listed in INTERP_SKIP — a failure outside that list gates, so interpreter/
# compiler divergence can only shrink.
INTERP_SKIP=(
  argv_clock          # argv differs under `run`
  goroutine_basic     # `go` not dispatched by the interpreter yet
  goroutine_channel
  func_if             # interpreter gaps as of 2026-06-09 — shrink this list,
  fn_fib              # never grow it: fn_def dispatch missing
  class_var           # "Invalid assignment target" on @@cvar assign
  array               # subscript-assign through alias reads back nil
  with                # :with node not dispatched
  duration            # :duration node not dispatched
  block_item_shadow   # implicit-item map not supported by the interpreter
)

interp_skipped() {
  local needle="$1"; local x
  for x in "${INTERP_SKIP[@]}"; do [ "$x" = "$needle" ] && return 0; done
  return 1
}

echo ""
echo "==> Interpreter leg (tungsten run)..."
IPASS=0
IFAIL=0
ISKIP=0
for name in "${SUPPORTED[@]}"; do
  fixture="$FIXTURES/${name}.w"
  expected="$TMP/${name}.expected"
  [ -f "$fixture" ] || continue
  [ -f "$expected" ] || continue
  if interp_skipped "$name"; then
    echo "iSKIP $name (known interpreter gap)"
    ISKIP=$((ISKIP + 1))
    continue
  fi
  iactual="$TMP/${name}.iactual"
  if ! perl -e 'alarm shift; exec @ARGV' 10 "$TUNGSTEN" run "$fixture" > "$iactual" 2>&1; then
    echo "iFAIL $name (interpreter error)"
    ERRORS="${ERRORS}\n--- $name (interp) ---\n$(head -3 "$iactual")"
    IFAIL=$((IFAIL + 1))
    continue
  fi
  if diff -q "$expected" "$iactual" > /dev/null 2>&1; then
    IPASS=$((IPASS + 1))
  else
    echo "iFAIL $name (interpreter output mismatch)"
    ERRORS="${ERRORS}\n--- $name (interp diff) ---\nexpected: $(cat "$expected")\nactual:   $(cat "$iactual")"
    IFAIL=$((IFAIL + 1))
  fi
done
echo "Interpreter: $IPASS pass, $IFAIL fail, $ISKIP known-skip"

if [ -n "$ERRORS" ]; then
  echo ""
  echo "=== Failures ==="
  echo -e "$ERRORS"
fi

exit $((FAIL + IFAIL))
