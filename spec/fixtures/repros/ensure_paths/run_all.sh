#!/bin/bash
# ensure_paths repro suite: spec 4.6.5 — the ensure body runs on EVERY exit
# path from a begin region, including return/break/next transfers (not just
# fall-through and raise). Compiled lowering used to branch straight to the
# transfer target, skipping ensure entirely; the fix replays enclosing
# ensure bodies at each transfer site (emit_transfer_unwind in
# compiler/lib/lowering/control_flow.w), after the transfer value is
# computed, popping each region's exception frame before its ensure body.
# Runs every repro COMPILED and INTERPRETED and checks sentinel lines.
#
#   return_ensure.w          — return through ensure; value computed first;
#                              ensure can't change the returned value
#   break_ensure.w           — break and next through ensure in while loops
#   nested_ensure.w          — return through two nested ensures, inner first
#   ensure_raise.w           — ensure raises during a return-unwind; the
#                              raise wins and propagates OUTSIDE the begin
#   rescue_return_ensure.w   — return from a rescue body still runs ensure
#   next_ensure.w            — next through ensure inside an iterator block
#   ensure_return_override.w — return inside ensure overrides the in-flight
#                              return
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
  local src="spec/fixtures/repros/ensure_paths/$name.w"

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

run_repro return_ensure "result:11" "order:CE" "result2:1"
run_repro break_ensure "log:bcebcebe|i:2" "nlog:tuvtvtuv"
run_repro nested_ensure "result:7" "order:TIO"
run_repro ensure_raise "caught:from-ensure"
run_repro rescue_return_ensure "result:5" "order:RE"
run_repro next_ensure "log:abeaeabe"
run_repro ensure_return_override "got:2"

if [ "$FAIL" -ne 0 ]; then
  echo "ensure_paths repros: FAILURES"
  exit 1
fi
echo "ensure_paths repros: all green"
