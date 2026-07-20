#!/bin/bash
# Float-literal / Decimal method-surface repro suite.
#
# ROOT CAUSE (not "poisoning"): a decimal literal such as `0.1` / `10.0`
# evaluates to an exact Decimal (0xFFFD numeric tag), NOT a Float (`~10.0` is
# the Float form). The runtime's dedicated Decimal IC table
# (w_ic_decimal_table) carried to_i/sqrt/floor/ceil/round/sq but OMITTED to_f
# and abs, so `(0.1).to_f` — anywhere, with or without a division or an
# "earlier" float literal — died "undefined method 'to_f' for Object
# (numeric 0xfffd...)". Data-derived floats (`2.to_f`) are genuine Floats with
# the complete Float surface, so they were "immune". The fix adds to_f and abs
# to w_ic_decimal_table (runtime/runtime.c), so decimal literals may now cross
# method boundaries by converting explicitly.
#
# Every repro runs COMPILED and INTERPRETED, checks sentinels, and requires
# the two engines' outputs to be byte-identical (the bug hit both because the
# interpreter is itself a compiled program sharing this runtime IC).
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
  local src="spec/fixtures/repros/float_literal_poison/$name.w"

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

  # Cross-engine identity: the Decimal method surface must not diverge.
  if [ -f "$TMP/$name.out" ] && [ -f "$TMP/$name.iout" ]; then
    if diff -u "$TMP/$name.out" "$TMP/$name.iout" >"$TMP/$name.diff" 2>&1; then
      echo "OK   $name (engines identical)"
    else
      echo "FAIL $name: compiled and interpreted outputs differ"
      sed 's/^/    | /' "$TMP/$name.diff"
      FAIL=1
    fi
  fi
}

# The committed repro: a float literal at top level used in a division, then
# the result crosses into a constructor argument via `.to_f`.
run_repro poison \
  "local x:            0.1" \
  "ctor x.to_f after float literal: 0.1"

# Minimal-minimal: a bare decimal literal's `.to_f`, no boundary at all.
run_repro bare_to_f \
  "bare to_f: 0.5" \
  "bare to_f neg: -0.25"

# The sibling IC omission: Decimal#abs stays exact.
run_repro abs_decimal \
  "abs pos: 0.25" \
  "abs neg: 0.25" \
  "abs whole: 5"

# Previously-forbidden shape: decimal literal as a method / constructor arg.
run_repro method_arg \
  "method arg to_f: 0.2" \
  "ctor arg to_f: 0.75"

# Decimal literals in an array literal crossing into a function.
run_repro array_literal \
  "array to_f: [0.1, 0.2, 0.3]" \
  "array abs: [0.1, 0.2, 0.3]"

if [ "$FAIL" -ne 0 ]; then
  echo "float_literal_poison repros: FAILURES"
  exit 1
fi
echo "float_literal_poison repros: all green"
