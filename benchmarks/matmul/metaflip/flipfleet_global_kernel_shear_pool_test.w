use metaflip_worker
use flipfleet_global_kernel_shear_pool_lib
use flipfleet_global_kernel_shear_bundle

-> ffgkst_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)

root = "/repo with spaces" ## String
binary = "/tmp/global shear worker" ## String
seed = "/tmp/exact seed" ## String
output = "/tmp/global shear output" ## String
build = ffgksb_build_command(root, binary) ## String
ffgkst_expect("build source and flags", build.include?("flipfleet_global_kernel_shear_pool.w") && build.include?("--release") && build.include?("--native") && build.include?("--fast") && build.include?("--lto"))
ffgkst_expect("quoted build paths", build.include?("'/repo with spaces'") && build.include?("'/tmp/global shear worker'"))
epoch = ffgksb_epoch_command(root, binary, seed, output, 5) ## String
ffgkst_expect("epoch command", epoch.include?("'/tmp/exact seed' '/tmp/global shear output' 5"))
ffgkst_expect("same path rejected", ffgksb_epoch_command(root, binary, seed, seed, 5) == "")
ffgkst_expect("negative nonce rejected", ffgksb_epoch_command(root, binary, seed, output, -1) == "")

# Plan five is the natural striped phase that exposes a real whole-frontier
# three-term dependency. Seed a stale file first: the verified hit must replace
# it, and the serialized endpoint must independently reparse as exact.
real_seed = "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt" ## String
real_output = "/tmp/flipfleet_global_kernel_shear_pool_test.out" ## String
miss_output = "/tmp/flipfleet_global_kernel_shear_pool_test.miss" ## String
z = write_file(miss_output, "stale\n")
miss_meta = i64[16]
miss = ffgks_run_engine(real_seed, miss_output, 0, miss_meta) ## i64
ffgkst_expect("ordinary miss clears stale output", miss == 0 && read_file(miss_output) == nil)
z = write_file(real_output, "stale\n")
meta = i64[16]
hit = ffgks_run_engine(real_seed, real_output, 5, meta) ## i64
ffgkst_expect("real global shear hit", hit == 93 && meta[0] == 5 && meta[1] == 5 && meta[5] >= 3 && meta[10] == 1)
capacity = ffw_default_capacity(5) ## i64
check = i64[ffw_state_size(capacity)]
loaded = ffw_load_scheme_cap(check, real_output, 5, capacity, 94009, 0, 1, 1, 1) ## i64
ffgkst_expect("published endpoint full exact", loaded == 93 && ffw_verify_current_exact(check, 5) == 1)
z = ffgks_remove(real_output)

<< "flipfleet global-kernel-shear pool tests passed changed=" + meta[5].to_s() + " elapsed_ms=" + meta[11].to_s()
