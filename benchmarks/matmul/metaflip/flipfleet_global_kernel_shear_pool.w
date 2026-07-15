use flipfleet_global_kernel_shear_pool_lib

args = argv()
if args.size() != 3
  << "usage: flipfleet_global_kernel_shear_pool seed.txt output.txt nonce"
  exit(2)
nonce = args[2].to_i() ## i64
meta = i64[16]
result = ffgks_run_engine(args[0], args[1], nonce, meta) ## i64
if result < 0
  exit(2)
