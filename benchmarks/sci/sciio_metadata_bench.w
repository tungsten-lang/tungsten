# Metadata-only scientific-format probes on a large fixture.

use core/io

mode = ARGV[0]
path = ARGV[1]
reps = ARGV[2] == nil ? 10 : ARGV[2].to_i
raise "usage: sciio_metadata_bench sniff|parquet|mat PATH [REPS]" if mode == nil || path == nil

checksum = 0
t0 = clock()
i = 0
while i < reps
  if mode == "sniff"
    value = SciIO.sniff(path)
    checksum += value[:format] == :unknown ? 0 : 1
  elsif mode == "parquet"
    value = SciIO.read_parquet(path)
    checksum += value[:format] == :parquet ? 1 : 0
  elsif mode == "mat"
    value = SciIO.read_mat(path)
    checksum += value[:level]
  else
    raise "mode must be sniff, parquet, or mat"
  i += 1
t1 = clock()

ns = (t1 - t0) * ~1000000000.0 / reps
line = "BENCH sciio_metadata mode=" + mode
line += " reps=" + reps.to_s
line += " ns=" + ns.round(1).to_s
line += " checksum=" + checksum.to_s
<< line
