#!/bin/sh
# killtree.sh PID...  -- SIGTERM the given pids and all their descendants (only what you name; never a pattern)
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
  kill $all 2>/dev/null
  echo "killed tree of $root: $all"
done
