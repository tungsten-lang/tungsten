# Build exact large seeds from bundled small square tensors. Kronecker
# products may be projected down by deleting matrix rows/columns together;
# this is an exact sub-tensor restriction, not a claimed best-known rank.
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

-> ffws_seed(out, n, root, naive) (i64[] i64 String i64) i64
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
    if ffw_load_scheme_cap(st,root+"/"+ffp_seed_path(a),a,cap,1,0,1,1,1) < 1
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
