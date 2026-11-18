# Bounded directed search for packed multiword tensors. Private per-worker
# state: a legal-bucket index and two 63-bit term-order-independent hashes.
# History is a bounded direct-mapped heuristic, NOT an exact visited set.
# Hash collisions can reject a valid neighbor; the full tensor gate, never
# these hashes, decides correctness. Like the baseline, density is archival
# only: no density filter or density-driven history aspiration.
use scheme

# Header: mode,hc,active,history-cap,h1,h2,prev1,prev2,prev-valid,
# legal,inverse-blocked,history-blocked,cache-misses,cache-hits,
# rank-rejects,rank-aspirations,no-edge,escapes,history-resets,stalled.
# Offsets 24..31: active IDs, reverse positions, pair witness, history hashes/
# used, then two term-fingerprint caches indexed by stable live slot.
# Dirty bucket IDs are kept in header 32..43; length is header[23].
# Header 44/45 is scratch for the fused fingerprint calculation.
# Word 53 requests an index refresh; 54/55 hold a selected legal pair. In
# legal-pair mode the witness table holds each bucket's unordered pair count.
# Policy words 46..52 (ffwd_init installs the campaign values; ffwd_policy and
# ffwd_watch change them): split period, stall threshold, split on no legal
# pair, split slack over the best rank, target rank, report threshold and
# proposal mode (0 directed legal buckets, 1 uniform term/position, 2 uniform legal pair).
-> ffwd_words(st, history) (i64[] i64) i64
  64+9*(st[3]+1)+3*history+2*st[2]

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

# Preserve both legacy hashes exactly, but load/validate each limb once.
-> ffwd_term_pair(data, at, stride, c) (i64[] i64 i64 i64[]) i64
  h1=2166136261 ## i64
  h2=7809847782465536322 ## i64
  axis=0 ## i64
  while axis<3
    nonzero=0 ## i64
    i=0 ## i64
    while i<stride
      v=data[at+axis*stride+i] ## i64
      nonzero=nonzero | v
      h1=((h1 ^ v)*6364136223846793005+1442695040888963407) & 9223372036854775807
      h2=((h2 ^ v)*6364136223846793005+1442695040888963407) & 9223372036854775807
      h1=h1 ^ (h1 >> 29)
      h2=h2 ^ (h2 >> 29)
      i+=1
    if nonzero==0
      c[44]=0
      c[45]=0
      return 1
    axis+=1
  c[44]=h1
  c[45]=h2
  1

# A toggle either inserts one slot, removes one slot, or ignores a zero
# factor. Only insertion needs a cache write; inactive slots may be stale.
# This wrapper also handles cancellations against a third live term and
# rollback insertions, not just the two original proposal slots.
-> ffwd_toggle(st, data, at, c, h1, h2) (i64[] i64[] i64 i64[] i64 i64) i64
  free=st[12] ## i64
  result=ffws_toggle(st,data,at) ## i64
  if result==1 && st[12]==free-1
    slot=st[st[16]+st[4]-1] ## i64
    c[c[30]+slot]=h1
    c[c[31]+slot]=h2
  result

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

# Enumerate unordered equal-factor pairs in a single hash chain. A negative
# ordinal counts all pairs. Otherwise store its two live slots in c[54..55].
-> ffwd_bucket_pairs(st, c, id, ordinal) (i64[] i64[] i64 i64) i64
  axis=id / c[1] ## i64
  links=st[20]+axis*st[2] ## i64
  hashes=st[22]+axis*st[2] ## i64
  stride=st[1] ## i64
  base=st[14]+axis*stride ## i64
  count=0 ## i64
  a=st[st[19]+id]-1 ## i64
  while a>=0
    b=st[links+a]-1 ## i64
    while b>=0
      if st[hashes+a]==st[hashes+b] && ffws_equal(st,base+3*a*stride,st,base+3*b*stride,stride)==1
        if count==ordinal
          c[54]=a
          c[55]=b
          return count
        count+=1
      b=st[links+b]-1
    a=st[links+a]-1
  count

