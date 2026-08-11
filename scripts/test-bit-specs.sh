#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-"$ROOT/bin/tungsten"}"
COMPILER="$ROOT/bin/tungsten-compiler"
TMP_ROOT="${TUNGSTEN_BIT_SPECS_TMP_ROOT:-${TMPDIR:-/tmp}/tungsten-bit-specs.$$}"
BIT_SPEC_TIMEOUT_SECONDS="${BIT_SPEC_TIMEOUT_SECONDS:-300}"

cleanup() {
  rm -rf "$TMP_ROOT"
}
if [[ "${1:-}" != "--worker" ]]; then
  trap cleanup EXIT
fi

cd "$ROOT"
mkdir -p "$TMP_ROOT/results" "$TMP_ROOT/bin"

run_bounded() {
  # POSIX alarm state survives exec, so this gives macOS and Linux the same
  # per-suite watchdog without depending on GNU `timeout` or Homebrew paths.
  perl -e 'alarm shift; exec @ARGV' "$BIT_SPEC_TIMEOUT_SECONDS" "$@"
}

if [[ ! -x "$COMPILER" ]]; then
  echo "bin/tungsten-compiler is missing; run bin/tungsten build first." >&2
  exit 1
fi

# Discovery is intentionally based on tracked files. An uncommitted local
# scratch spec must not change the root suite, while a newly committed spec
# must either be a runnable bit suite or one of Carbide's generator fixtures.
tracked_specs=()
while IFS= read -r path; do
  tracked_specs+=("$path")
done < <(git ls-files | awk '/^bits\/.*\/spec\/.*_spec\.w$/')

ordinary_specs=()
fixture_specs=()
unclassified=()
for path in "${tracked_specs[@]}"; do
  fields="$(awk -F/ '{print NF}' <<<"$path")"
  if [[ "$fields" == "4" && "$path" == bits/*/spec/*_spec.w ]]; then
    ordinary_specs+=("$path")
  elif [[ "$path" == bits/tungsten-carbide/lib/bit/blueprints/*/template/spec/* && "$path" == *%file_name%*_spec.w ]]; then
    fixture_specs+=("$path")
  else
    unclassified+=("$path")
  fi
done

if [[ ${#unclassified[@]} -ne 0 ]]; then
  echo "unclassified tracked bit specs:" >&2
  printf '  %s\n' "${unclassified[@]}" >&2
  echo "classify each as a runnable suite or an explicit generator fixture" >&2
  exit 1
fi

# These are templates emitted by Carbide's generators, not executable suites:
# their placeholder names deliberately are not valid Tungsten programs. The
# runnable Carbide specs (including template_spec.w) exercise the corresponding
# bit and generator contracts. Pin the complete fixture set so a new template
# cannot disappear into this classification silently.
if [[ ${#fixture_specs[@]} -ne 18 ]]; then
  echo "expected 18 Carbide blueprint spec fixtures; found ${#fixture_specs[@]}" >&2
  printf '  %s\n' "${fixture_specs[@]}" >&2
  exit 1
fi

special_specs=()
generic_specs=()
for path in "${ordinary_specs[@]}"; do
  case "$path" in
    bits/tungsten-wassat/spec/*|bits/tungsten-wrat/spec/*)
      special_specs+=("$path") ;;
    *)
      generic_specs+=("$path") ;;
  esac
done

jobs="${JOBS:-auto}"
if [[ "$jobs" == "auto" ]]; then
  jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
  (( jobs > 8 )) && jobs=8
  (( jobs < 1 )) && jobs=1
fi

run_one() {
  local path="$1"
  local key="${path//\//__}"
  local out="$TMP_ROOT/bin/${key%.w}"
  local log="$TMP_ROOT/results/$key.log"
  local status=0

  # Argon relies on compiled option-parser lowering and Hammer exercises a
  # native string-pointer builtin. The remaining ordinary bit suites are
  # language/library contracts and run through the interpreter, avoiding a
  # second native build matrix inside the root correctness gate.
  case "$path" in
    bits/tungsten-argon/spec/argon_spec.w|bits/tungsten-hammer/spec/hammer_spec.w|bits/tungsten-drawille/spec/inspection_spec.w)
      if ! run_bounded env TUNGSTEN_INCREMENTAL=0 "$TUNGSTEN" compile "$path" --out "$out" --no-lto >"$log" 2>&1; then
        status=1
      elif ! run_bounded "$out" >>"$log" 2>&1; then
        status=1
      fi
      ;;
    bits/tungsten-spec/spec/smoke_spec.w)
      # The framework smoke suite deliberately contains two failures. It is a
      # negative contract, not a skipped suite: require its nonzero exit and
      # exact accounting before accepting it.
      if run_bounded "$TUNGSTEN" run "$path" >"$log" 2>&1; then
        echo "FAIL: deliberate-failure smoke suite exited successfully" >>"$log"
        status=1
      elif ! grep -Eq '^8 examples: 6 passed, 2 failed, 1 pending$' "$log" ||
           ! grep -q 'FAILS on unequal ints (deliberate)' "$log" ||
           ! grep -q 'FAILS with a runtime error (deliberate)' "$log"; then
        echo "FAIL: deliberate-failure smoke suite emitted unexpected results" >>"$log"
        status=1
      fi
      ;;
    *)
      if ! run_bounded "$TUNGSTEN" run "$path" >"$log" 2>&1; then
        status=1
      fi
      ;;
  esac

  if [[ "$status" == "0" ]] &&
     [[ "$path" != "bits/tungsten-spec/spec/smoke_spec.w" ]] &&
     grep -q '^use spec\([[:space:]]\|$\)' "$path" &&
     ! grep -Eq '^[0-9]+ examples(:|,).*0 failed' "$log"; then
    echo "FAIL: spec framework suite emitted no zero-failure summary" >>"$log"
    status=1
  fi
  echo "$status" > "$TMP_ROOT/results/$key.status"
}

if [[ "${1:-}" == "--worker" ]]; then
  run_one "$2"
  exit 0
fi

export ROOT TUNGSTEN COMPILER TMP_ROOT BIT_SPEC_TIMEOUT_SECONDS
export TUNGSTEN_BIT_SPECS_TMP_ROOT="$TMP_ROOT"
export -f run_bounded run_one

printf 'bit specs: %d runnable, %d generator fixtures\n' \
  "${#ordinary_specs[@]}" "${#fixture_specs[@]}"
printf '%s\n' "${generic_specs[@]}" |
  xargs -P "$jobs" -I{} bash "$0" --worker "{}"

failed=0
for path in "${generic_specs[@]}"; do
  key="${path//\//__}"
  status="$(cat "$TMP_ROOT/results/$key.status")"
  if [[ "$status" == "0" ]]; then
    echo "PASS $path"
  else
    echo "FAIL $path" >&2
    cat "$TMP_ROOT/results/$key.log" >&2
    failed=1
  fi
done

if [[ "$failed" -ne 0 ]]; then
  echo "bit specs: FAIL" >&2
  exit 1
fi

# Wassat/Wrat retain the execution-mode split and stronger summary checks in
# the main harness. BIT_SPECS_ONLY prevents any root/core suite duplication.
BIT_SPECS_ONLY=1 "$ROOT/scripts/test-specs.sh"

echo "bit specs: PASS"
