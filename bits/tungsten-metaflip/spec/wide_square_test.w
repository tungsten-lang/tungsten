use ../lib/metaflip/wide/seeds

-> wide_consistent(st) (i64[]) i64
  cap = st[2] ## i64
  stride = st[1] ## i64
  if st[4] + st[12] != cap
    return 0
  density = 0 ## i64
  t = 0 ## i64
  while t < st[4]
    slot = st[st[16]+t] ## i64
    if slot < 0 || slot >= cap || st[st[17]+slot] != t
      return 0
    axis = 0 ## i64
    while axis < 3
      h = ffws_hash(st,st[14]+(3*slot+axis)*stride,stride) ## i64
      if st[st[22]+axis*cap+slot] != h
        return 0
      axis += 1
    i = 0 ## i64
    while i < 3*stride
      density += popcount(st[st[14]+3*slot*stride+i])
      i += 1
    t += 1
  if density != st[10]
    return 0
  axis = 0 ## i64
  while axis < 3
    seen = i64[cap]
    count = 0 ## i64
    bucket = 0 ## i64
    while bucket <= st[3]
      c = st[st[19]+axis*(st[3]+1)+bucket] ## i64
      previous = 0 ## i64
      while c != 0
        slot = c-1 ## i64
        if slot < 0 || slot >= cap || seen[slot] != 0 || st[st[17]+slot] < 0
          return 0
        if st[st[21]+axis*cap+slot] != previous || (st[st[22]+axis*cap+slot] & st[3]) != bucket
          return 0
        seen[slot] = 1
        count += 1
        previous = c
        c = st[st[20]+axis*cap+slot]
      bucket += 1
    if count != st[4]
      return 0
    axis += 1
  1

root = __DIR__ + "/../lib/metaflip"
n = 8 ## i64
while n <= 16
  stride = ffpk_stride(n,n,n) ## i64
  words = 8192*3*stride ## i64
  seed = i64[words]
  rank = ffws_seed(seed,n,root,0) ## i64
  parity = i64[n*n*stride]
  if rank < 1 || rank >= n*n*n || ffpk_exact(seed,words,rank,n,n,n,parity,n*n*stride,0) != 1
    << "FAIL wide seed " + n.to_s()
    exit(1)
  cap = rank+64 ## i64
  st = i64[ffws_words(n,cap)]
  if ffws_init(st,n,cap,seed,rank,19071) != 1
    exit(1)
  scratch = i64[12*stride]
  stop = i64[1]
  batch = 0 ## i64
  while batch < 10
    z = ffws_work(st,scratch,4100,stop,8) ## i64
    if wide_consistent(st) != 1
      << "FAIL wide hash/live/density invariants " + n.to_s()
      exit(1)
    batch += 1
  current = ffws_export(st,seed,0) ## i64
  if ffpk_exact(seed,words,current,n,n,n,parity,n*n*stride,0) != 1
    << "FAIL wide current " + n.to_s()
    exit(1)
  best = ffws_export(st,seed,1) ## i64
  if ffpk_exact(seed,words,best,n,n,n,parity,n*n*stride,0) != 1 || best > rank || st[7] != 41000
    << "FAIL wide best " + n.to_s()
    exit(1)
  stop[0]=1
  z = ffws_work(st,scratch,1000,stop,8)
  if st[7] != 41000
    exit(1)
  z = ffpk_canonicalize(seed,words,best,stride)
  blob = ffpk_blob(seed,best,n,n,n)
  parsed = i64[words]
  meta = i64[4]
  if ffpk_parse(blob,parsed,words,meta,4) != best || ffws_equal(seed,0,parsed,0,best*3*stride) != 1
    exit(1)
  << "PASS wide square n=" + n.to_s() + " seed=" + rank.to_s() + " current=" + current.to_s() + " best=" + best.to_s() + " accepted=" + st[8].to_s()
  n += 1
Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!
