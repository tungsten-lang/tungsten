# Bounded directed-search experiment for packed squares. Private per-worker
# state: a legal-bucket index and two 63-bit term-order-independent hashes.
# History is a bounded direct-mapped heuristic, NOT an exact visited set.
# Hash collisions can reject a valid neighbor; the full tensor gate, never
# these hashes, decides correctness. Like the baseline, density is archival
# only: no density filter or density-driven history aspiration.
use scheme

# Header: mode,hc,active,history-cap,h1,h2,prev1,prev2,prev-valid,
# legal,inverse-blocked,history-blocked,cache-misses,cache-hits,
# rank-rejects,rank-aspirations,no-edge,escapes,history-resets,stalled.
# Offsets 24..29: active IDs, reverse positions, pair witness, hash1/hash2/used.
# Dirty bucket IDs are kept in header 32..43; length is header[23].
-> ffwd_words(st, history) (i64[] i64) i64
  64+9*(st[3]+1)+3*history

-> ffwd_term(data, at, stride, salt) (i64[] i64 i64 i64) i64
  axis=0 ## i64
  h=salt ## i64
  while axis<3
    nonzero=0 ## i64
    i=0 ## i64
    while i<stride
      v=data[at+axis*stride+i] ## i64
      nonzero=nonzero | v
      h=((h ^ v)*6364136223846793005+1442695040888963407) & 9223372036854775807
      h=h ^ (h >> 29)
      i+=1
    if nonzero==0
      return 0
    axis+=1
  h

-> ffwd_fingerprint(st, salt) (i64[] i64) i64
  h=0 ## i64
  i=0 ## i64
  while i<st[4]
    slot=st[st[16]+i] ## i64
    h=h ^ ffwd_term(st,st[14]+slot*3*st[1],st[1],salt)
    i+=1
  h

-> ffwd_seen(c, h1, h2) (i64[] i64 i64) i64
  slot=(h1 ^ (h1 >> 31)) & (c[3]-1) ## i64
  if c[c[29]+slot]!=0 && c[c[27]+slot]==h1 && c[c[28]+slot]==h2
    return 1
  0

# Misses are relative to this bounded table, not globally unique states.
-> ffwd_remember(c) (i64[]) i64
  seen=ffwd_seen(c,c[4],c[5]) ## i64
  if seen==1
    c[13]+=1
  else
    c[12]+=1
  slot=(c[4] ^ (c[4] >> 31)) & (c[3]-1) ## i64
  c[c[27]+slot]=c[4]
  c[c[28]+slot]=c[5]
  c[c[29]+slot]=1
  seen

# New rank bests override both heuristic guards. Return the rejection reason.
-> ffwd_guard(c, h1, h2, aspiration) (i64[] i64 i64 i64) i64
  if aspiration!=0 || c[0]<2
    return 0
  if (h1==c[4] && h2==c[5]) || (c[8]!=0 && h1==c[6] && h2==c[7])
    return 1
  if c[0]>=3 && ffwd_seen(c,h1,h2)==1
    return 2
  0

# Refresh only buckets touched by a transaction. A witness is an actual
# equal-factor pair, not a hash collision. The index never selects a singleton.
-> ffwd_refresh(st, c, id) (i64[] i64[] i64) i64
  cap=st[2] ## i64
  axis=id / c[1] ## i64
  head=st[st[19]+id] ## i64
  witness=0-1 ## i64
  a=head ## i64
  while a!=0 && witness<0
    b=st[st[20]+axis*cap+a-1] ## i64
    while b!=0
      if st[st[22]+axis*cap+a-1]==st[st[22]+axis*cap+b-1] && ffws_equal(st,st[14]+((a-1)*3+axis)*st[1],st,st[14]+((b-1)*3+axis)*st[1],st[1])==1
        witness=a-1
        break
      b=st[st[20]+axis*cap+b-1]
    a=st[st[20]+axis*cap+a-1]
  pos=c[c[25]+id] ## i64
  if witness>=0
    c[c[26]+id]=witness
    if pos<0
      c[c[25]+id]=c[2]
      c[c[24]+c[2]]=id
      c[2]+=1
  elsif pos>=0
    c[2]-=1
    last=c[c[24]+c[2]] ## i64
    c[c[24]+pos]=last
    c[c[25]+last]=pos
    c[c[25]+id]=0-1
  1

