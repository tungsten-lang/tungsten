use ../lib/metaflip/wide/directed
use ../lib/metaflip/compose

root = __DIR__ + "/../lib/metaflip"
n = 2 ## i64
m = 3 ## i64
p = 4 ## i64
stride = ffpk_stride(n,m,p) ## i64
us = i64[128]
vs = i64[128]
ws = i64[128]
rank = ffsc_load(root + "/seeds/gf2/matmul_2x3x4_rank20_d130_global_isotropy_gf2.txt",us,vs,ws,128) ## i64
if rank != 20 || stride != 1
  << "FAIL rectangular seed"
  exit(1)
cap = rank+16 ## i64
seed = i64[3*stride*cap]
i = 0 ## i64
while i < rank
  seed[(3*i)*stride]=us[i]
  seed[(3*i+1)*stride]=vs[i]
  seed[(3*i+2)*stride]=ws[i]
  i += 1
parity = i64[12]
if ffpk_exact(seed,seed.size(),rank,n,m,p,parity,parity.size(),0) != 1
  << "FAIL rectangular seed tensor"
  exit(1)
st = i64[ffws_words_rect(n,m,p,cap)]
if ffws_init_rect(st,n,m,p,cap,seed,rank,19071) != 1 || st[24] != 6 || st[25] != 12 || st[26] != 8
  << "FAIL rectangular init"
  exit(1)
scratch = i64[12*stride]
stop = i64[1]
z = ffws_work(st,scratch,10000,stop,8) ## i64
current = ffws_export(st,seed,0) ## i64
if ffpk_exact(seed,seed.size(),current,n,m,p,parity,parity.size(),0) != 1
  << "FAIL rectangular ordinary walk"
  exit(1)
best = ffws_export(st,seed,1) ## i64
if best > rank || ffpk_exact(seed,seed.size(),best,n,m,p,parity,parity.size(),0) != 1
  << "FAIL rectangular ordinary best"
  exit(1)
if ffws_init_rect(st,n,m,p,cap,seed,best,19072) != 1
  << "FAIL rectangular directed init"
  exit(1)
control = i64[ffwd_words(st,1024)]
if ffwd_init(st,control,2,1024) != 1
  << "FAIL rectangular directed control"
  exit(1)
z = ffwd_work(st,scratch,control,10000,stop,8)
current = ffws_export(st,seed,0)
if ffpk_exact(seed,seed.size(),current,n,m,p,parity,parity.size(),0) != 1
  << "FAIL rectangular directed walk"
  exit(1)
best = ffws_export(st,seed,1)
if best > rank || ffpk_exact(seed,seed.size(),best,n,m,p,parity,parity.size(),0) != 1
  << "FAIL rectangular directed best"
  exit(1)
wide_cap = 8200 ## i64
wide_st = i64[ffws_words_rect(n,m,p,wide_cap)]
if ffws_init_rect(wide_st,n,m,p,wide_cap,seed,best,19073) != 1
  << "FAIL rectangular rank-over-8192 capacity"
  exit(1)
seed[0] = seed[0] | (1 << 6)
if ffws_init_rect(st,n,m,p,cap,seed,best,19073) != 0
  << "FAIL rectangular width gate"
  exit(1)

# Exercise the multiword layout at a portfolio-scale rectangular shape, not
# just the one-limb seed above. The naive tensor is an exact independent gate.
n=14
m=18
p=25
stride=ffpk_stride(n,m,p)
rank=n*m*p
cap=rank+16
large=i64[3*stride*cap]
t=0 ## i64
i=0
while i<n
  j=0 ## i64
  while j<m
    k=0 ## i64
    while k<p
      u=i*m+j ## i64
      v=j*p+k ## i64
      w=i*p+k ## i64
      large[(3*t)*stride+u/32]=1 << (u%32)
      large[(3*t+1)*stride+v/32]=1 << (v%32)
      large[(3*t+2)*stride+w/32]=1 << (w%32)
      t+=1
      k+=1
    j+=1
  i+=1
large_parity=i64[m*p*((n*p+31)/32)]
if ffpk_exact(large,large.size(),rank,n,m,p,large_parity,large_parity.size(),0) != 1
  << "FAIL multiword rectangular tensor"
  exit(1)
large_st=i64[ffws_words_rect(n,m,p,cap)]
if ffws_init_rect(large_st,n,m,p,cap,large,rank,19074) != 1 || large_st[1] != 15
  << "FAIL multiword rectangular init"
  exit(1)
large_scratch=i64[12*stride]
z=ffws_work(large_st,large_scratch,1000,stop,8)
current=ffws_export(large_st,large,0)
if ffpk_exact(large,large.size(),current,n,m,p,large_parity,large_parity.size(),0) != 1
  << "FAIL multiword rectangular walk"
  exit(1)
<< "PASS rectangular wide pair walks"
Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!
