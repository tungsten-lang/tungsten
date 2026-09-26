use ../lib/metaflip/composition/transform_queue
Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

if ARGV.size() == 4 && ARGV[0] == "--task"
  root = ARGV[1]
  identity = ARGV[2]
  blob = File.read_prefix(root + "/composition/objects/" + identity + ".tensor",12632129)
  source = i64[3*32*8000]
  meta = i64[4]
  parity = i64[32768]
  if blob == nil || Crypto:SHA256.hexdigest(blob) != identity
    exit(1)
  rank = ffpk_parse(blob,source,source.size(),meta,meta.size()) ## i64
  if rank < 1 || ffpk_exact(source,source.size(),rank,meta[0],meta[1],meta[2],parity,parity.size(),20000000) != 1 || !File.mkdir_p(root + "/composition/best") || !File.mkdir_p(root + "/composition/by-shape") || ffwc_index_kind(root,identity,blob,rank,meta[0],meta[1],meta[2],identity,"TEST") != 1 || ffxt_offer(root,identity,3136) != 1
    exit(1)
  index = ffbq_read(root + "/composition/transforms/index/" + identity + "/","closure",1)
  if index == nil || ffxt_task(root,ffpk_decimal(index.strip())) != 1
    exit(1)
  result = ffbq_read(root + "/composition/transforms/","results",ffpk_decimal(index.strip()))
  if result == nil
    exit(1)
  f = result.strip().split(" ")
  if f.size() != 11 || ffrf_hash_valid(f[2]) != 1
    exit(1)
  output = File.read_prefix(root + "/composition/objects/" + f[2] + ".tensor",12632129)
  if output == nil || !write_file(ARGV[3],output)
    exit(1)
  << result.strip()
  exit(0)

if ARGV.size() == 3 && ARGV[0] == "--catalog"
  exit(1-ffcl_catalog(ARGV[1],ARGV[2]))

if ARGV.size() == 3 && ARGV[0] == "--register"
  blob = File.read_prefix(ARGV[2],12632129)
  out = i64[3*32*8000]
  meta = i64[4]
  parity = i64[32768]
  if blob == nil
    exit(1)
  rank = ffpk_parse(blob,out,out.size(),meta,meta.size()) ## i64
  if rank < 1 || ffpk_exact(out,out.size(),rank,meta[0],meta[1],meta[2],parity,parity.size(),20000000) != 1
    exit(1)
  identity = Crypto:SHA256.hexdigest(blob)
  if !File.mkdir_p(ARGV[1] + "/composition/objects") || ffrf_atomic(ARGV[1] + "/composition/objects/" + identity + ".tensor",blob,"test") != 1
    exit(1)
  exit(1-ffcl_register(ARGV[1],identity,rank,meta[0],meta[1],meta[2]))

if ARGV.size() == 8 && ARGV[0] == "--plan"
  n = ffpk_decimal(ARGV[3]) ## i64
  m = ffpk_decimal(ARGV[4]) ## i64
  p = ffpk_decimal(ARGV[5]) ## i64
  before = ffpk_decimal(ARGV[6]) ## i64
  plan = ffcl_plan(ARGV[1],ARGV[2],n,m,p,before)
  out = i64[3*32*8000]
  meta = i64[4]
  parity = i64[32768]
  rank = ffcl_replay(ARGV[1],ARGV[2],plan,out,meta) ## i64
  if rank < 1 || ffpk_exact(out,out.size(),rank,meta[0],meta[1],meta[2],parity,parity.size(),20000000) != 1 || !write_file(ARGV[7],ffpk_blob(out,rank,n,m,p))
    exit(1)
  << "CLOSURE_RESULT rank=" + rank.to_s()
  exit(0)

if ARGV.size() == 5 && ARGV[0] == "--replay"
  plan = File.read_prefix(ARGV[3],1048577)
  out = i64[3*32*8000]
  meta = i64[4]
  parity = i64[32768]
  if plan == nil
    exit(1)
  rank = ffcl_replay(ARGV[1],ARGV[2],plan,out,meta) ## i64
  if rank < 1 || ffpk_exact(out,out.size(),rank,meta[0],meta[1],meta[2],parity,parity.size(),20000000) != 1 || !write_file(ARGV[4],ffpk_blob(out,rank,meta[0],meta[1],meta[2]))
    exit(1)
  exit(0)

if (ARGV.size() == 5 || ARGV.size() == 6) && ARGV[0] == "--binary"
  left = i64[3*32*8000]
  right = i64[3*32*8000]
  out = i64[3*32*16384]
  lm = i64[4]
  rm = i64[4]
  meta = i64[4]
  work = i64[1]
  parity = i64[32768]
  lb = File.read_prefix(ARGV[1],12632129)
  rb = File.read_prefix(ARGV[2],12632129)
  if lb == nil || rb == nil
    exit(1)
  lr = ffpk_parse(lb,left,left.size(),lm,lm.size()) ## i64
  rr = ffpk_parse(rb,right,right.size(),rm,rm.size()) ## i64
  if lr < 1 || rr < 1 || ffpk_exact(left,left.size(),lr,lm[0],lm[1],lm[2],parity,parity.size(),20000000) != 1 || ffpk_exact(right,right.size(),rr,rm[0],rm[1],rm[2],parity,parity.size(),20000000) != 1
    exit(1)
  budget = 20000000 ## i64
  if ARGV.size() == 6
    budget = ffpk_decimal(ARGV[5])
  rank = ffck_binary(left,lr,lm[0],lm[1],lm[2],right,rr,rm[0],rm[1],rm[2],ffpk_decimal(ARGV[3]),out,meta,work,budget) ## i64
  if rank < 1 || ffpk_exact(out,out.size(),rank,meta[0],meta[1],meta[2],parity,parity.size(),20000000) != 1 || !write_file(ARGV[4],ffpk_blob(out,rank,meta[0],meta[1],meta[2]))
    exit(1)
  exit(0)

<< "wide closure: expected --catalog/--register/--plan/--replay/--binary"
exit(2)
