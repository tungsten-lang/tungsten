use ../pooled_exact

args = argv()
if args.size() != 6
  << "usage: metaflip_pooled_exact seed output n kind budget nonce"
  exit(2)
n = args[2].to_i() ## i64
kind = args[3].to_i() ## i64
budget = args[4].to_i() ## i64
nonce = args[5].to_i() ## i64
meta = i64[20]
result = ffpem_run(args[0], args[1], n, kind, budget, nonce, meta) ## i64
if result < 0
  exit(2)
