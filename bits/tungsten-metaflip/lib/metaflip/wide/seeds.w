# Pinned published GF(2) seeds plus exact small-tensor compositions.
use scheme
use ../seeds/catalog

-> ffws_naive(out, n) (i64[] i64) i64
  stride = ffpk_stride(n,n,n) ## i64
  rank = n*n*n ## i64
  i = 0 ## i64
  while i < 3*stride*rank
    out[i]=0
    i += 1
  t = 0 ## i64
  i = 0
  while i < n
    j = 0 ## i64
    while j < n
      k = 0 ## i64
      while k < n
        u = i*n+j ## i64
        v = j*n+k ## i64
        w = i*n+k ## i64
        out[3*t*stride+u/32]=1 << (u%32)
        out[(3*t+1)*stride+v/32]=1 << (v%32)
        out[(3*t+2)*stride+w/32]=1 << (w%32)
        t += 1
        k += 1
      j += 1
    i += 1
  rank

-> ffws_product(out, n, a, b, left, right) (i64[] i64 i64 i64 i64[] i64[]) i64
  stride = ffpk_stride(n,n,n) ## i64
  rank = left[7]*right[7] ## i64
  if rank > 8192
    return 0
  i = 0 ## i64
  while i < 3*stride*rank
    out[i]=0
    i += 1
  t = 0 ## i64
  l = 0 ## i64
  while l < left[7]
    r = 0 ## i64
    while r < right[7]
      axis = 0 ## i64
      while axis < 3
        x = left[left[47+axis]+l] ## i64
        i = 0
        while i < a*a
          if ((x >> i) & 1) != 0
            y = right[right[47+axis]+r] ## i64
            j = 0 ## i64
            while j < b*b
              if ((y >> j) & 1) != 0
                row = (i / a)*b+j / b ## i64
                col = (i%a)*b+j%b ## i64
                if row < n && col < n
                  bit = row*n+col ## i64
                  at = (3*t+axis)*stride+bit/32 ## i64
                  out[at]=out[at] | (1 << (bit%32))
              j += 1
          i += 1
        axis += 1
      t += 1
      r += 1
    l += 1
  ffpk_canonicalize(out,8192*3*stride,rank,stride)

-> ffws_composed_seed(out, n, root, naive, variant) (i64[] i64 String i64 i64) i64
  if n < 8 || n > 16
    return 0
  best = ffws_naive(out,n) ## i64
  if naive != 0
    return ffpk_canonicalize(out,8192*3*ffpk_stride(n,n,n),best,ffpk_stride(n,n,n))
  bank = []
  a = 2 ## i64
  while a <= 7
    cap = ffw_default_capacity(a) ## i64
    st = i64[ffw_state_size(cap)]
    paths = ffp_frontier_seed_paths(a)
    path = ffp_seed_path(a)
    if variant > 0 && paths.size() > 0
      path = paths[variant % paths.size()]
    if ffw_load_scheme_cap(st,root+"/"+path,a,cap,1,0,1,1,1) < 1
      return 0
    bank.push(st)
    a += 1
  stride = ffpk_stride(n,n,n) ## i64
  trial = i64[8192*3*stride]
  a = 2
  while a <= 7
    b = 2 ## i64
    while b <= 7
      if a*b >= n && a*b <= n+2
        rank = ffws_product(trial,n,a,b,bank[a-2],bank[b-2]) ## i64
        if rank > 0 && rank < best
          best = rank
          i = 0 ## i64
          while i < rank*3*stride
            out[i]=trial[i]
            i += 1
      b += 1
    a += 1
  ffpk_canonicalize(out,8192*3*stride,best,stride)

-> ffws_bits(data, count) (i64[] i64) i64
  result = 0 ## i64
  i = 0 ## i64
  while i < count
    result += popcount(data[i])
    i += 1
  result

-> ffws_checked_load(path, data, words, n, parity) (String i64[] i64 i64 i64[]) i64
  raw = File.read_prefix(path,12632129)
  if raw == nil
    return 0
  meta = i64[4]
  rank = ffpk_parse(raw,data,words,meta,4) ## i64
  if rank < 1 || meta[0] != n || meta[1] != n || meta[2] != n
    return 0-1
  if ffpk_exact(data,words,rank,n,n,n,parity,n*n*ffpk_stride(n,n,n),0) != 1
    return 0-1
  rank

-> ffws_packaged_paths(root, n) (String i64)
  paths = []
  text = read_file(root+"/manifests/wide-seeds.tsv")
  if text == nil
    return paths
  lines = text.split("\n")
  i = 1 ## i64
  while i < lines.size()
    if lines[i] != ""
      row = lines[i].split("\t")
      if row.size() != 12 || !row[3].starts_with?("seeds/gf2/wide/") || row[3].include?("..")
        return ["invalid-wide-seed-manifest"]
      if row[0] == n.to_s()
        paths.push(row[3])
    i += 1
  paths

# Public field-compatible reference, audited 2026-09-12. This is not an
# optimality claim; smaller Q-only/commutative catalog ranks are excluded.
-> ffws_reference_rank(n) (i64) i64
  ranks = i64[9]
  ranks[0]=329
  ranks[1]=486
  ranks[2]=651
  ranks[3]=873
  ranks[4]=1068
  ranks[5]=1426
  ranks[6]=1725
  ranks[7]=2058
  ranks[8]=2209
  if n < 8 || n > 16
    return 0
  ranks[n-8]

-> ffws_seed(out, n, root, naive) (i64[] i64 String i64) i64
  best = ffws_composed_seed(out,n,root,naive,0) ## i64
  if naive != 0 || best < 1
    return best
  stride = ffpk_stride(n,n,n) ## i64
  words = 8192*3*stride ## i64
  trial = i64[words]
  parity = i64[n*n*stride]
  paths = ffws_packaged_paths(root,n)
  i = 0 ## i64
  while i < paths.size()
    rank = ffws_checked_load(root+"/"+paths[i],trial,words,n,parity) ## i64
    if rank < 1
      return 0
    if rank < best || (rank == best && ffws_bits(trial,rank*3*stride) < ffws_bits(out,best*3*stride))
      best=rank
      j = 0 ## i64
      while j < rank*3*stride
        out[j]=trial[j]
        j += 1
    i += 1
  best

# Four literal-distinct starts at most, within 5% of the leader. Higher-rank
# published alternatives remain available via --seed, not automatic lanes.
-> ffws_bank_add(bank, ranks, trial, rank, stride, leader)
  if rank < 1 || rank > leader+(leader+19) / 20 || bank.size() >= 4
    return 0
  b = 0 ## i64
  while b < bank.size()
    if ranks[b] == rank
      same = 1 ## i64
      j = 0 ## i64
      existing = bank[b]
      while j < rank*3*stride
        if existing[j] != trial[j]
          same=0
          break
        j += 1
      if same == 1
        return 0
    b += 1
  ranks[bank.size()]=rank
  bank.push(trial)
  1
