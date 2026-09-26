# Fixed-work replay/profiling driver. Arguments: MFW steps mode seed prefix audit.
use ../lib/metaflip/wide/directed
use core/crypto/sha256

if ARGV.size()!=6
  exit(2)
raw=File.read_prefix(ARGV[0],12632129)
steps=ARGV[1].to_i() ## i64
mode=ARGV[2].to_i() ## i64
nonce=ARGV[3].to_i() ## i64
audit=ARGV[5].to_i() ## i64
if raw==nil || steps<1 || steps>100000000 || mode<1 || mode>3 || audit<0 || audit>1
  exit(2)
seed=i64[3*32*16384]
info=i64[4]
rank=ffpk_parse(raw,seed,seed.size(),info,4) ## i64
stride=ffpk_stride(info[0],info[1],info[2]) ## i64
parity=i64[32768]
if rank<1 || rank+64>16384 || ffpk_exact(seed,seed.size(),rank,info[0],info[1],info[2],parity,parity.size(),0)!=1
  exit(1)
st=i64[ffws_words_rect(info[0],info[1],info[2],rank+64)]
if ffws_init_rect(st,info[0],info[1],info[2],rank+64,seed,rank,nonce)!=1
  exit(1)
c=i64[ffwd_words(st,4096)]
if ffwd_init(st,c,mode,4096)!=1
  exit(1)
scratch=i64[12*stride]
stop=i64[1]
remaining=steps ## i64
start=ccall("__w_clock_ms") ## i64
while remaining>0
  batch=100000 ## i64
  if audit==1
    batch=1000
  if batch>remaining
    batch=remaining
  if ffwd_work(st,scratch,c,batch,stop,8)<1 || stop[0]!=0
    exit(1)
  remaining-=batch
  if audit==1 && (c[4]!=ffwd_fingerprint(st,2166136261) || c[5]!=ffwd_fingerprint(st,7809847782465536322))
    exit(1)
  if audit==1 && c[30]>0
    i=0 ## i64
    while i<st[4]
      slot=st[st[16]+i] ## i64
      at=st[14]+slot*3*stride ## i64
      if c[c[30]+slot]!=ffwd_term(st,at,stride,2166136261) || c[c[31]+slot]!=ffwd_term(st,at,stride,7809847782465536322)
        exit(1)
      i+=1
ms=ccall("__w_clock_ms")-start ## i64
if c[4]!=ffwd_fingerprint(st,2166136261) || c[5]!=ffwd_fingerprint(st,7809847782465536322)
  exit(1)
out=i64[3*32*16384]
r=ffws_export(st,out,0) ## i64
if ffpk_exact(out,out.size(),r,info[0],info[1],info[2],parity,parity.size(),0)!=1
  exit(1)
r=ffpk_canonicalize(out,out.size(),r,stride)
current=ffpk_blob(out,r,info[0],info[1],info[2])
best=ffws_export(st,out,1) ## i64
if ffpk_exact(out,out.size(),best,info[0],info[1],info[2],parity,parity.size(),0)!=1
  exit(1)
best=ffpk_canonicalize(out,out.size(),best,stride)
saved=ffpk_blob(out,best,info[0],info[1],info[2])
if !write_file(ARGV[4]+"-current.mfw",current) || !write_file(ARGV[4]+"-best.mfw",saved)
  exit(1)
<< "REPLAY ms="+ms.to_s()+" moves="+st[7].to_s()+" accepts="+st[8].to_s()+" rejects="+st[9].to_s()+" bits="+st[10].to_s()+" best_bits="+st[11].to_s()+" current_rank="+r.to_s()+" best_rank="+best.to_s()+" rng="+st[6].to_s()+" h1="+c[4].to_s()+" h2="+c[5].to_s()+" legal="+c[9].to_s()+" inverse="+c[10].to_s()+" tabu="+c[11].to_s()+" novelty="+c[12].to_s()+" repeats="+c[13].to_s()+" aspirations="+c[15].to_s()+" no_edge="+c[16].to_s()+" escapes="+c[17].to_s()+" resets="+c[18].to_s()+" current="+Crypto:SHA256.hexdigest(current)+" best="+Crypto:SHA256.hexdigest(saved)
