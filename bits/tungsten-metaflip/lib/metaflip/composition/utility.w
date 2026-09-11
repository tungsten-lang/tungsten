# Scheduling telemetry only. One native composition worker owns these writes.
# Call only AFTER a full tensor gate. Never use utility as tensor authority.
# First observation establishes a baseline; only later strict rank decreases
# earn credit. Targets are canonicalized across axis permutations. The small
# index has one file per target, not one per candidate. Credit is attributed
# to the originating campaign, not asserted as a causal theorem about a leaf.
use counters

-> ffcu_shape(n, m, p) (i64 i64 i64)
  a = n ## i64
  b = m ## i64
  c = p ## i64
  if a > b
    t = a ## i64
    a = b
    b = t
  if b > c
    t = b ## i64
    b = c
    c = t
  if a > b
    t = a ## i64
    a = b
    b = t
  a.to_s() + "x" + b.to_s() + "x" + c.to_s()

-> ffcu_source(root, n, m, p) (String i64 i64 i64) i64
  shape = ffcu_shape(n,m,p)
  path = root + "/composition/utility/source"
  old = File.read_prefix(path, 64)
  if old != nil
    if old == shape + "\n" || old == "mixed\n"
      return 1
    # A custom status path can intentionally share intake across shapes.
    # Preserve intake, but stop attributing its combined gains to one parent.
    return ffrf_atomic(path, "mixed\n", "utility-source")
  if !File.mkdir_p(root + "/composition/utility")
    return 0
  ffrf_atomic(path, shape + "\n", "utility-source")

-> ffcu_record(root, identity, rank, n, m, p) (String String i64 i64 i64 i64) i64
  if ffrf_hash_valid(identity) != 1 || rank < 1 || rank > 16384 || n < 1 || m < 1 || p < 1 || n > 1024 || m > 1024 || p > 1024
    return 0
  queue = root + "/composition/utility/"
  source = File.read_prefix(queue + "source", 64)
  shape = ffcu_shape(n,m,p)
  if source == nil || source == "mixed\n" || source.strip() == shape
    return 1
  if !File.mkdir_p(queue + "best")
    return 0
  path = queue + "best/" + shape
  old = File.read_prefix(path, 100)
  previous = 0 ## i64
  if old != nil
    fields = old.strip().split(" ")
    if fields.size() != 2 || ffrf_hash_valid(fields[1]) != 1
      return 0
    previous = ffw_parse_decimal_i64(fields[0])
    canonical = previous.to_s() + " " + fields[1] + "\n"
    if previous < 1 || previous > 16384 || old != canonical
      return 0
    if rank >= previous
      return 1
  credit = ffmd_count(queue + "saved") ## i64
  if credit < 0 || credit > 1000000000000
    return 0
  # Commit the monotonic baseline first: a crash can lose telemetry credit,
  # but replay cannot manufacture it twice.
  if ffrf_atomic(path, rank.to_s() + " " + identity + "\n", "utility") != 1
    return 0
  if previous == 0
    return 1
  ffrf_atomic(queue + "saved", (credit+previous-rank).to_s() + "\n", "utility")
