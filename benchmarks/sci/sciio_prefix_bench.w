# Benchmark the bounded prefix primitive used by SciIO.sniff.
#
#   bin/tungsten compile --release --native --out /tmp/sciio-prefix bench...
#   /tmp/sciio-prefix /tmp/large.bin 200 16

use core/io

path = ARGV[0]
raise "usage: sciio_prefix_bench PATH [REPS] [BYTES]" if path == nil
reps = ARGV[1] == nil ? 100 : ARGV[1].to_i
bytes = ARGV[2] == nil ? 16 : ARGV[2].to_i

prefix = nil
checksum = 0
t0 = clock()
i = 0
while i < reps
  prefix = SciIO.read_prefix(path, bytes)
  checksum += prefix == nil ? 0 : prefix.size()
  i += 1
t1 = clock()

raise "prefix exceeds request" if prefix != nil && prefix.size() > bytes
ns = (t1 - t0) * ~1000000000.0 / reps
line = "BENCH sciio_prefix bytes=" + bytes.to_s
line += " reps=" + reps.to_s
line += " ns=" + ns.round(1).to_s
line += " checksum=" + checksum.to_s
<< line
