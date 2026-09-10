use ../lib/metaflip/composition/transform_queue

if ARGV.size() == 1 && ARGV[0] == "--turn-self-test"
  if ffxt_turn(0, 10, 2) != 0 || ffxt_turn(1, 10, 0) != 0 || ffxt_turn(1, 10, 1) != 0 || ffxt_turn(1, 10, 2) != 1 || ffxt_turn(1, 0, 0) != 1 || ffxt_turn(256, 10, 0) != 1 || ffxt_turn(255, 10, 0) != 0
    exit(1)
  exit(0)

if ARGV.size() == 3 && ARGV[0] == "--drain"
  exit(ffxt_drain(ARGV[1], ffpk_decimal(ARGV[2])))
if ARGV.size() == 4 && ARGV[0] == "--offer-task"
  result = ffxt_offer(ARGV[1], ARGV[2], ffpk_decimal(ARGV[3])) ## i64
  if result != 1
    exit(1)
  exit(0)
if ARGV.size() == 3 && ARGV[0] == "--task"
  result = ffxt_task(ARGV[1], ffpk_decimal(ARGV[2])) ## i64
  if result != 1
    exit(1)
  exit(0)
if ARGV.size() == 3 && ARGV[0] == "--offer-file"
  root = ARGV[1]
  raw = File.read_prefix(ARGV[2], 12632129)
  if raw == nil || File.exists?(root + "/stop")
    exit(1)
  out = i64[3*32*16384]
  meta = i64[4]
  parity = i64[32768]
  rank = ffpk_parse(raw, out, 3*32*16384, meta, 4) ## i64
  if rank < 1 || ffpk_exact(out, 3*32*16384, rank, meta[0], meta[1], meta[2], parity, 32768, 20000000) != 1
    exit(1)
  names = ["objects", "best", "by-shape"]
  i = 0 ## i64
  while i < names.size()
    if !File.mkdir_p(root + "/composition/" + names[i])
      exit(1)
    i += 1
  identity = Crypto:SHA256.hexdigest(raw)
  if ffwc_index_kind(root, identity, raw, rank, meta[0], meta[1], meta[2], identity, "MFW_TEST1") != 1 || ffxt_offer(root, identity, 0) != 1
    exit(1)
  if ffxt_coordinates(meta[0], meta[1], meta[2]) > 0 && ffxt_offer(root, identity, 18) != 1
    exit(1)
  << "WIDE_OFFER " + identity
  exit(0)
exit(2)
