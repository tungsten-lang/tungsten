use ../lib/metaflip/fleet/refinement

if ARGV.size() == 4 && ARGV[0] == "--prepare"
  if ffbc_prepare(ARGV[1], ARGV[2], ARGV[3], []) != 1
    exit(1)
  exit(0)
if ARGV.size() == 5 && ARGV[0] == "--refine-batch"
  exit(ffrf_batch_with_composition(ARGV[1], ffw_parse_decimal_i64(ARGV[2]), ffw_parse_decimal_i64(ARGV[3]), ARGV[4]))
if ARGV.size() == 3 && ARGV[0] == "--compose-batch"
  exit(ffbc_drain(ARGV[1], ffw_parse_decimal_i64(ARGV[2])))
if ARGV.size() == 3 && ARGV[0] == "--coordinator"
  queue = MetaflipRefinement.new(ARGV[1], System.executable_path(), ARGV[2])
  cap = ffw_default_capacity(2) ## i64
  output = i64[ffw_state_size(cap)]
  start = ccall("__w_clock_ms") ## i64
  blocked = 0 ## i64
  while queue.pending() > 0 && ccall("__w_clock_ms")-start < 30000
    z = queue.poll(ccall("__w_clock_ms")) ## i64
    if queue.status_fields().includes?(" refine_blocked=1 ")
      blocked = 1
    z = queue.take_into(output, 2, 2, 2, cap, 23, 8, 3, 1000, 2000)
    if z < 0
      exit(1)
    ccall("__w_sleep", ~0.001)
  stopped = queue.stop() ## i64
  if stopped != 1 || queue.pending() != 0 || queue.failures() != 0 || blocked != 1
    << "FAIL backpressure coordinator" + queue.status_fields()
    exit(1)
  << "PASS backpressure coordinator" + queue.status_fields()
  exit(0)
if ARGV.size() != 0
  exit(2)
n = 1 ## i64
while n <= 63
  m = 1 ## i64
  while m <= 63
    p = 1 ## i64
    while p <= 63
      reserve = ffrf_composition_reserve(n, m, p) ## i64
      if ffrf_shape_valid(n, m, p) == 1 && (reserve < 1 || reserve > 1269)
        exit(1)
      p += 1
    m += 1
  n += 1
if ffrf_composition_reserve(4, 8, 4) != 360 || ffrf_composition_reserve(5, 5, 5) != 342 || ffrf_composition_reserve(1, 1, 63) != 1206 || ffrf_composition_reserve(8, 8, 8) != 0
  exit(1)
<< "PASS composition reservation: every supported narrow shape, singleton axes, invalid shapes"
