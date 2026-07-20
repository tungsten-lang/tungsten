#!/bin/bash
# Variadic `*args` parameter-collection repro suite.
#
# A `*rest` param collects the middle arguments into a REAL array ([] when
# none remain after satisfying any trailing fixed params); fixed params may
# appear before AND after the splat and right-align against the end of args.
# Reference semantics live in the Ruby engine (interpreter.rb bind_params).
#
# ENGINE STATUS (2026-07-20):
#   * INTERPRETER (`bin/tungsten file.w`): FIXED — collects correctly, matches
#     the Ruby engine exactly. This arm GATES the suite.
#   * COMPILED (`bin/tungsten -o`): DOCUMENTED GAP. The dynamic-dispatch ABI
#     drops args beyond the callee's declared fixed arity before the function
#     is entered, so no function-body prologue can recover them; a fix needs a
#     calling-convention change across ~6 dispatch sites + the WMethod/inline-
#     cache structs + the static-call path (see the task report's compiled
#     map). Until then the compiled arm is run and REPORTED but never fails the
#     suite. NOTE: call-site splat forwarding (`f(*arr)`) is a separate
#     unimplemented gap in BOTH self-hosted engines (the self-hosted parser
#     discards the `*` marker at call sites); the Ruby engine handles it.
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
  local src="spec/fixtures/repros/varargs/$name.w"

  # Interpreter — the correctness gate.
  if bin/tungsten "$src" >"$TMP/$name.iout" 2>&1; then
    check_output "$name (interp)" "$TMP/$name.iout" "$@"
  else
    echo "FAIL $name (interp): nonzero exit"
    sed 's/^/    | /' "$TMP/$name.iout"
    FAIL=1
  fi

  # Compiled — documented gap; reported, never fails the suite.
  local ok=1
  if bin/tungsten -o "$TMP/$name" "$src" >"$TMP/$name.build" 2>&1 \
     && "$TMP/$name" >"$TMP/$name.out" 2>&1; then
    for s in "$@"; do
      grep -qF "$s" "$TMP/$name.out" || ok=0
    done
    if [ "$ok" -eq 1 ]; then
      echo "!!   $name (compiled): now MATCHES — compiled splat gap appears CLOSED; update this suite to gate the compiled arm."
    else
      echo "gap  $name (compiled): documented gap (collection not implemented in codegen)"
    fi
  else
    echo "gap  $name (compiled): documented gap (drops rest args / crashes on empty)"
  fi
}

run_repro splat_only \
  "cap n=0 v=[]" \
  "cap n=1 v=[10]" \
  "cap n=3 v=[10, 20, 30]"

run_repro lead_splat \
  "lead x=1 n=0 v=[]" \
  "lead x=1 n=1 v=[2]" \
  "lead x=1 n=3 v=[2, 3, 4]"

run_repro splat_trail \
  "trail n=0 mid=[] z=9" \
  "trail n=1 mid=[1] z=9" \
  "trail n=3 mid=[1, 2, 3] z=9"

run_repro mid_splat \
  "mid x=1 n=0 mid=[] z=9" \
  "mid x=1 n=1 mid=[2] z=9" \
  "mid x=1 n=3 mid=[2, 3, 4] z=9"

run_repro top_fn \
  "gather n=0 v=[]" \
  "gather n=1 v=[5]" \
  "gather n=3 v=[5, 6, 7]"

if [ "$FAIL" -ne 0 ]; then
  echo "varargs repros: FAILURES (interpreter arm)"
  exit 1
fi
echo "varargs repros: all green (interpreter); compiled arm = documented gap"
