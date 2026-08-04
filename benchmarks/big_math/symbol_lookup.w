# GEMMA-19: distinguish compiled local BigInt access from explicit Hash lookup.

-> print_result(lane, n, started_at, finished_at, sink)
  << lane + "\t" + n.to_s() + "\t" + ((finished_at - started_at) * ~1000000000.0 / n.to_f()).to_s() + "\t" + sink.to_s()

-> run_local(n)
  value = (1 << 4096) + 987654321
  sink = 0 ## i64
  i = 0 ## i64
  t0 = clock()
  while i < n
    sink = sink ^ (value & 65535)
    i += 1
  t1 = clock()
  print_result("local", n, t0, t1, sink)

-> run_hash(n)
  table = {"heavy": (1 << 4096) + 987654321}
  sink = 0 ## i64
  i = 0 ## i64
  t0 = clock()
  while i < n
    value = table["heavy"]
    sink = sink ^ (value & 65535)
    i += 1
  t1 = clock()
  print_result("hash", n, t0, t1, sink)

-> run_cached(n)
  table = {"heavy": (1 << 4096) + 987654321}
  value = table["heavy"]
  sink = 0 ## i64
  i = 0 ## i64
  t0 = clock()
  while i < n
    sink = sink ^ (value & 65535)
    i += 1
  t1 = clock()
  print_result("cached", n, t0, t1, sink)

args = argv()
lane = args.size() > 0 ? args[0] : "local"
n = args.size() > 1 ? args[1].to_i() : 2000001
if lane == "local"
  run_local(n)
elsif lane == "hash"
  run_hash(n)
else
  run_cached(n)
