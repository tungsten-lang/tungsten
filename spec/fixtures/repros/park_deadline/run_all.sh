#!/bin/bash
# park_deadline repro suite: a goroutine parked on a socket with a deadline
# (w_socket_park_until) must be woken when the deadline expires even under a
# PERSISTENT scheduler. Before the fix, persistent mode's idle event poll
# blocked with timeout -1 and the deadline sweep never ran — both programs
# here hung forever (the "before" state is a timeout kill; see file headers).
# Compiled-only: Socket / go / ccall are compiled-runtime builtins.
#
#   park_deadline.w     — raw park deadline (ccall w_socket_read_fd_until)
#   set_timeout_read.w  — boxed Socket#set_timeout + #read returning nil
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

# Run one repro compiled. The deadline in each program is <= 2s, so a
# healthy run exits well under the 30s guard; min/max wall-time bounds
# assert the deadline fired neither early nor via hang-then-kill.
run_repro() { # name min_secs max_secs sentinel...
  local name="$1" min_s="$2" max_s="$3"
  shift 3
  local src="spec/fixtures/repros/park_deadline/$name.w"

  if ! bin/tungsten -o "$TMP/$name" "$src" >"$TMP/$name.build" 2>&1; then
    echo "FAIL $name: build failed"
    tail -5 "$TMP/$name.build" | sed 's/^/    | /'
    FAIL=1
    return
  fi

  local start end rc
  start=$(python3 -c 'import time; print(time.time())')
  timeout 30 "$TMP/$name" >"$TMP/$name.out" 2>&1
  rc=$?
  end=$(python3 -c 'import time; print(time.time())')

  if [ "$rc" -ne 0 ]; then
    echo "FAIL $name: exit $rc (124/137 = hung until killed — deadline never fired)"
    sed 's/^/    | /' "$TMP/$name.out"
    FAIL=1
    return
  fi

  if ! python3 -c "import sys; e = $end - $start; sys.exit(0 if $min_s <= e <= $max_s else 1)"; then
    python3 -c "print(f'FAIL $name: wall time {$end-$start:.2f}s outside [$min_s, $max_s]s')"
    FAIL=1
    return
  fi

  check_output "$name" "$TMP/$name.out" "$@"
}

# 2s park deadline: must fire (>= 1.9s, not early) and exit promptly.
run_repro park_deadline 1.9 15 \
  "park-deadline: connected" \
  "park-deadline: parking with 2s deadline" \
  "park-deadline: fired"

# 1.5s boxed Socket#set_timeout read deadline: nil read at ~1.5s.
run_repro set_timeout_read 1.4 15 \
  "set-timeout-read: connected" \
  "set-timeout-read: nil (deadline fired)"

if [ "$FAIL" -ne 0 ]; then
  echo "park_deadline repros: FAILURES"
  exit 1
fi
echo "park_deadline repros: all green"
