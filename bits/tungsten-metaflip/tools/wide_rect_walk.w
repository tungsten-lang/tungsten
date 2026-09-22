# Standalone finite multiword rectangular walk. MFW1 input/output are fully
# checked before admission; this does not mutate the fleet's live archives.
use ../lib/metaflip/wide/directed
use core/file

args = argv()
if args.size() != 4
  << "usage: wide-rect-walk NxMxP SEED.mfw OUTPUT.mfw STEPS"
  exit(2)
shape = args[0].split("x")
if shape.size() != 3
  << "invalid tensor shape"
  exit(2)
n = ffpk_decimal(shape[0]) ## i64
m = ffpk_decimal(shape[1]) ## i64
p = ffpk_decimal(shape[2]) ## i64
stride = ffpk_stride(n,m,p) ## i64
steps = ffpk_decimal(args[3]) ## i64
if n < 2 || m < 2 || p < 2 || stride < 1 || steps < 1 || steps > 1000000000 || File.exists?(args[2])
  << "invalid dimensions, step count, or existing output"
  exit(2)
raw = read_file(args[1])
if raw == nil
  << "missing seed"
  exit(2)
data = i64[3*stride*8192]
meta = i64[4]
rank = ffpk_parse(raw,data,data.size(),meta,4) ## i64
if rank < 1 || meta[0] != n || meta[1] != m || meta[2] != p || rank+64 > 8192
  << "invalid MFW1 seed"
  exit(2)
parity = i64[m*p*((n*p+31)/32)]
if ffpk_exact(data,data.size(),rank,n,m,p,parity,parity.size(),0) != 1
  << "seed failed full tensor verification"
  exit(2)
cap = rank+64 ## i64
st = i64[ffws_words_rect(n,m,p,cap)]
if ffws_init_rect(st,n,m,p,cap,data,rank,19071) != 1
  << "wide rectangular initialization failed"
  exit(2)
control = i64[ffwd_words(st,4096)]
if ffwd_init(st,control,2,4096) != 1
  << "directed control initialization failed"
  exit(2)
scratch = i64[12*stride]
stop = i64[1]
remaining = steps ## i64
while remaining > 0
  batch = remaining ## i64
  if batch > 100000
    batch = 100000
  if ffwd_work(st,scratch,control,batch,stop,8) < 0
    << "directed walk failed"
    exit(1)
  remaining -= batch
best = ffws_export(st,data,1) ## i64
if best < 1 || ffpk_exact(data,data.size(),best,n,m,p,parity,parity.size(),0) != 1
  << "result failed full tensor verification"
  exit(1)
if ffpk_canonicalize(data,data.size(),best,stride) != best
  << "result canonicalization failed"
  exit(1)
if !write_file(args[2],ffpk_blob(data,best,n,m,p))
  << "cannot write result"
  exit(1)
<< "WIDE_RECT_RESULT tensor="+args[0]+" seed_rank="+rank.to_s()+" rank="+best.to_s()+" moves="+st[7].to_s()+" accepted="+st[8].to_s()+" no_pair="+st[23].to_s()+" escapes="+control[17].to_s()+" output="+args[2]
