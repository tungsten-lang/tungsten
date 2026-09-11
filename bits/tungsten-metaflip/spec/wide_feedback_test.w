use ../lib/metaflip/fleet/refinement
use ../lib/metaflip/composition/worker

if ARGV.size() == 4 && ARGV[0] == "--refine-batch"
  exit(ffrf_batch(ARGV[1], ffpk_decimal(ARGV[2]), ffpk_decimal(ARGV[3])))
if ARGV.size() == 3 && ARGV[0] == "--publish"
  root = ARGV[1]
  raw = File.read_prefix(ARGV[2], 12632129)
  if raw == nil
    exit(2)
  packed = i64[3*32*16384]
  meta = i64[4]
  rank = ffpk_parse(raw, packed, 3*32*16384, meta, 4) ## i64
  if rank < 1
    exit(2)
  identity = Crypto:SHA256.hexdigest(raw)
  if !File.mkdir_p(root + "/composition/objects")
    exit(2)
  if ffrf_atomic(root + "/composition/objects/" + identity + ".tensor", raw, "test") != 1
    exit(2)
  z = ffwf_publish(root, identity, raw, rank, meta[0], meta[1], meta[2]) ## i64
  << "PUBLISH " + z.to_s()
  if z != 1
    exit(1)
  exit(0)
if ARGV.size() == 2 && ARGV[0] == "--recover"
  if ffwf_recover(ARGV[1] + "/composition/feedback/") != 1
    exit(1)
  exit(0)
if ARGV.size() == 7 && (ARGV[0] == "--take" || ARGV[0] == "--take-stopped")
  root = ARGV[1]
  n = ffpk_decimal(ARGV[2]) ## i64
  m = ffpk_decimal(ARGV[3]) ## i64
  p = ffpk_decimal(ARGV[4]) ## i64
  cap = ffpk_decimal(ARGV[5]) ## i64
  calls = ffpk_decimal(ARGV[6]) ## i64
  if cap < 1 || cap > 4096 || calls < 1 || calls > 20
    exit(2)
  queue = MetaflipRefinement.new(root, System.executable_path())
  if ARGV[0] == "--take-stopped"
    stopped = queue.stop() ## i64
  state = i64[ffw_state_size(cap)]
  count = 0 ## i64
  while count < calls
    result = queue.take_into(state, n, m, p, cap, 17+count, 8, 3, 1000, 2000) ## i64
    << "TAKE " + result.to_s() + " " + queue.last_kind() + " " + queue.last_identity()
    if result > 0
      checked = 0 ## i64
      if n == m && m == p
        checked = ffw_verify_best_exact(state, n)
      else
        checked = ffr_verify_best_exact(state, n, m, p)
      if checked != 1
        exit(1)
    if result < 0
      << queue.status_fields()
      exit(1)
    count += 1
    if count < calls
      ccall("__w_sleep", ~0.260)
  << queue.status_fields()
  exit(0)
if ARGV.size() != 0
  exit(2)

source = i64[6]
out = i64[3]
source[0] = 1
source[2] = 1
source[4] = 1
out[0] = 999
if ffwf_unpack(source, 6, 1, 1, 1, 63, out, 2, 1) != 0 || out[0] != 999
  exit(1)
if ffwf_unpack(source, 6, 1, 1, 1, 64, out, 3, 1) != 0 || out[0] != 999
  exit(1)
source[3] = 1 << 30
source[5] = 1 << 30
if ffwf_unpack(source, 6, 1, 1, 1, 63, out, 3, 1) != 1 || out[1] != 1+(1 << 62) || out[2] != 1+(1 << 62)
  exit(1)
if ffwf_valid_record("MFW_FEED1 invalid invalid 1 1 1 1\n") != 0
  exit(1)
<< "PASS wide feedback: strict format and nonmutating 63-bit conversion gates"
