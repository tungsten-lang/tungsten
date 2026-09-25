use ../lib/metaflip/composition/wide_pairs

if ARGV.size() != 3
  exit(2)
raw = File.read_prefix(ARGV[0],12632129)
source = i64[3*32*16384]
out = i64[3*32*16384]
shape = i64[4]
meta = i64[4]
parity = i64[32768]
rank = ffpk_parse(raw,source,source.size(),shape,4) ## i64
if rank < 1 || ffpk_exact(source,source.size(),rank,shape[0],shape[1],shape[2],parity,parity.size(),20000000) != 1
  exit(1)
axis = ffpk_decimal(ARGV[2]) ## i64
result = pair_compose(source,rank,shape[0],shape[1],shape[2],axis,out,meta) ## i64
if result < 1 || ffpk_exact(out,out.size(),result,meta[0],meta[1],meta[2],parity,parity.size(),20000000) != 1 || !write_file(ARGV[1],ffpk_blob(out,result,meta[0],meta[1],meta[2]))
  exit(1)
<< "PAIRS " + axis.to_s() + " " + rank.to_s() + " " + meta[3].to_s() + " " + result.to_s()
