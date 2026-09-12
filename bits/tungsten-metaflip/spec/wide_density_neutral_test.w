use ../lib/metaflip/wide/directed
use ../lib/metaflip/wide/seeds

-> density_copy(src,dst) (i64[] i64[]) i64
  i=0 ## i64
  while i<src.size()
    dst[i]=src[i]
    i+=1
  1

# Find a real rank-neutral density reduction from a denser valid walk state,
# then force its fingerprint into history. Archive it without accepting it.
-> density_archive_before_guard(source,n) (i64[] i64) i64
  stride=source[1] ## i64
  out=i64[8192*3*stride]
  rank=ffws_export(source,out,0) ## i64
  st=i64[ffws_words(n,rank+64)]
  before=i64[st.size()]
  c=i64[ffwd_words(source,256)]
  saved=i64[c.size()]
  scratch=i64[12*stride]
  attempt=0 ## i64
  while attempt<1000
    z=ffws_init(st,n,rank+64,out,rank,777+attempt) ## i64
    # source and trial can have different capacities after a rank drop.
    if c.size()<ffwd_words(st,256)
      return 0
    z=ffwd_init(st,c,1,256)
    z=density_copy(st,before)
    z=density_copy(c,saved)
    old_bits=st[10] ## i64
    result=ffwd_one(st,scratch,c,0) ## i64
    if result==1 && st[4]==rank && st[10]<old_bits
      h1=c[4] ## i64
      h2=c[5] ## i64
      bits=st[10] ## i64
      z=density_copy(before,st)
      z=density_copy(saved,c)
      c[4]=h1
      c[5]=h2
      z=ffwd_remember(c)
      c[4]=saved[4]
      c[5]=saved[5]
      c[0]=3
      c[8]=0
      result=ffwd_one(st,scratch,c,0)
      if result!=0 || c[11]!=saved[11]+1 || st[4]!=rank || st[10]!=old_bits || st[5]!=rank || st[11]!=bits
        return 0
      if c[4]!=ffwd_fingerprint(st,2166136261) || c[5]!=ffwd_fingerprint(st,7809847782465536322)
        return 0
      parity=i64[n*n*stride]
      r=ffws_export(st,out,1) ## i64
      if ffpk_exact(out,out.size(),r,n,n,n,parity,parity.size(),0)!=1
        return 0
      r=ffws_export(st,out,0)
      return ffpk_exact(out,out.size(),r,n,n,n,parity,parity.size(),0)
    attempt+=1
  0

root=__DIR__+"/../lib/metaflip"
sizes=i64[3]
sizes[0]=8
sizes[1]=15
sizes[2]=16
uphill=i64[4]
shape=0 ## i64
while shape<3
  n=sizes[shape] ## i64
  stride=ffpk_stride(n,n,n) ## i64
  seed=i64[8192*3*stride]
  rank=ffws_seed(seed,n,root,0) ## i64
  mode=0 ## i64
  while mode<4
    a=i64[ffws_words(n,rank+64)]
    b=i64[a.size()]
    z=ffws_init(a,n,rank+64,seed,rank,19071) ## i64
    z=density_copy(a,b)
    ca=i64[ffwd_words(a,256)]
    cb=i64[ca.size()]
    z=ffwd_init(a,ca,1,256)
    ca[0]=mode
    z=density_copy(ca,cb)
    sa=i64[12*stride]
    sb=i64[12*stride]
    stop=i64[1]
    step=0 ## i64
    while step<20000
      old_rank=a[4] ## i64
      old_bits=a[10] ## i64
      best_rank=a[5] ## i64
      best_bits=a[11] ## i64
      escape=a[7]>0 && a[7]%2000==0
      if mode>0 && (ca[2]==0 || ca[19]>=256)
        escape=true
      if mode==0
        z=ffws_work(a,sa,1,stop,0)
        z=ffws_work(b,sb,1,stop,1000000)
      else
        z=ffwd_work(a,sa,ca,1,stop,0)
        z=ffwd_work(b,sb,cb,1,stop,1000000)
      if a[5]>best_rank || (a[5]==best_rank && a[11]>best_bits)
        << "FAIL density archive regressed"
        exit(1)
      # Count only genuine pair-flip increases, not density from an escape.
      if !escape && a[4]==old_rank && a[10]>old_bits+4
        uphill[mode]+=1
      step+=1
    if ffws_equal(a,0,b,0,a.size())!=1 || ffws_equal(ca,0,cb,0,ca.size())!=1
      << "FAIL legacy density option changed walk n="+n.to_s()+" mode="+mode.to_s()
      exit(1)
    if a[8]+a[9]!=a[7] || a[23]>a[9] || (mode<=1 && a[23]!=a[9])
      << "FAIL separated attempt counters"
      exit(1)
    out=i64[seed.size()]
    parity=i64[n*n*stride]
    r=ffws_export(a,out,0) ## i64
    if ffpk_exact(out,out.size(),r,n,n,n,parity,parity.size(),0)!=1
      exit(1)
    r=ffws_export(a,out,1)
    if ffpk_exact(out,out.size(),r,n,n,n,parity,parity.size(),0)!=1
      exit(1)
    if n==8 && mode==1
      if density_archive_before_guard(a,n)!=1
        << "FAIL density archival changed history policy or lost a seen best"
        exit(1)
      << "PASS density-only best archived despite history rejection"
    << "PASS density-neutral n="+n.to_s()+" mode="+mode.to_s()+" uphill="+uphill[mode].to_s()+" best="+a[5].to_s()+" bits="+a[11].to_s()
    mode+=1
  shape+=1
mode=0
while mode<4
  if uphill[mode]<1
    << "FAIL did not exercise large uphill density move"
    exit(1)
  mode+=1
Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!
