# Focused interpreter benchmark for the REPL spelling:
#
#   i = 0
#   0..N -> i++
#
# Keep this source intentionally free of timing calls so the same workload can
# be measured around compiler startup with `/usr/bin/time`.
n = ARGV.size() > 0 ? ARGV[0].to_i() : 1_000_000
i = 0
0..n -> i++
raise "range result mismatch" if i != n + 1
