#!/bin/bash
# Interpreter/stdlib gap repro suite (round 2). Each repro pins an
# interpreter behavior that diverged from the compiled engine:
#   string_index_offset   — String#index/#rindex dropped their offset arg
#   nested_array_oob      — generic [] rode the UNCHECKED w_array_idx IC row
#                           (nested OOB read returned a neighboring word)
#   index_compound_assign — `h[k] += v` raised "Invalid compound assignment
#                           target"
#   lambda_block_promotion— Enumerable trait never autoloaded for lazily
#                           loaded core classes (sort_by/min_by/max_by
#                           undefined; trait sort shadowed Array#sort(&) and
#                           recursed)
#   floor_and_gsub        — bodyless Decimal facade methods "ran" as empty
#                           bodies (3.7.floor crashed); gsub missing interp
#   sort_bang             — sort!/mergesort! called the never-implemented
#                           array_mergesort! extern (undefined method on
#                           BOTH engines); comparator blocks on sort were
#                           silently ignored (both engines sorted ascending)
#   sum_init              — interp Array#sum(init) builtin discarded init
#                           (compiled twin was fixed in e857a36)
# Every repro runs COMPILED and INTERPRETED, checks sentinels, and requires
# the two engines' outputs to be byte-identical.
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
  local src="spec/fixtures/repros/interp_gaps/$name.w"

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

  # Cross-engine identity: these gaps must not diverge again.
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

run_repro string_index_offset \
  "index base=0 off1=12 o5=7" \
  "rindex base=12 cap11=0 o6=4" \
  "past-end-nil=true"

run_repro nested_array_oob \
  "m9-nil=true" \
  "m2-nil=true" \
  "m100-nil=true" \
  "mneg=3-4" \
  "flat9-nil=true" \
  "lit9-nil=true" \
  "oob-set-size=2"

run_repro index_compound_assign \
  "h-plus=6" \
  "h-minus=4" \
  "tally=2" \
  "arr=5-27-60" \
  "str=abcd"

run_repro lambda_block_promotion \
  "sort_by=a-bb-ccc" \
  "min_by=a" \
  "max_by=ccc" \
  "trailing=a-bb-ccc" \
  "desc=5-4-1" \
  "sort=1-2-3" \
  "nested-sort=1-5"

run_repro floor_and_gsub \
  "floor=3" \
  "ceil=4" \
  "negfloor=-3" \
  "round=3" \
  "gsub=x-b-x" \
  "gsub2=hell0 w0rld" \
  "gsub3=ba" \
  "gsub-miss=abc"

run_repro sort_bang \
  "sort_bang=[1, 2, 3]" \
  "sort_bang_chain=[1, 2]" \
  "sort_desc=[3, 2, 1]" \
  "sort_src_unchanged=[3, 1, 2]" \
  "sort_bang_desc=[3, 2, 1]" \
  "mergesort_bang=[1, 4, 5, 9]" \
  "mergesort_bang_desc=[9, 5, 4, 1]" \
  "stable_sort=b,d,cc,aa,ee" \
  "stable_mergesort_bang=b,d,cc,aa,ee"

run_repro sum_init \
  "sum_init=16" \
  "sum_plain=6" \
  "sum_empty_init=5" \
  "sum_float_init=5"

if [ "$FAIL" -ne 0 ]; then
  echo "interp_gaps repros: FAILURES"
  exit 1
fi
echo "interp_gaps repros: all green"