# Refresh only buckets touched by a transaction. A witness is an actual
# equal-factor pair, not a hash collision. The index never selects a singleton.
-> ffwd_refresh(st, c, id) (i64[] i64[] i64) i64
  cap=st[2] ## i64
  axis=id / c[1] ## i64
  head=st[st[19]+id] ## i64
  witness=0-1 ## i64
  a=head ## i64
  if c[52]==2
    count=ffwd_bucket_pairs(st,c,id,-1) ## i64
    if count>0
      witness=count
    a=0
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
  c[46]=2000
  c[47]=256
  c[48]=1
  c[49]=8
  c[24]=64
  c[25]=c[24]+3*c[1]
  c[26]=c[25]+3*c[1]
  c[27]=c[26]+3*c[1]
  c[28]=c[27]+history
  c[29]=c[28]+history
  c[30]=c[29]+history
  c[31]=c[30]+st[2]
  i=0
  while i<3*c[1]
    c[c[25]+i]=0-1
    i+=1
  i=0
  while i<3*c[1]
    z=ffwd_refresh(st,c,i) ## i64
    i+=1
  i=0
  while i<st[4]
    slot=st[st[16]+i] ## i64
    z=ffwd_term_pair(st,st[14]+slot*3*st[1],st[1],c) ## i64
    c[c[30]+slot]=c[44]
    c[c[31]+slot]=c[45]
    c[4]=c[4] ^ c[44]
    c[5]=c[5] ^ c[45]
    i+=1
  z=ffwd_remember(c) ## i64
  1

# A split is an escape, not a rank improvement. Reset the immediate-inverse
# guard, retaining older history; the next proposal must normally leave it.
-> ffwd_split(st, scratch, c) (i64[] i64[] i64[]) i64
  if st[4]>=st[5]+c[49] || st[12]<1
    return 0
  stride=st[1] ## i64
  slot=st[st[16]+((ffws_rand(st)*st[4]) >> 31)] ## i64
  axis=(ffws_rand(st)*3) >> 31 ## i64
  bit=(ffws_rand(st)*st[24+axis]) >> 31 ## i64
  c[23]=0
  z=ffwd_touch(c,st,st[14]+slot*3*stride,stride) ## i64
  h1=c[4] ^ c[c[30]+slot] ## i64
  h2=c[5] ^ c[c[31]+slot] ## i64
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
  z=ffwd_term_pair(scratch,0,stride,c)
  new11=c[44] ## i64
  new12=c[45] ## i64
  z=ffwd_term_pair(scratch,3*stride,stride,c)
  new21=c[44] ## i64
  new22=c[45] ## i64
  z=ffws_remove(st,slot)
  z=ffwd_toggle(st,scratch,0,c,new11,new12)
  z=ffwd_toggle(st,scratch,3*stride,c,new21,new22)
  c[4]=h1 ^ new11 ^ new21
  c[5]=h2 ^ new12 ^ new22
  c[8]=0
  c[17]+=1
  z=ffwd_remember(c)
  z=ffwd_refresh_dirty(st,c)
  z=ffws_adopt(st)
  1

# A proposal void of any flip: no legal pair, or a uniform draw without a partner.
-> ffwd_void(st, c) (i64[] i64[]) i64
  c[16]+=1
  st[23]+=1
  st[9]+=1
  0

