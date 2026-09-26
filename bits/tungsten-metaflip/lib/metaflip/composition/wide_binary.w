# Native block sums and arbitrary multiword Kronecker products over GF(2).
# Inputs/output must be distinct slabs. Construction is not verification;
# callers must full-check every input and result before archive admission.
use packed

-> ffck_shape(n, m, p) (i64 i64 i64) i64
  if n < 1 || m < 1 || p < 1 || n > 32 || m > 32 || p > 32
    return 0
  ffpk_stride(n,m,p)

-> ffck_naive(out, n, m, p) (i64[] i64 i64 i64) i64
  stride = ffck_shape(n,m,p) ## i64
  rank = n*m*p ## i64
  if stride == 0 || rank > 16384 || out.size() < 3*stride*rank
    return 0
  i = 0 ## i64
  while i < 3*stride*rank
    out[i] = 0
    i += 1
  t = 0 ## i64
  i = 0
  while i < n
    j = 0 ## i64
    while j < m
      k = 0 ## i64
      while k < p
        a = i*m+j ## i64
        b = j*p+k ## i64
        c = i*p+k ## i64
        out[3*t*stride+a/32] = 1 << (a%32)
        out[(3*t+1)*stride+b/32] = 1 << (b%32)
        out[(3*t+2)*stride+c/32] = 1 << (c%32)
        t += 1
        k += 1
      j += 1
    i += 1
  rank

-> ffck_embed(source, rank, n, m, p, target, offsets, out, first, work, budget) (i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64 i64[] i64) i64
  stride = ffpk_stride(n,m,p) ## i64
  wide = ffpk_stride(target[0],target[1],target[2]) ## i64
  columns = i64[3]
  columns[0] = m
  columns[1] = p
  columns[2] = p
  rows = i64[3]
  rows[1] = 1
  cols = i64[3]
  cols[0] = 1
  cols[1] = 2
  cols[2] = 2
  t = 0 ## i64
  while t < rank
    axis = 0 ## i64
    while axis < 3
      limb = 0 ## i64
      width = columns[axis] ## i64
      while limb < stride
        word = source[(3*t+axis)*stride+limb] ## i64
        while word != 0
          bit = 32*limb+ffpk_ctz(word) ## i64
          translated = (bit / width+offsets[rows[axis]])*target[cols[axis]]+bit%width+offsets[cols[axis]] ## i64
          work[0] += 1
          if work[0] > budget
            return 0-1
          out[(3*(first+t)+axis)*wide+translated/32] = out[(3*(first+t)+axis)*wide+translated/32] ^ (1 << (translated%32))
          word = word & (word-1)
        limb += 1
      axis += 1
    t += 1
  1

# kind 0/1/2 splits that dimension; kind 3 is a componentwise product.
# -1 is a bounded-work exhaustion, never a partially admitted tensor.
-> ffck_binary(left, lr, ln, lm, lp, right, rr, rn, rm, rp, kind, out, meta, work, budget) (i64[] i64 i64 i64 i64 i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64) i64
  ls = ffck_shape(ln,lm,lp) ## i64
  rs = ffck_shape(rn,rm,rp) ## i64
  if ls == 0 || rs == 0 || kind < 0 || kind > 3 || meta.size() < 4 || work.size() < 1 || budget < 1 || ffpk_valid(left,left.size(),lr,ln,lm,lp) != 1 || ffpk_valid(right,right.size(),rr,rn,rm,rp) != 1
    return 0
  a = i64[3]
  b = i64[3]
  a[0] = ln
  a[1] = lm
  a[2] = lp
  b[0] = rn
  b[1] = rm
  b[2] = rp
  shape = i64[3]
  rank = lr+rr ## i64
  axis = 0 ## i64
  while axis < 3
    if kind == 3
      shape[axis] = a[axis]*b[axis]
    elsif axis == kind
      shape[axis] = a[axis]+b[axis]
    else
      if a[axis] != b[axis]
        return 0
      shape[axis] = a[axis]
    axis += 1
  if kind == 3
    rank = lr*rr
  stride = ffck_shape(shape[0],shape[1],shape[2]) ## i64
  if stride == 0 || rank < 1 || rank > 16384 || out.size() < 3*stride*rank
    return 0
  i = 0 ## i64
  while i < 3*stride*rank
    out[i] = 0
    i += 1
  if kind < 3
    offsets = i64[3]
    if ffck_embed(left,lr,ln,lm,lp,shape,offsets,out,0,work,budget) != 1
      return 0-1
    offsets[kind] = a[kind]
    if ffck_embed(right,rr,rn,rm,rp,shape,offsets,out,lr,work,budget) != 1
      return 0-1
  else
    ac = i64[3]
    bc = i64[3]
    br = i64[3]
    ac[0] = lm
    ac[1] = lp
    ac[2] = lp
    bc[0] = rm
    bc[1] = rp
    bc[2] = rp
    br[0] = rn
    br[1] = rm
    br[2] = rn
    l = 0 ## i64
    while l < lr
      r = 0 ## i64
      while r < rr
        axis = 0
        while axis < 3
          aw = ac[axis] ## i64
          bw = bc[axis] ## i64
          bh = br[axis] ## i64
          x = 0 ## i64
          while x < ls
            word = left[(3*l+axis)*ls+x] ## i64
            while word != 0
              bit = 32*x+ffpk_ctz(word) ## i64
              y = 0 ## i64
              while y < rs
                small = right[(3*r+axis)*rs+y] ## i64
                while small != 0
                  sub = 32*y+ffpk_ctz(small) ## i64
                  translated = (bit / aw*bh+sub / bw)*(aw*bw)+bit%aw*bw+sub%bw ## i64
                  work[0] += 1
                  if work[0] > budget
                    return 0-1
                  out[(3*(l*rr+r)+axis)*stride+translated/32] = out[(3*(l*rr+r)+axis)*stride+translated/32] ^ (1 << (translated%32))
                  small = small & (small-1)
                y += 1
              word = word & (word-1)
            x += 1
          axis += 1
        r += 1
      l += 1
  meta[0] = shape[0]
  meta[1] = shape[1]
  meta[2] = shape[2]
  meta[3] = rank
  ffpk_canonicalize(out,out.size(),rank,stride)
