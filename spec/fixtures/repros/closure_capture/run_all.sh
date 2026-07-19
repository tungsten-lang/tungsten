#!/bin/bash
# Closure-capture repro suite: a method that builds and returns (or stores)
# a closure over a captured variable must keep that capture alive after the
# creating frame exits. Runs every repro COMPILED and INTERPRETED and checks
# the sentinel output lines. See v7/v9a/v9c/closure_repro2 headers.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAIL=0

check_output() { # label file sentinel...
  local label="$1" file="$2"
  shift 2
  for s in "$@"; do
    if ! grep -qF "$s" "$file"; then
      echo "FAIL $label: missing sentinel '$s'"
      sed 's/^/    | /' "$file"
      FAIL=1
      return 1
    fi
  done
  echo "OK   $label"
}

run_repro() { # name sentinel...
  local name="$1"
  shift
  local src="spec/fixtures/repros/closure_capture/$name.w"

  # Compiled
  if bin/tungsten -o "$TMP/$name" "$src" >"$TMP/$name.build" 2>&1; then
    if "$TMP/$name" >"$TMP/$name.out" 2>&1; then
      check_output "$name (compiled)" "$TMP/$name.out" "$@"
    else
      echo "FAIL $name (compiled): exit $? running binary"
      sed 's/^/    | /' "$TMP/$name.out"
      FAIL=1
    fi
  else
    echo "FAIL $name (compiled): build failed"
    tail -5 "$TMP/$name.build" | sed 's/^/    | /'
    FAIL=1
  fi

  # Interpreted
  if bin/tungsten "$src" >"$TMP/$name.iout" 2>&1; then
    check_output "$name (interp)" "$TMP/$name.iout" "$@"
  else
    echo "FAIL $name (interp): exit $?"
    sed 's/^/    | /' "$TMP/$name.iout"
    FAIL=1
  fi
}

run_compiled_only() { # name sentinel...
  local name="$1"
  shift
  local src="spec/fixtures/repros/closure_capture/$name.w"
  if bin/tungsten -o "$TMP/$name" "$src" >"$TMP/$name.build" 2>&1; then
    if timeout 30 "$TMP/$name" >"$TMP/$name.out" 2>&1; then
      check_output "$name (compiled)" "$TMP/$name.out" "$@"
    else
      echo "FAIL $name (compiled): exit $? running binary"
      sed 's/^/    | /' "$TMP/$name.out"
      FAIL=1
    fi
  else
    echo "FAIL $name (compiled): build failed"
    tail -5 "$TMP/$name.build" | sed 's/^/    | /'
    FAIL=1
  fi
}

run_repro v7 "shown:one" "shown:two"
run_repro v9a "shown:one" "shown:two"
run_repro v9c "shown:one" "shown:two"
run_repro closure_repro2 "shown:one" "shown:two" "shown:three"
# Goroutine shapes: Channel / go are compiled-runtime builtins (the
# interpreter silently no-ops them), so these run compiled-only.
run_compiled_only loop_slot "sum: 100" "distinct: truetruetruetrue" "range sum: 60"
run_compiled_only local_vs_param "param ok: true" "local ok: true"

if [ "$FAIL" -ne 0 ]; then
  echo "closure_capture repros: FAILURES"
  exit 1
fi
echo "closure_capture repros: all green"