# One proposal: pick two live terms that share a factor, flip them, and keep or
# roll back the result. Directed proposals draw a uniform legal bucket, a random
# member, then a uniform equal-factor partner; this deliberately changes the
# sampling distribution, but not legal moves. Uniform proposals (c[52]=1) draw
# term, position and partner as the packed fleet walker does; a draw without a
# partner is a void proposal, not a rejection.
-> ffwd_one(st, scratch, c, slack) (i64[] i64[] i64[] i64) i64
  st[7]+=1
  stride=st[1] ## i64
  first=0 ## i64
  second=0 ## i64
  axis=0 ## i64
  # The active IDs are identical under either policy. Rebuild their payloads
  # on a policy change; subsequent transactions update only dirty buckets.
  if c[53]!=0
    idx=0 ## i64
    while idx<c[2]
      ffwd_refresh(st,c,c[c[24]+idx])
      idx+=1
    c[53]=0
  if c[52]==0
    if c[2]==0
      return ffwd_void(st,c)
    id=c[c[24]+((ffws_rand(st)*c[2]) >> 31)] ## i64
    axis=id / c[1]
    cap=st[2] ## i64
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
    first=item-1
    word=ffws_rand(st) ## i64
    second=ffws_partner(st,first,axis,word)
    if second<0
      first=c[c[26]+id]
      second=ffws_partner(st,first,axis,word)
    if second<0
      return 0-1
  elsif c[52]==2
    if c[2]==0
      return ffwd_void(st,c)
    total=0 ## i64
    idx=0 ## i64
    while idx<c[2]
      total+=c[c[26]+c[c[24]+idx]]
      idx+=1
    # Each pair has two orientations. The rank cap bounds this below 2^31.
    span=2*total ## i64
    limit=2147483648-(2147483648 % span) ## i64
    word=ffws_rand(st) ## i64
    while word>=limit
      word=ffws_rand(st)
    draw=word % span ## i64
    ordinal=draw / 2 ## i64
    idx=0
    id=c[c[24]] ## i64
    while ordinal>=c[c[26]+id]
      ordinal-=c[c[26]+id]
      idx+=1
      id=c[c[24]+idx]
    axis=id / c[1]
    ffwd_bucket_pairs(st,c,id,ordinal)
    first=c[54+(draw & 1)]
    second=c[55-(draw & 1)]
  else
    if st[4]<2
      return ffwd_void(st,c)
    first=st[st[16]+((ffws_rand(st)*st[4]) >> 31)]
    axis=(ffws_rand(st)*3) >> 31
    second=ffws_partner(st,first,axis,ffws_rand(st))
    if second<0
      return ffwd_void(st,c)
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
  old11=c[c[30]+first] ## i64
  old12=c[c[31]+first] ## i64
  old21=c[c[30]+second] ## i64
  old22=c[c[31]+second] ## i64
  i=0
  while i<4
    z=ffwd_touch(c,scratch,i*3*stride,stride) ## i64
    i+=1
  z=ffwd_term_pair(scratch,6*stride,stride,c) ## i64
  new11=c[44] ## i64
  new12=c[45] ## i64
  z=ffwd_term_pair(scratch,9*stride,stride,c)
  new21=c[44] ## i64
  new22=c[45] ## i64
  h1=c[4] ^ old11 ^ old21 ^ new11 ^ new21 ## i64
  h2=c[5] ^ old12 ^ old22 ^ new12 ^ new22 ## i64
  old_rank=st[4] ## i64
  z=ffws_remove(st,first) ## i64
  z=ffws_remove(st,second)
  z=ffwd_toggle(st,scratch,6*stride,c,new11,new12)
  z=ffwd_toggle(st,scratch,9*stride,c,new21,new22)
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
  z=ffwd_toggle(st,scratch,6*stride,c,new11,new12)
  z=ffwd_toggle(st,scratch,9*stride,c,new21,new22)
  z=ffwd_toggle(st,scratch,0,c,old11,old12)
  z=ffwd_toggle(st,scratch,3*stride,c,old21,old22)
  z=ffwd_refresh_dirty(st,c)
  st[9]+=1
  c[19]+=1
  0

# Ablation switches of the walk, all installed by ffwd_init with the campaign
# values: a split every `period` proposals (0: never), on a stall of `stall`
# consecutive rejections (0: never; the history is forgotten too) and when no
# legal pair exists (`no_pair`), never above best+`slack`; `proposal` 0 samples
# legal buckets, 1 draws by term and position, 2 draws by oriented legal pair.
-> ffwd_policy(c, period, stall, no_pair, slack, proposal) (i64[] i64 i64 i64 i64 i64) i64
  if period<0 || stall<0 || slack<0 || (no_pair!=0 && no_pair!=1) || (proposal<0 || proposal>2)
    return 0
  c[46]=period
  c[47]=stall
  c[48]=no_pair
  c[49]=slack
  if proposal!=c[52] && (proposal==2 || c[52]==2)
    c[53]=1
  c[52]=proposal
  1

# ffwd_work returns early once the best rank is <= target, and once it is
# strictly below report, so a caller can log every new best rank as it happens.
# Zero disables either condition.
-> ffwd_watch(c, target, report) (i64[] i64 i64) i64
  c[50]=target
  c[51]=report
  1

-> ffwd_work(st, scratch, c, steps, stop, slack) (i64[] i64[] i64[] i64 i64[] i64) i64
  never=1099511627776 ## i64
  period=c[46] ## i64
  next_split=never ## i64
  if period>0
    span=st[7]+period-1 ## i64
    next_split=span / period * period
    if next_split==0
      next_split=period
  stall=c[47] ## i64
  if stall==0
    stall=never
  no_pair=0-1 ## i64
  if c[48]!=0
    no_pair=0
  floor_rank=c[50] ## i64
  if c[51]-1>floor_rank
    floor_rank=c[51]-1
  i=0 ## i64
  while i<steps
    if (i & 63)==0 && stop[0]!=0
      break
    if c[2]==no_pair || st[7]==next_split || c[19]>=stall
      z=ffwd_split(st,scratch,c) ## i64
      if st[7]==next_split
        next_split+=period
      if c[19]>=stall
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
    if st[5]<=floor_rank
      break
  st[5]
