#!/bin/bash
# Variadic `*args` parameter-collection repro suite.
#
# A `*rest` param collects the middle arguments into a REAL array ([] when
# none remain after satisfying any trailing fixed params); fixed params may
# appear before AND after the splat and right-align against the end of args.
# Reference semantics live in the Ruby engine (interpreter.rb bind_params).
#
# Both self-hosted engines gate this suite. Compiled direct calls pack the
# middle source arguments into the callee's one Array slot; dynamic method
# dispatch carries the splat index in WMethod and performs the same binding.
# NOTE: call-site splat forwarding (`f(*arr)`) is a separate unimplemented gap
# in BOTH self-hosted engines (the parser discards the `*` marker at call
# sites); the Ruby engine handles it.
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

  # Compiled — the same sentinels are a correctness gate.
  if bin/tungsten -o "$TMP/$name" "$src" >"$TMP/$name.build" 2>&1 \
     && "$TMP/$name" >"$TMP/$name.out" 2>&1; then
    check_output "$name (compiled)" "$TMP/$name.out" "$@"
  else
    echo "FAIL $name (compiled): nonzero build or run"
    sed 's/^/    | /' "$TMP/$name.build"
    [ ! -f "$TMP/$name.out" ] || sed 's/^/    | /' "$TMP/$name.out"
    FAIL=1
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

run_repro static_splat \
  "static x=1 n=0 mid=[] z=9" \
  "static x=1 n=1 mid=[2] z=9" \
  "static x=1 n=3 mid=[2, 3, 4] z=9"

if [ "$FAIL" -ne 0 ]; then
  echo "varargs repros: FAILURES (interpreter arm)"
  exit 1
fi
echo "varargs repros: all green (interpreter + compiled)"
