# Native diagnostic driver: n mode seed milliseconds output-prefix.
use ../lib/metaflip/wide/directed
use ../lib/metaflip/wide/seeds
av=argv()
if av.size()!=5
  exit(2)
n=av[0].to_i() ## i64
mode=av[1].to_i() ## i64
nonce=av[2].to_i() ## i64
duration=av[3].to_i() ## i64
if n<8 || n>16 || mode<0 || mode>3 || duration<100 || duration>10000
  exit(2)
stride=ffpk_stride(n,n,n) ## i64
words=8192*3*stride ## i64
seed=i64[words]
rank=ffws_seed(seed,n,__DIR__+"/../lib/metaflip",0) ## i64
st=i64[ffws_words(n,rank+64)]
z=ffws_init(st,n,rank+64,seed,rank,nonce) ## i64
c=i64[ffwd_words(st,65536)]
z=ffwd_init(st,c,1,65536)
c[0]=mode
scratch=i64[12*stride]
stop=i64[1]
out=i64[words]
parity=i64[n*n*stride]
start=ccall("__w_clock_ms") ## i64
last=start ## i64
samples=0 ## i64
now=start ## i64
while now-start<duration
  if mode==0
    z=ffws_work(st,scratch,4096,stop,8)
  else
    z=ffwd_work(st,scratch,c,4096,stop,8)
  if z<1 || stop[0]!=0
    exit(1)
  now=ccall("__w_clock_ms")
  if now-last>=100
    r=ffws_export(st,out,0) ## i64
    r=ffpk_canonicalize(out,words,r,stride)
    if !write_file(av[4]+"-"+samples.to_s()+".mfw",ffpk_blob(out,r,n,n,n))
      exit(1)
    samples+=1
    last=now
ms=ccall("__w_clock_ms")-start ## i64
if mode!=0 && (c[4]!=ffwd_fingerprint(st,2166136261) || c[5]!=ffwd_fingerprint(st,7809847782465536322))
  exit(1)
r=ffws_export(st,out,1) ## i64
if ffpk_exact(out,words,r,n,n,n,parity,parity.size(),0)!=1
  exit(1)
r=ffpk_canonicalize(out,words,r,stride)
if !write_file(av[4]+"-best.mfw",ffpk_blob(out,r,n,n,n))
  exit(1)
<< "RESULT n="+n.to_s()+" mode="+mode.to_s()+" seed="+nonce.to_s()+" density_unrestricted=1 ms="+ms.to_s()+" attempts="+st[7].to_s()+" accepted="+st[8].to_s()+" no_pair="+st[23].to_s()+" blocked="+(st[9]-st[23]).to_s()+" best_rank="+st[5].to_s()+" best_bits="+st[11].to_s()+" legal="+(st[7]-st[23]).to_s()+" inverse="+c[10].to_s()+" tabu="+c[11].to_s()+" novelty_hashes="+c[12].to_s()+" repeat_hashes="+c[13].to_s()+" resets="+c[18].to_s()+" escapes="+c[17].to_s()+" samples="+samples.to_s()
