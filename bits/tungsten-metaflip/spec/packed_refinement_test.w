use ../lib/metaflip/wide/refinement

av = argv()
if av.size() == 3 && av[0] == "--compose-batch"
  exit(ffbc_drain(av[1],ffpk_decimal(av[2])))
if av.size() < 3
  exit(2)
root = av[1]
if av[0] == "--schedule"
  exit(1-ffxt_packed_intake(root))
data = i64[3*32*16384]
meta = i64[4]
parity = i64[32768]
if av[0] == "--take"
  n = ffpk_decimal(av[2]) ## i64
  state_root = ""
  if av.size() == 4
    state_root = av[3]
  R = MetaflipPackedRefinement.new(root,System.executable_path(),state_root)
  rank = R.take_into(data,data.size(),n,parity) ## i64
  << "PACKED_TAKE rank=" + rank.to_s() + R.status_fields()
  exit(0)
raw = File.read_prefix(av[2],12632129)
if raw == nil
  exit(2)
rank = ffpk_parse(raw,data,data.size(),meta,4) ## i64
if rank < 1
  exit(2)
R = MetaflipPackedRefinement.new(root,System.executable_path(),"")
if av[0] == "--submit"
  if R.submit(data,data.size(),rank,meta[0],meta[1],meta[2]) != 1
    exit(1)
  z = R.counters()
  << "PACKED_SUBMIT" + R.status_fields()
  exit(0)
if av[0] == "--publish"
  if ffpk_exact(data,data.size(),rank,meta[0],meta[1],meta[2],parity,parity.size(),20000000) != 1
    exit(1)
  identity = Crypto:SHA256.hexdigest(raw)
  if ffwc_index_kind(root,identity,raw,rank,meta[0],meta[1],meta[2],identity,"MFW_TEST1") != 1 || ffwf_publish(root,identity,raw,rank,meta[0],meta[1],meta[2]) != 1
    exit(1)
  << "PACKED_PUBLISH " + identity
  exit(0)
exit(2)
Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!