-> ffwd_touch(c, data, at, stride) (i64[] i64[] i64 i64) i64
  axis=0 ## i64
  while axis<3
    id=axis*c[1]+(ffws_hash(data,at+axis*stride,stride) & (c[1]-1)) ## i64
    found=0 ## i64
    i=0 ## i64
    while i<c[23]
      if c[32+i]==id
        found=1
      i+=1
    if found==0
      c[32+c[23]]=id
      c[23]+=1
    axis+=1
  1

-> ffwd_refresh_dirty(st, c) (i64[] i64[]) i64
  i=0 ## i64
  while i<c[23]
    z=ffwd_refresh(st,c,c[32+i]) ## i64
    i+=1
  c[23]=0
  1

-> ffwd_init(st, c, mode, history) (i64[] i64[] i64 i64) i64
  if mode<1 || mode>3 || history<2 || (history & (history-1))!=0 || c.size()<ffwd_words(st,history)
    return 0
  i=0 ## i64
  while i<c.size()
    c[i]=0
    i+=1
  c[0]=mode
  c[1]=st[3]+1
  c[3]=history
  c[24]=64
  c[25]=c[24]+3*c[1]
  c[26]=c[25]+3*c[1]
  c[27]=c[26]+3*c[1]
  c[28]=c[27]+history
  c[29]=c[28]+history
  i=0
  while i<3*c[1]
    c[c[25]+i]=0-1
    i+=1
  i=0
  while i<3*c[1]
    z=ffwd_refresh(st,c,i) ## i64
    i+=1
  c[4]=ffwd_fingerprint(st,2166136261)
  c[5]=ffwd_fingerprint(st,7809847782465536322)
  z=ffwd_remember(c) ## i64
  1

# A split is an escape, not a rank improvement. Reset the immediate-inverse
# guard, retaining older history; the next proposal must normally leave it.
-> ffwd_split(st, scratch, c) (i64[] i64[] i64[]) i64
  if st[4]>=st[5]+8 || st[12]<1
    return 0
  stride=st[1] ## i64
  slot=st[st[16]+((ffws_rand(st)*st[4]) >> 31)] ## i64
  axis=(ffws_rand(st)*3) >> 31 ## i64
  bit=(ffws_rand(st)*st[0]*st[0]) >> 31 ## i64
  c[23]=0
  z=ffwd_touch(c,st,st[14]+slot*3*stride,stride) ## i64
  h1=c[4] ^ ffwd_term(st,st[14]+slot*3*stride,stride,2166136261) ## i64
  h2=c[5] ^ ffwd_term(st,st[14]+slot*3*stride,stride,7809847782465536322) ## i64
  i=0 ## i64
  while i<3*stride
    v=st[st[14]+slot*3*stride+i] ## i64
    scratch[i]=v
    scratch[3*stride+i]=v
    if i / stride==axis
      scratch[i]=0
      if i%stride==bit / 32
        scratch[i]=1 << (bit%32)
      scratch[3*stride+i]=v ^ scratch[i]
    i+=1
  z=ffwd_touch(c,scratch,0,stride)
  z=ffwd_touch(c,scratch,3*stride,stride)
  z=ffws_remove(st,slot)
  z=ffws_toggle(st,scratch,0)
  z=ffws_toggle(st,scratch,3*stride)
  c[4]=h1 ^ ffwd_term(scratch,0,stride,2166136261) ^ ffwd_term(scratch,3*stride,stride,2166136261)
  c[5]=h2 ^ ffwd_term(scratch,0,stride,7809847782465536322) ^ ffwd_term(scratch,3*stride,stride,7809847782465536322)
  c[8]=0
  c[17]+=1
  z=ffwd_remember(c)
  z=ffwd_refresh_dirty(st,c)
  z=ffws_adopt(st)
  1

