#!/bin/sh
# Serialize performance measurements across concurrent agents.
#
# Several agents work in this repo at once, and a benchmark is the one kind of
# work that cannot tolerate a neighbour: two GPU runs at the same time do not
# fail, they quietly return plausible wrong numbers. This session lost a
# measured 33% run-to-run swing to exactly that -- larger than the effect being
# measured, which turns an A/B into a coin flip.
#
# Usage:
#   scripts/bench/perf_lock.sh <command> [args...]
#
# Environment:
#   TUNGSTEN_PERF_LOCK       lock directory (default ~/.cache/tungsten/perf.lock)
#   TUNGSTEN_PERF_WAIT       seconds to wait for the lock (default 3600, 0 = fail fast)
#   TUNGSTEN_PERF_MAX_LOAD   refuse to start above this 1-min load average
#                            (default 0 = no gate; the lock cannot serialize
#                            Safari or a compile, so gate on load when the
#                            number has to be trustworthy)
#
# The lock is a directory, because mkdir is atomic on every filesystem that
# matters and needs no flock(1) -- which macOS does not ship. It lives outside
# the repo so it never shows up in git status: another agent's uncommitted work
# is already hard enough to classify.

set -e

LOCK="${TUNGSTEN_PERF_LOCK:-$HOME/.cache/tungsten/perf.lock}"
WAIT="${TUNGSTEN_PERF_WAIT:-3600}"
MAX_LOAD="${TUNGSTEN_PERF_MAX_LOAD:-0}"

if [ $# -eq 0 ]; then
  echo "usage: $0 <command> [args...]" >&2
  exit 64
fi

mkdir -p "$(dirname "$LOCK")"

holder_pid() { cat "$LOCK/pid" 2>/dev/null || echo ""; }

# A crashed run must not wedge every later benchmark, so a lock whose owner is
# gone is reclaimed rather than waited on.
reclaim_if_stale() {
  pid=$(holder_pid)
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null && return 1
  echo "perf-lock: reclaiming stale lock from dead pid $pid" >&2
  rm -rf "$LOCK"
  return 0
}

acquired=""
waited=0
while :; do
  if mkdir "$LOCK" 2>/dev/null; then
    acquired=1
    break
  fi
  reclaim_if_stale && continue
  if [ "$WAIT" -eq 0 ] || [ "$waited" -ge "$WAIT" ]; then
    echo "perf-lock: held by pid $(holder_pid) ($(cat "$LOCK/what" 2>/dev/null))" >&2
    echo "perf-lock: giving up after ${waited}s; results would not be comparable" >&2
    exit 75
  fi
  if [ "$waited" -eq 0 ]; then
    echo "perf-lock: waiting for pid $(holder_pid) ($(cat "$LOCK/what" 2>/dev/null))" >&2
  fi
  sleep 5
  waited=$((waited + 5))
done

# Only the process that created the directory writes these, so there is no race
# between acquiring and describing the holder.
echo "$$" > "$LOCK/pid"
echo "$*" > "$LOCK/what"
date > "$LOCK/since"

# Release on every exit path, including interrupts: a benchmark is exactly the
# kind of long job someone ctrl-Cs.
cleanup() { [ -n "$acquired" ] && rm -rf "$LOCK"; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

if [ "$waited" -gt 0 ]; then
  echo "perf-lock: acquired after ${waited}s" >&2
fi

# The lock serializes agents; it says nothing about the rest of the machine.
if [ "$MAX_LOAD" != "0" ]; then
  gate_waited=0
  while :; do
    load=$(uptime | sed 's/.*load averages*: *//' | awk '{print $1}' | tr -d ,)
    over=$(awk -v l="$load" -v m="$MAX_LOAD" 'BEGIN { print (l > m) ? 1 : 0 }')
    [ "$over" -eq 0 ] && break
    if [ "$gate_waited" -ge "$WAIT" ]; then
      echo "perf-lock: load $load still above $MAX_LOAD after ${gate_waited}s; running anyway" >&2
      break
    fi
    [ "$gate_waited" -eq 0 ] && echo "perf-lock: load $load above $MAX_LOAD, waiting for the box to settle" >&2
    sleep 15
    gate_waited=$((gate_waited + 15))
  done
fi

"$@"
