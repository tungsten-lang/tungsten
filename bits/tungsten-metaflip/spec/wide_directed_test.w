use ../lib/metaflip/wide/directed
use ../lib/metaflip/wide/seeds

-> directed_consistent(st,c) (i64[] i64[]) i64
  if c[4]!=ffwd_fingerprint(st,2166136261) || c[5]!=ffwd_fingerprint(st,7809847782465536322)
    return 0
  count=0 ## i64
  id=0 ## i64
  while id<3*c[1]
    present=0 ## i64
    axis=id / c[1] ## i64
    item=st[st[19]+id] ## i64
    while item!=0
      if ffws_partner(st,item-1,axis,0)>=0
        present=1
      item=st[st[20]+axis*st[2]+item-1]
    pos=c[c[25]+id] ## i64
    if present==1
      if pos<0 || pos>=c[2] || c[c[24]+pos]!=id
        return 0
      if ffws_partner(st,c[c[26]+id],axis,0)<0
        return 0
      count+=1
    elsif pos>=0
      return 0
    id+=1
  if count!=c[2]
    return 0
  1

root=__DIR__+"/../lib/metaflip"
n=8 ## i64
blocked=0 ## i64
while n<=16
  stride=ffpk_stride(n,n,n) ## i64
  seed=i64[8192*3*stride]
  rank=ffws_seed(seed,n,root,0) ## i64
  mode=1 ## i64
  while mode<=3
    st=i64[ffws_words(n,rank+64)]
    z=ffws_init(st,n,rank+64,seed,rank,19071+n) ## i64
    c=i64[ffwd_words(st,256)]
    if ffwd_init(st,c,0,256)!=0 || ffwd_init(st,c,4,256)!=0 || ffwd_init(st,c,mode,3)!=0 || ffwd_init(st,c,mode,512)!=0
      << "FAIL directed invalid configuration"
      exit(1)
    if ffwd_init(st,c,mode,256)!=1 || directed_consistent(st,c)!=1
      << "FAIL directed init"
      exit(1)
    # Reordering the same terms must not defeat the state fingerprint.
    first=st[st[16]] ## i64
    st[st[16]]=st[st[16]+1]
    st[st[16]+1]=first
    same=c[4]==ffwd_fingerprint(st,2166136261) && c[5]==ffwd_fingerprint(st,7809847782465536322)
    st[st[16]+1]=st[st[16]]
    st[st[16]]=first
    if !same || directed_consistent(st,c)!=1
      << "FAIL directed term-order hash"
      exit(1)
    scratch=i64[12*stride]
    stop=i64[1]
    batch=0 ## i64
    while batch<12
      result=ffwd_work(st,scratch,c,1000,stop,8) ## i64
      if result<1 || directed_consistent(st,c)!=1
        << "FAIL directed transaction n="+n.to_s()+" mode="+mode.to_s()+" batch="+batch.to_s()
        exit(1)
      batch+=1
    out=i64[8192*3*stride]
    parity=i64[n*n*stride]
    r=ffws_export(st,out,0) ## i64
    if ffpk_exact(out,out.size(),r,n,n,n,parity,parity.size(),0)!=1
      << "FAIL directed current tensor"
      exit(1)
    r=ffws_export(st,out,1)
    if r>rank || ffpk_exact(out,out.size(),r,n,n,n,parity,parity.size(),0)!=1
      << "FAIL directed best tensor"
      exit(1)
    if st[7]!=12000 || c[9]+c[16]!=st[7] || st[8]+st[9]!=st[7]
      << "FAIL directed counters"
      exit(1)
    stop[0]=1
    z=ffwd_work(st,scratch,c,1000,stop,8)
    if st[7]!=12000
      exit(1)
    blocked+=c[10]+c[11]
    # A table-index collision is not a fingerprint match; eviction is
    # explicit and bounded, not an exact forever-visited guarantee.
    c[4]=12345
    c[5]=67890
    z=ffwd_remember(c)
    if ffwd_seen(c,12345,67890)!=1 || ffwd_seen(c,12345,67891)!=0
      exit(1)
    c[4]=111
    c[5]=222
    c[6]=333
    c[7]=444
    c[8]=1
    expected=0 ## i64
    if mode>=2
      expected=1
    if ffwd_guard(c,111,222,0)!=expected || ffwd_guard(c,333,444,0)!=expected || ffwd_guard(c,333,444,1)!=0 || ffwd_guard(c,12345,67890,1)!=0
      << "FAIL directed inverse or aspiration"
      exit(1)
    expected=0
    if mode==3
      expected=2
    if ffwd_guard(c,12345,67890,0)!=expected
      << "FAIL directed history guard"
      exit(1)
    << "PASS directed n="+n.to_s()+" mode="+mode.to_s()+" accepted="+st[8].to_s()+" inverse="+c[10].to_s()+" tabu="+c[11].to_s()+" best="+r.to_s()
    mode+=1
  n+=1
if blocked<1
  << "FAIL guards never exercised"
  exit(1)
Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!
