#!/bin/bash
# static_inherit repro suite: class-method (static) inheritance must work
# identically compiled and interpreted. Before the fix, compiled
# `Post.create(...)` with `-> .create` defined on Model died with
# "undefined method 'create' for Post": the compile-time
# known_static_methods lookup was exact-key only and the runtime
# w_static_method_lookup did not walk the superclass chain.
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
  local src="spec/fixtures/repros/static_inherit/$name.w"

  # Compiled
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

  # Interpreted
  if timeout 60 bin/tungsten "$src" >"$TMP/$name.iout" 2>&1; then
    check_output "$name (interp)" "$TMP/$name.iout" "$@"
  else
    echo "FAIL $name (interp): exit $?"
    sed 's/^/    | /' "$TMP/$name.iout"
    FAIL=1
  fi
}

run_repro inherited_statics \
  "post:attrs=hello" "post-tag:post-instance" "post-kind:post" \
  "model-kind:model" \
  "comment:attrs=deep" "comment-tag:comment-instance" "comment-kind:post"

if [ "$FAIL" -ne 0 ]; then
  echo "static_inherit repros: FAILURES"
  exit 1
fi
echo "static_inherit repros: all green"
