#!/bin/bash
# Keyword-argument unification repro suite. A call-site kwargs group
# (`f(a: 1, b: 2)`) passes as ONE hash marked W_HASH_FLAG_KWARGS; callees
# with declared keyword params rebind by NAME at entry (w_kwargs_remap12 /
# interpreter kwargs_remap_args), callees without keyword params receive the
# group as an ordinary trailing hash (`options = {}` collapse). Every repro
# runs COMPILED and INTERPRETED, checks sentinels, and requires the two
# engines' outputs to be byte-identical.
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
  local src="spec/fixtures/repros/kwargs/$name.w"

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

  # Cross-engine identity: kwargs semantics must not diverge again.
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

run_repro named_binding \
  "pad hi/10 align=right pc=< >" \
  "pad hi/10 align=left pc=<_>" \
  "pad hi/10 align=mid pc=<*>" \
  "pad hi/10 align=left pc=< >"

run_repro ctor_kwargs \
  "widget a=5 name=x" \
  "widget a=7 name=~" \
  "widget a=~ name=only" \
  "dec scale=2" \
  "dec scale=4"

run_repro options_hash \
  "auto=true" \
  "enabled=true" \
  "auto2=true" \
  "port2=8443" \
  "auto3=false" \
  "mode3=manual"

run_repro extra_kwargs \
  "plain a={a: 1, b: 2} b=~" \
  "fill slot={stray: 9} depth=3" \
  "fill slot=s1 depth=2"

run_repro positional_mix \
  "mix 1,2,x,y" \
  "mix 1,2,C,y" \
  "mix 1,2,px,y" \
  "mix 1,2,C,D" \
  "mix 1,2,px,pd" \
  "lone a=~ b=2"

run_repro fn_and_static \
  "fn hello wren!" \
  "fn hello wren?" \
  "fn yo wren." \
  "static chair size=M color=none" \
  "static chair size=M color=red" \
  "static chair size=XL color=red" \
  "dyn >a" \
  "dyn #b"

run_repro block_kwargs \
  "block saw 300" \
  "block saw 8" \
  "done"

if [ "$FAIL" -ne 0 ]; then
  echo "kwargs repros: FAILURES"
  exit 1
fi
echo "kwargs repros: all green"
