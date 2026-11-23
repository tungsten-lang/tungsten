#!/bin/sh
# memstat.sh [--heap] CMD [ARGS...]
#   CPU seconds (user+sys) and peak RSS from /usr/bin/time -l.
#   --heap: also the live malloc heap at exit (the runner must honour JSRUN_PAUSE=1 by
#   printing "jsrun: paused" to stderr and waiting): total blocks, bytes, and the count of
#   16-byte blocks, from `heap -s --showSizes`.
# Every run is capped with TUNGSTEN_MEMORY_LIMIT (default 4.5G) and timeout (default 600 s).
heapmode=0
if [ "$1" = "--heap" ]; then heapmode=1; shift; fi
: "${TUNGSTEN_MEMORY_LIMIT:=4.5G}"; export TUNGSTEN_MEMORY_LIMIT
T=${MEMSTAT_TIMEOUT:-600}
tmp=$(mktemp -d)
if [ $heapmode = 0 ]; then
  /usr/bin/time -l timeout "$T" "$@" > "$tmp/out" 2> "$tmp/err"
  st=$?
  user=$(awk '/ user /{print $3}' "$tmp/err"); sys=$(awk '/ sys/{print $5}' "$tmp/err")
  rss=$(awk '/maximum resident set size/{print $1}' "$tmp/err")
  real=$(awk '/ real /{print $1}' "$tmp/err")
  echo "cpu $(echo "$user + $sys" | bc) s  real ${real} s  peak_rss $((rss / 1048576)) MB  exit $st"
  grep -v "^ *[0-9]" "$tmp/err" | grep -v "real.*user.*sys" | head -5
  head -3 "$tmp/out" | sed 's/^/  out: /'
else
  JSRUN_PAUSE=1 timeout "$T" "$@" > "$tmp/out" 2> "$tmp/err" &
  pid=$!
  while kill -0 $pid 2>/dev/null && ! grep -q "jsrun: paused" "$tmp/err"; do sleep 0.2; done
  if kill -0 $pid 2>/dev/null; then
    rpid=$(pgrep -P $pid | head -1); [ -z "$rpid" ] && rpid=$pid
    heap -s --showSizes "$rpid" > "$tmp/heap" 2>&1
    rss=$(ps -o rss= -p "$rpid")
    { kill $pid; pkill -P $pid; wait $pid; } 2>/dev/null
    # "All zones: N nodes malloced - Sizes: 224[1000525] 128[...] ..." (K suffix = KiB)
    grep -m1 "All zones:" "$tmp/heap" | python3 -c '
import re, sys
l = sys.stdin.read()
m = re.search(r"All zones: (\d+) nodes", l)
n = int(m.group(1)) if m else 0
sz = [(float(a) * (1024 if k == "KB" else 1048576 if k == "MB" else 1), int(c)) for a, k, c in re.findall(r"([\d.]+)(KB|MB|)\[(\d+)\]", l)]
tot = sum(s * c for s, c in sz)
b16 = sum(c for s, c in sz if s == 16)
top = sorted(sz, key=lambda x: -x[1])[:6]
print("live blocks %d  bytes %.1f MB  16-byte %d  top %s" % (n, tot / 1048576, b16, " ".join("%d:%d" % (s, c) for s, c in top)))'
    echo "rss_at_exit $((rss / 1024)) MB"
  else
    echo "process exited before pausing"; tail -3 "$tmp/err"
  fi
  head -3 "$tmp/out" | sed 's/^/  out: /'
fi
rm -rf "$tmp"
