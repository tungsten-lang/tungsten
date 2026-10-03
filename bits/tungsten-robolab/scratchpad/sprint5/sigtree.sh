#!/bin/sh
# sigtree.sh SIGNAL PID...  -- send SIGNAL (STOP / CONT) to the given pids and all their descendants (only what you name; never a pattern)
SIG=$1; shift
for root in "$@"; do
  all="$root"; frontier="$root"
  while [ -n "$frontier" ]; do
    next=""
    for p in $frontier; do
      kids=$(pgrep -P "$p" 2>/dev/null)
      [ -n "$kids" ] && next="$next $kids"
    done
    all="$all $next"; frontier="$next"
  done
  kill -$SIG $all 2>/dev/null
  echo "signal $SIG to the tree of $root: $(echo $all | wc -w) processes"
done
