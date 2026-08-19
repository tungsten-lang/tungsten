#!/usr/bin/env bash
# Time the shipped compiled-lane path on the FAST compiled list against
# compiling those same specs independently with incremental caching disabled.
# Also pins that a FAIL line still fails the suite.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-"$ROOT/bin/tungsten"}"
CLASSIFY="$ROOT/scripts/spec-lanes.sh"
HARNESS="$ROOT/scripts/test-specs.sh"
OUT_DIR="${TUNGSTEN_SPECS_SLICE_OUT:-}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-spec-slice.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

cd "$ROOT"

if [[ ! -x "$ROOT/bin/tungsten-compiler" ]]; then
  echo "bin/tungsten-compiler is missing; run bin/tungsten build first." >&2
  exit 1
fi

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$TMP/out"
fi
mkdir -p "$OUT_DIR"

JOBS="${JOBS:-auto}"
if [[ "$JOBS" == "auto" ]]; then
  JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
  JOBS=$(( JOBS - 2 ))
  (( JOBS < 1 )) && JOBS=1
fi

"$CLASSIFY" --print-lane fast-compiled >"$TMP/slice.list"
slice=()
while IFS= read -r path; do
  [[ -n "$path" ]] && slice+=("$path")
done <"$TMP/slice.list"
if [[ ${#slice[@]} -eq 0 ]]; then
  echo "FAIL: fast-compiled lane is empty" >&2
  exit 1
fi

# --- FAIL line still fails the shipped compiled-lane path ------------------
# Copy a known-good compiled spec and append a FAIL line so this drives
# compile+run, not a compile-error path.
cp spec/compiler/typed_overload_spec.w "$TMP/fail_slice_spec.w"
printf '\n<< "FAIL compiled-slice contract"\n' >>"$TMP/fail_slice_spec.w"
set +e
"$HARNESS" --compiled-slice "$TMP/fail_slice_spec.w" \
  >"$OUT_DIR/fail-contract.log" 2>&1
fail_status=$?
set -e
if [[ "$fail_status" -eq 0 ]]; then
  echo "FAIL: compiled slice accepted a FAIL-line spec" >&2
  cat "$OUT_DIR/fail-contract.log" >&2
  exit 1
fi
grep -Fq 'FAIL [fail_slice_spec] emitted failing checks' "$OUT_DIR/fail-contract.log"
grep -Fq 'test-specs: FAIL (compiled slice)' "$OUT_DIR/fail-contract.log"

now_seconds() {
  python3 -c 'import time; print("%.6f" % time.time())'
}

elapsed() {
  python3 -c 'import sys; print("%.6f" % (float(sys.argv[2]) - float(sys.argv[1])))' "$1" "$2"
}

median2() {
  python3 -c 'import sys; a=float(sys.argv[1]); b=float(sys.argv[2]); print("%.6f" % ((a+b)/2.0))' "$1" "$2"
}

run_harness() {
  local label="$1"
  local log="$OUT_DIR/spec-perf-$label.log"
  local started ended
  started="$(now_seconds)"
  set +e
  TUNGSTEN_CACHE_DIR="$OUT_DIR/harness-cache" \
    TUNGSTEN_SPECS_BIN_DIR="$OUT_DIR/harness-cache/bin" \
    TUNGSTEN_SPECS_PROFILE_FILE="$OUT_DIR/specs.profile" \
    JOBS="$JOBS" \
    "$HARNESS" --compiled-slice "${slice[@]}" >"$log" 2>&1
  local status=$?
  set -e
  ended="$(now_seconds)"
  local wall
  wall="$(elapsed "$started" "$ended")"
  printf '%s\n' "$wall" >"$OUT_DIR/$label.wall"
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL: harness $label exited $status" >&2
    cat "$log" >&2
    exit 1
  fi
  if ! grep -q 'test-specs: OK (compiled slice)' "$log"; then
    echo "FAIL: harness $label missing compiled-slice OK line" >&2
    cat "$log" >&2
    exit 1
  fi
  local path name
  for path in "${slice[@]}"; do
    name="$(basename "${path%.w}")"
    if ! grep -Fq "PASS [$name]" "$log"; then
      echo "FAIL: harness $label did not PASS $name" >&2
      cat "$log" >&2
      exit 1
    fi
    if grep -Fq "FAIL [$name]" "$log"; then
      echo "FAIL: harness $label reported FAIL for $name" >&2
      cat "$log" >&2
      exit 1
    fi
  done
  printf '%s\n' "$wall"
}

run_independent() {
  local label="$1"
  local log="$OUT_DIR/spec-perf-$label.log"
  local work="$TMP/$label"
  mkdir -p "$work/results"
  local started ended
  started="$(now_seconds)"
  set +e
  printf '%s\n' "${slice[@]}" | JOBS="$JOBS" WORK="$work" TUNGSTEN="$TUNGSTEN" \
    xargs -P "$JOBS" -I{} bash -c '
      set -euo pipefail
      path="$1"
      name="$(basename "${path%.w}")"
      dir="$WORK/$name"
      mkdir -p "$dir/cache"
      log="$dir/run.log"
      status=0
      if ! TUNGSTEN_INCREMENTAL=0 TUNGSTEN_CACHE_DIR="$dir/cache" \
          "$TUNGSTEN" compile "$path" --out "$dir/bin" >"$log" 2>&1; then
        status=1
      elif ! TUNGSTEN_SPEC_QUIET=1 "$dir/bin" >>"$log" 2>&1; then
        status=1
      fi
      echo "$status" > "$WORK/results/$name.status"
      cp "$log" "$WORK/results/$name.log"
    ' _ {} >"$log" 2>&1
  local xstatus=$?
  set -e
  ended="$(now_seconds)"
  local wall
  wall="$(elapsed "$started" "$ended")"
  printf '%s\n' "$wall" >"$OUT_DIR/$label.wall"
  {
    echo "independent $label JOBS=$JOBS xargs_exit=$xstatus"
    local path name status
    for path in "${slice[@]}"; do
      name="$(basename "${path%.w}")"
      status="$(cat "$work/results/$name.status" 2>/dev/null || echo missing)"
      if [[ "$status" == "0" ]]; then
        echo "PASS [$name]"
      else
        echo "FAIL [$name] independent compile/run"
        cat "$work/results/$name.log" 2>/dev/null || true
      fi
    done
  } >>"$log"
  local path name status
  for path in "${slice[@]}"; do
    name="$(basename "${path%.w}")"
    status="$(cat "$work/results/$name.status" 2>/dev/null || echo missing)"
    if [[ "$status" != "0" ]]; then
      echo "FAIL: independent $label did not PASS $name" >&2
      cat "$log" >&2
      exit 1
    fi
  done
  printf '%s\n' "$wall"
}

echo "compiled-slice timing JOBS=$JOBS specs=${#slice[@]}"

h1="$(run_harness harness-1)"
h2="$(run_harness harness-2)"
i1="$(run_independent independent-1)"
i2="$(run_independent independent-2)"

hmed="$(median2 "$h1" "$h2")"
imed="$(median2 "$i1" "$i2")"

{
  printf 'kind\trun\tjobs\twall_seconds\tresult\n'
  printf 'harness\t1\t%s\t%s\tPASS\n' "$JOBS" "$h1"
  printf 'harness\t2\t%s\t%s\tPASS\n' "$JOBS" "$h2"
  printf 'independent\t1\t%s\t%s\tPASS\n' "$JOBS" "$i1"
  printf 'independent\t2\t%s\t%s\tPASS\n' "$JOBS" "$i2"
  printf 'harness\tmedian\t%s\t%s\tPASS\n' "$JOBS" "$hmed"
  printf 'independent\tmedian\t%s\t%s\tPASS\n' "$JOBS" "$imed"
} >"$OUT_DIR/spec-perf.tsv"

echo "harness median ${hmed}s vs independent median ${imed}s (JOBS=$JOBS)"
python3 - "$hmed" "$imed" <<'PY'
import sys
h = float(sys.argv[1])
i = float(sys.argv[2])
if not (h < i):
    raise SystemExit("FAIL: new-harness median %s is not strictly lower than independent %s" % (h, i))
PY

echo "spec-compiled-slice: PASS"
