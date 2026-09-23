use ../lib/metaflip/composition/transform_queue

if ARGV.size() == 4 && ARGV[0] == "--basis-mode"
  mode = ffpk_decimal(ARGV[3]) ## i64
  raw = File.read_prefix(ARGV[1], 12632129)
  if mode < 0 || mode >= 18 || raw == nil
    exit(2)
  source = i64[3*32*16384]
  out = i64[3*32*16384]
  parity = i64[32768]
  info = i64[4]
  meta = i64[5]
  before = ffpk_parse(raw, source, 3*32*16384, info, 4) ## i64
  if before < 1 || ffpk_exact(source, 3*32*16384, before, info[0], info[1], info[2], parity, 32768, 20000000) != 1
    exit(1)
  rank = ffxt_propose(ARGV[1], source, out, before, info[0], info[1], info[2], mode, meta) ## i64
  if rank < 1 || rank > before || ffpk_exact(out, 3*32*16384, rank, info[0], info[1], info[2], parity, 32768, 20000000) != 1 || !write_file(ARGV[2], ffpk_blob(out, rank, info[0], info[1], info[2]))
    exit(1)
  << "BASIS_MODE " + before.to_s() + " " + rank.to_s() + " " + meta[3].to_s() + " " + meta[4].to_s()
  exit(0)

if (ARGV.size() == 2 || ARGV.size() == 3) && ARGV[0] == "--postbasis-scan"
  raw = File.read_prefix(ARGV[1], 12632129)
  if raw == nil
    exit(1)
  source = i64[3*32*16384]
  out = i64[3*32*16384]
  best_data = i64[3*32*16384]
  parity = i64[32768]
  info = i64[4]
  meta = i64[5]
  before = ffpk_parse(raw, source, 3*32*16384, info, 4) ## i64
  if before < 1 || ffpk_exact(source, 3*32*16384, before, info[0], info[1], info[2], parity, 32768, 20000000) != 1
    exit(1)
  best = before ## i64
  mode = 3090 ## i64
  while mode < 3108
    rank = ffxt_propose(ARGV[1], source, out, before, info[0], info[1], info[2], mode, meta) ## i64
    if rank < 1 || rank > before || ffpk_exact(out, 3*32*16384, rank, info[0], info[1], info[2], parity, 32768, 20000000) != 1
      exit(1)
    if rank < best
      best = rank
      if ARGV.size() == 3
        stride = ffpk_stride(info[0], info[1], info[2]) ## i64
        i = 0 ## i64
        while i < 3*stride*rank
          best_data[i] = out[i]
          i += 1
    mode += 1
  if ARGV.size() == 3
    selected = raw
    if best < before
      selected = ffpk_blob(best_data, best, info[0], info[1], info[2])
    if !write_file(ARGV[2], selected)
      exit(1)
  << "POSTBASIS before=" + before.to_s() + " best=" + best.to_s()
  exit(0)

if ARGV.size() == 1 && ARGV[0] == "--turn-self-test"
  if ffxt_turn(0, 10, 2) != 0 || ffxt_turn(1, 10, 0) != 0 || ffxt_turn(1, 10, 1) != 0 || ffxt_turn(1, 10, 2) != 1 || ffxt_turn(1, 0, 0) != 1 || ffxt_turn(256, 10, 0) != 1 || ffxt_turn(255, 10, 0) != 0
    exit(1)
  if ffxt_reproject(3089, 10, 9, 3) != 0 || ffxt_reproject(3090, 10, 9, 3) != 0 || ffxt_reproject(3107, 10, 10, 3) != 0 || ffxt_reproject(3107, 10, 9, 0) != 0 || ffxt_reproject(3107, 10, 9, 3) != 1 || ffxt_reproject(3125, 10, 9, 3) != 1 || ffxt_reproject(3126, 10, 9, 3) != 0
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
if ARGV.size() == 3 && ARGV[0] == "--offer-postbasis-file"
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
  if ffwc_index_kind(root, identity, raw, rank, meta[0], meta[1], meta[2], identity, "MFW_TEST1") != 1 || ffxt_offer(root, identity, 3090) != 1
    exit(1)
  << "WIDE_POSTBASIS_OFFER " + identity
  exit(0)
exit(2)