-> ffwd_one(st, scratch, c, slack) (i64[] i64[] i64[] i64) i64
  st[7]+=1
  if c[2]==0
    c[16]+=1
    st[23]+=1
    st[9]+=1
    return 0
  id=c[c[24]+((ffws_rand(st)*c[2]) >> 31)] ## i64
  axis=id / c[1] ## i64
  cap=st[2] ## i64
  stride=st[1] ## i64
  # Uniform bucket, random member, then uniform equal-factor partner. This
  # deliberately changes the sampling distribution, but not legal moves.
  count=0 ## i64
  item=st[st[19]+id] ## i64
  while item!=0
    count+=1
    item=st[st[20]+axis*cap+item-1]
  want=(ffws_rand(st)*count) >> 31 ## i64
  item=st[st[19]+id]
  while want>0
    item=st[st[20]+axis*cap+item-1]
    want-=1
  first=item-1 ## i64
  word=ffws_rand(st) ## i64
  second=ffws_partner(st,first,axis,word) ## i64
  if second<0
    first=c[c[26]+id]
    second=ffws_partner(st,first,axis,word)
  if second<0
    return 0-1
  c[9]+=1
  i=0 ## i64
  while i<3*stride
    scratch[i]=st[st[14]+first*3*stride+i]
    scratch[3*stride+i]=st[st[14]+second*3*stride+i]
    scratch[6*stride+i]=scratch[i]
    scratch[9*stride+i]=scratch[3*stride+i]
    i+=1
  left=(axis+1)%3 ## i64
  right=(axis+2)%3 ## i64
  i=0
  while i<stride
    scratch[6*stride+right*stride+i]=scratch[right*stride+i] ^ scratch[3*stride+right*stride+i]
    scratch[9*stride+left*stride+i]=scratch[left*stride+i] ^ scratch[3*stride+left*stride+i]
    i+=1
  c[23]=0
  h1=c[4] ## i64
  h2=c[5] ## i64
  i=0
  while i<4
    z=ffwd_touch(c,scratch,i*3*stride,stride) ## i64
    h1=h1 ^ ffwd_term(scratch,i*3*stride,stride,2166136261)
    h2=h2 ^ ffwd_term(scratch,i*3*stride,stride,7809847782465536322)
    i+=1
  old_rank=st[4] ## i64
  z=ffws_remove(st,first) ## i64
  z=ffws_remove(st,second)
  z=ffws_toggle(st,scratch,6*stride)
  z=ffws_toggle(st,scratch,9*stride)
  accept=0 ## i64
  if st[4]<=old_rank
    accept=1
  else
    c[14]+=1
  aspiration=0 ## i64
  if st[4]<st[5]
    aspiration=1
  if accept==1
    # Save every encountered best before a history rejection can roll back
    # the walk. A lower-density tie does not influence the next walk state.
    z=ffws_adopt(st)
    guard=ffwd_guard(c,h1,h2,aspiration) ## i64
    if guard==1
      c[10]+=1
      accept=0
    elsif guard==2
      c[11]+=1
      accept=0
  if accept==1
    if aspiration==1
      c[15]+=1
    c[6]=c[4]
    c[7]=c[5]
    c[8]=1
    c[4]=h1
    c[5]=h2
    c[19]=0
    st[8]+=1
    z=ffwd_remember(c)
    z=ffwd_refresh_dirty(st,c)
    return 1
  z=ffws_toggle(st,scratch,6*stride)
  z=ffws_toggle(st,scratch,9*stride)
  z=ffws_toggle(st,scratch,0)
  z=ffws_toggle(st,scratch,3*stride)
  z=ffwd_refresh_dirty(st,c)
  st[9]+=1
  c[19]+=1
  0

-> ffwd_work(st, scratch, c, steps, stop, slack) (i64[] i64[] i64[] i64 i64[] i64) i64
  i=0 ## i64
  while i<steps
    if (i & 63)==0 && stop[0]!=0
      break
    if c[2]==0 || (st[7]>0 && st[7]%2000==0) || c[19]>=256
      z=ffwd_split(st,scratch,c) ## i64
      if c[19]>=256
        # Do not strand a walk behind heuristic history. Bounded forgetting
        # restores exploration; repeats are explicitly allowed after reset.
        j=0 ## i64
        while j<c[3]
          c[c[29]+j]=0
          j+=1
        c[8]=0
        c[19]=0
        c[18]+=1
    z=ffwd_one(st,scratch,c,slack) ## i64
    if z<0
      stop[0]=1
      return 0-1
    i+=1
  st[5]
