# Multiword square islands, using the existing 32-bit-limb MFW1 format.
# Stable slots and three factor hash chains keep proposals independent of
# rank. Hash equality only selects a bucket; every factor is compared exactly.
# Header[23] counts attempts with no legal pair. Density only selects the
# saved best at equal rank; it never gates a walk transition.
use ../composition/packed
use ../scheme

-> ffws_words(n, cap) (i64 i64) i64
  32 + 6*ffpk_stride(n,n,n)*cap + 12*cap + 3*ffw_hash_capacity(cap)

-> ffws_hash(data, offset, stride) (i64[] i64 i64) i64
  h = 2166136261 ## i64
  i = 0 ## i64
  while i < stride
    h = ((h ^ data[offset+i])*16777619) & 4294967295
    i += 1
  h ^ (h >> 16)

-> ffws_equal(a, ao, b, bo, count) (i64[] i64 i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if a[ao+i] != b[bo+i]
      return 0
    i += 1
  1

-> ffws_rand(st) (i64[]) i64
  st[6] = (st[6]*6364136223846793005+1442695040888963407) & 9223372036854775807
  (st[6] >> 32) & 2147483647

-> ffws_remove(st, slot) (i64[] i64) i64
  cap = st[2] ## i64
  stride = st[1] ## i64
  axis = 0 ## i64
  while axis < 3
    node = axis*cap+slot ## i64
    nn = st[st[20]+node] ## i64
    pp = st[st[21]+node] ## i64
    if pp == 0
      bucket = st[st[22]+node] & st[3] ## i64
      st[st[19]+axis*(st[3]+1)+bucket] = nn
    else
      st[st[20]+axis*cap+pp-1] = nn
    if nn != 0
      st[st[21]+axis*cap+nn-1] = pp
    axis += 1
  pos = st[st[17]+slot] ## i64
  last = st[st[16]+st[4]-1] ## i64
  st[st[16]+pos] = last
  st[st[17]+last] = pos
  st[st[17]+slot] = 0-1
  st[st[18]+st[12]] = slot
  st[12] += 1
  i = 0 ## i64
  while i < 3*stride
    st[10] -= popcount(st[st[14]+slot*3*stride+i])
    i += 1
  st[4] -= 1
  1

# Toggle in the GF(2) tensor sum, including zero factors and cancellations.
-> ffws_toggle(st, data, offset) (i64[] i64[] i64) i64
  stride = st[1] ## i64
  cap = st[2] ## i64
  axis = 0 ## i64
  while axis < 3
    value = 0 ## i64
    i = 0 ## i64
    while i < stride
      value = value | data[offset+axis*stride+i]
      i += 1
    if value == 0
      return 1
    axis += 1
  h = ffws_hash(data,offset,stride) ## i64
  c = st[st[19]+(h & st[3])] ## i64
  while c != 0
    slot = c-1 ## i64
    if ffws_equal(st,st[14]+slot*3*stride,data,offset,3*stride) == 1
      return ffws_remove(st,slot)
    c = st[st[20]+slot]
  if st[12] <= 0
    return 0
  slot = st[st[18]+st[12]-1] ## i64
  st[12] -= 1
  i = 0 ## i64
  while i < 3*stride
    value = data[offset+i] ## i64
    st[st[14]+slot*3*stride+i] = value
    st[10] += popcount(value)
    i += 1
  axis = 0
  while axis < 3
    h = ffws_hash(data,offset+axis*stride,stride)
    node = axis*cap+slot ## i64
    head = st[19]+axis*(st[3]+1)+(h & st[3]) ## i64
    old = st[head] ## i64
    st[st[20]+node] = old
    st[st[21]+node] = 0
    st[st[22]+node] = h
    if old != 0
      st[st[21]+axis*cap+old-1] = slot+1
    st[head] = slot+1
    axis += 1
  st[st[16]+st[4]] = slot
  st[st[17]+slot] = st[4]
  st[4] += 1
  1

-> ffws_adopt(st) (i64[]) i64
  if st[5] >= 0 && (st[4] > st[5] || (st[4] == st[5] && st[10] >= st[11]))
    return 0
  stride = st[1] ## i64
  t = 0 ## i64
  while t < st[4]
    slot = st[st[16]+t] ## i64
    i = 0 ## i64
    while i < 3*stride
      st[st[15]+t*3*stride+i] = st[st[14]+slot*3*stride+i]
      i += 1
    t += 1
  st[5] = st[4]
  st[11] = st[10]
  1

-> ffws_init(st, n, cap, data, rank, seed) (i64[] i64 i64 i64[] i64 i64) i64
  if n < 8 || n > 16 || rank < 1 || cap < rank+2 || cap > 8192
    return 0
  stride = ffpk_stride(n,n,n) ## i64
  hc = ffw_hash_capacity(cap) ## i64
  words = ffws_words(n,cap) ## i64
  i = 0 ## i64
  while i < words
    st[i] = 0
    i += 1
  st[0]=n
  st[1]=stride
  st[2]=cap
  st[3]=hc-1
  st[5]=0-1
  st[6]=seed & 9223372036854775807
  st[12]=cap
  st[14]=32
  st[15]=st[14]+3*stride*cap
  st[16]=st[15]+3*stride*cap
  st[17]=st[16]+cap
  st[18]=st[17]+cap
  st[19]=st[18]+cap
  st[20]=st[19]+3*hc
  st[21]=st[20]+3*cap
  st[22]=st[21]+3*cap
  i = 0
  while i < cap
    st[st[18]+i]=cap-1-i
    st[st[17]+i]=0-1
    i += 1
  i = 0
  while i < rank
    if ffws_toggle(st,data,i*3*stride) != 1
      return 0
    i += 1
  ffws_adopt(st)

-> ffws_partner(st, first, axis, random_word) (i64[] i64 i64 i64) i64
  stride = st[1] ## i64
  cap = st[2] ## i64
  key = st[st[22]+axis*cap+first] ## i64
  head = st[19]+axis*(st[3]+1)+(key & st[3]) ## i64
  count = 0 ## i64
  pass = 0 ## i64
  want = 0 ## i64
  while pass < 2
    c = st[head] ## i64
    while c != 0
      slot = c-1 ## i64
      if slot != first && st[st[22]+axis*cap+slot] == key
        if ffws_equal(st,st[14]+(slot*3+axis)*stride,st,st[14]+(first*3+axis)*stride,stride) == 1
          if pass == 0
            count += 1
          else
            if want == 0
              return slot
            want -= 1
      c = st[st[20]+axis*cap+slot]
    if count == 0
      return 0-1
    want = (random_word*count) >> 31
    pass += 1
  0-1

# Scratch holds two source terms and two proposed terms. Ordinary pair flips
# preserve the shared factor and XOR the other two, exactly as narrow flips.
# Keep the legacy slack argument for caller compatibility; it is unused.
-> ffws_one(st, scratch, slack) (i64[] i64[] i64) i64
  st[7] += 1
  if st[4] < 2
    st[9] += 1
    st[23] += 1
    return 0
  stride = st[1] ## i64
  first = st[st[16]+((ffws_rand(st)*st[4]) >> 31)] ## i64
  axis = (ffws_rand(st)*3) >> 31 ## i64
  second = ffws_partner(st,first,axis,ffws_rand(st)) ## i64
  if second < 0
    st[9] += 1
    st[23] += 1
    return 0
  i = 0 ## i64
  while i < 3*stride
    scratch[i]=st[st[14]+first*3*stride+i]
    scratch[3*stride+i]=st[st[14]+second*3*stride+i]
    scratch[6*stride+i]=scratch[i]
    scratch[9*stride+i]=scratch[3*stride+i]
    i += 1
  left = (axis+1)%3 ## i64
  right = (axis+2)%3 ## i64
  i = 0
  while i < stride
    scratch[6*stride+right*stride+i]=scratch[right*stride+i] ^ scratch[3*stride+right*stride+i]
    scratch[9*stride+left*stride+i]=scratch[left*stride+i] ^ scratch[3*stride+left*stride+i]
    i += 1
  old_rank = st[4] ## i64
  z = ffws_remove(st,first) ## i64
  z = ffws_remove(st,second)
  z = ffws_toggle(st,scratch,6*stride)
  z = ffws_toggle(st,scratch,9*stride)
  if st[4] <= old_rank
    st[8] += 1
    z = ffws_adopt(st)
    return 1
  z = ffws_toggle(st,scratch,6*stride)
  z = ffws_toggle(st,scratch,9*stride)
  z = ffws_toggle(st,scratch,0)
  z = ffws_toggle(st,scratch,3*stride)
  st[9] += 1
  0

-> ffws_export(st, out, best) (i64[] i64[] i64) i64
  stride = st[1] ## i64
  rank = st[4] ## i64
  if best != 0
    rank = st[5]
  t = 0 ## i64
  while t < rank
    from = st[15]+t*3*stride ## i64
    if best == 0
      from = st[14]+st[st[16]+t]*3*stride
    i = 0 ## i64
    while i < 3*stride
      out[t*3*stride+i]=st[from+i]
      i += 1
    t += 1
  rank

-> ffws_split(st, scratch) (i64[] i64[]) i64
  if st[4] >= st[5]+8 || st[12] < 1
    return 0
  stride = st[1] ## i64
  slot = st[st[16]+((ffws_rand(st)*st[4]) >> 31)] ## i64
  axis = (ffws_rand(st)*3) >> 31 ## i64
  bit = (ffws_rand(st)*st[0]*st[0]) >> 31 ## i64
  i = 0 ## i64
  while i < 3*stride
    value = st[st[14]+slot*3*stride+i] ## i64
    scratch[i]=value
    scratch[3*stride+i]=value
    if i / stride == axis
      scratch[i]=0
      if i%stride == bit/32
        scratch[i]=1 << (bit%32)
      scratch[3*stride+i]=value ^ scratch[i]
    i += 1
  z = ffws_remove(st,slot) ## i64
  z = ffws_toggle(st,scratch,0)
  z = ffws_toggle(st,scratch,3*stride)
  z = ffws_adopt(st)
  1

-> ffws_work(st, scratch, steps, stop, slack) (i64[] i64[] i64 i64[] i64) i64
  i = 0 ## i64
  while i < steps
    if (i & 255) == 0 && stop[0] != 0
      break
    if st[7] > 0 && (st[7]%2000) == 0
      z = ffws_split(st,scratch) ## i64
    z = ffws_one(st,scratch,slack) ## i64
    i += 1
  st[5]
