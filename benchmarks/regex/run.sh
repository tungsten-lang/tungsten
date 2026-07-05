#!/usr/bin/env bash
# Benchmark the homegrown Tungsten regex engine vs oniguruma (via Ruby) and the
# POSIX C engine. Pattern (\d+)-(\d+) on a 31-char subject. Run from repo root.
set -euo pipefail
cd "$(dirname "$0")/../.."
echo "== regex match throughput: (\\d+)-(\\d+) on a 31-char string =="
bin/tungsten -o /tmp/bench_mine benchmarks/regex/bench_mine.w >/dev/null 2>&1
/tmp/bench_mine
clang -O2 benchmarks/regex/bench_posix.c -o /tmp/bench_posix && /tmp/bench_posix
ruby -e 's="the order id is 4521-9837 today"; r=/(\d+)-(\d+)/; n=5_000_000; r.match(s)
t=Process.clock_gettime(Process::CLOCK_MONOTONIC); n.times{ r.match(s) }
e=Process.clock_gettime(Process::CLOCK_MONOTONIC); ms=(e-t)*1000
printf("onig (Ruby %s): %.0f ms / %d matches = %.0f ns/match\n", RUBY_VERSION, ms, n, ms*1e6/n)'
rm -f /tmp/bench_mine /tmp/bench_posix
