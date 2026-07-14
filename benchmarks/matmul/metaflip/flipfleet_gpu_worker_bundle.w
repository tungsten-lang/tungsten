# Lightweight build/launch glue for FlipFleet's bounded surgery workers.
#
# Keep these helpers separate from the large @gpu implementation modules so
# the native coordinator can build and launch children without merging their
# kernels (and an unused multi-kernel Metal sidecar) into itself.

use flipfleet_metallib_cache

-> ffgwb_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

-> ffm_build_command(root, binary) (String String)
  source = "benchmarks/matmul/metaflip/flipfleet_mitm_lane.w"
  "cd " + ffgwb_shell_quote(root) + " && TUNGSTEN_LL_PATH=" + ffgwb_shell_quote(binary + ".ll") + " TUNGSTEN_METAL_PATH=" + ffgwb_shell_quote(ffmc_generated_source_path(binary)) + " bin/tungsten -o " + ffgwb_shell_quote(binary) + " " + ffgwb_shell_quote(source) + " --release --native --fast --lto"

-> ffm_build(root, binary) (String String) i64
  built = system(ffm_build_command(root, binary))
  if !built
    return 0
  ffmc_build(root, ffmc_generated_source_path(binary), binary)

-> ffm_metallib_path(binary) (String)
  ffmc_library_path(binary)

-> ffm_metallib_fresh(root, binary) (String String) i64
  ffmc_fresh(ffmc_generated_source_path(binary), binary)

-> ffgwb_mitm_plan_valid(n, subsets, pool, nearby, offset) (i64 i64 i64 i64 i64) i64
  if n < 3 || n > 7
    return 0
  if subsets < 1 || subsets > 16
    return 0
  if pool < 4 || pool > 700
    return 0
  if nearby < 0 || nearby > 8 || offset < 0
    return 0
  1

-> ffm_epoch_command(root, binary, seed_path, output_path, n, subsets, pool, nearby, offset) (String String String String i64 i64 i64 i64 i64)
  if ffgwb_mitm_plan_valid(n, subsets, pool, nearby, offset) == 0
    return ""
  "cd " + ffgwb_shell_quote(root) + " && " + ffgwb_shell_quote(binary) + " " + ffgwb_shell_quote(seed_path) + " " + ffgwb_shell_quote(output_path) + " " + n.to_s() + " " + subsets.to_s() + " " + pool.to_s() + " " + nearby.to_s() + " " + offset.to_s() + " '' " + ffgwb_shell_quote(ffm_metallib_path(binary))

-> ffpc_build_command(root, binary) (String String)
  source = "benchmarks/matmul/metaflip/flipfleet_constraint_pool.w"
  "cd " + ffgwb_shell_quote(root) + " && TUNGSTEN_LL_PATH=" + ffgwb_shell_quote(binary + ".ll") + " TUNGSTEN_METAL_PATH=" + ffgwb_shell_quote(ffmc_generated_source_path(binary)) + " bin/tungsten -o " + ffgwb_shell_quote(binary) + " " + ffgwb_shell_quote(source) + " --release --native --fast --lto"

-> ffpc_build(root, binary) (String String) i64
  built = system(ffpc_build_command(root, binary))
  if !built
    return 0
  ffmc_build(root, ffmc_generated_source_path(binary), binary)

-> ffpc_metallib_path(binary) (String)
  ffmc_library_path(binary)

-> ffpc_metallib_fresh(root, binary) (String String) i64
  ffmc_fresh(ffmc_generated_source_path(binary), binary)

-> ffpc_epoch_command(root, binary, seed_path, output_path, n, mode, lanes, steps, epoch) (String String String String i64 i64 i64 i64 i64)
  metal_path = root + "/benchmarks/matmul/metaflip/flipfleet_constraint_pool.metal"
  "cd " + ffgwb_shell_quote(root) + " && " + ffgwb_shell_quote(binary) + " " + ffgwb_shell_quote(seed_path) + " " + ffgwb_shell_quote(output_path) + " " + n.to_s() + " " + mode.to_s() + " " + lanes.to_s() + " " + steps.to_s() + " " + epoch.to_s() + " " + ffgwb_shell_quote(metal_path) + " " + ffgwb_shell_quote(ffpc_metallib_path(binary))

-> ffx_build_command(root, binary) (String String)
  source = "benchmarks/matmul/metaflip/flipfleet_kxor_pool.w"
  "cd " + ffgwb_shell_quote(root) + " && TUNGSTEN_LL_PATH=" + ffgwb_shell_quote(binary + ".ll") + " TUNGSTEN_METAL_PATH=" + ffgwb_shell_quote(ffmc_generated_source_path(binary)) + " bin/tungsten -o " + ffgwb_shell_quote(binary) + " " + ffgwb_shell_quote(source) + " --release --native --fast --lto"

-> ffx_build(root, binary) (String String) i64
  built = system(ffx_build_command(root, binary))
  if !built
    return 0
  ffmc_build(root, ffmc_generated_source_path(binary), binary)

-> ffx_metallib_path(binary) (String)
  ffmc_library_path(binary)

-> ffx_metallib_fresh(root, binary) (String String) i64
  ffmc_fresh(ffmc_generated_source_path(binary), binary)

-> ffx_epoch_command(root, binary, seed_path, output_path, n, k, subsets, pool, nearby, offset) (String String String String i64 i64 i64 i64 i64 i64)
  metal_path = root + "/benchmarks/matmul/metaflip/flipfleet_kxor_pool.metal"
  "cd " + ffgwb_shell_quote(root) + " && " + ffgwb_shell_quote(binary) + " " + ffgwb_shell_quote(seed_path) + " " + ffgwb_shell_quote(output_path) + " " + n.to_s() + " " + k.to_s() + " " + subsets.to_s() + " " + pool.to_s() + " " + nearby.to_s() + " " + offset.to_s() + " " + ffgwb_shell_quote(metal_path) + " " + ffgwb_shell_quote(ffx_metallib_path(binary))

# Complete local factor-span refactoring.  Its Metal source is generated from
# the @gpu functions in the pure-Tungsten worker library, so both the source
# fallback and cached metallib live beside the child binary in /tmp.
-> ffsrp_build_command(root, binary) (String String)
  source = "benchmarks/matmul/metaflip/flipfleet_span_refactor_pool.w"
  "cd " + ffgwb_shell_quote(root) + " && TUNGSTEN_LL_PATH=" + ffgwb_shell_quote(binary + ".ll") + " TUNGSTEN_METAL_PATH=" + ffgwb_shell_quote(ffmc_generated_source_path(binary)) + " bin/tungsten -o " + ffgwb_shell_quote(binary) + " " + ffgwb_shell_quote(source) + " --release --native --fast --lto"

-> ffsrp_build(root, binary) (String String) i64
  built = system(ffsrp_build_command(root, binary))
  if !built
    return 0
  ffmc_build(root, ffmc_generated_source_path(binary), binary)

-> ffsrp_metallib_path(binary) (String)
  ffmc_library_path(binary)

-> ffsrp_metallib_fresh(root, binary) (String String) i64
  ffmc_fresh(ffmc_generated_source_path(binary), binary)

-> ffsrp_plan_valid(n, k, want, subsets, offset) (i64 i64 i64 i64 i64) i64
  if n < 3 || n > 7
    return 0
  if k < 3 || k > 4
    return 0
  if k == 3 && (want < 2 || want > 4)
    return 0
  if k == 4 && (want < 3 || want > 4)
    return 0
  if subsets < 1 || subsets > 8 || offset < 0
    return 0
  # A four-span neighborhood may allocate millions of exact pair entries.
  # Never multiply that table inside one child process.
  if k == 4 && subsets != 1
    return 0
  1

-> ffsrp_epoch_command(root, binary, seed_path, output_path, n, k, want, subsets, offset) (String String String String i64 i64 i64 i64 i64)
  if ffsrp_plan_valid(n, k, want, subsets, offset) == 0
    return ""
  metal_path = ffmc_generated_source_path(binary)
  "cd " + ffgwb_shell_quote(root) + " && " + ffgwb_shell_quote(binary) + " " + ffgwb_shell_quote(seed_path) + " " + ffgwb_shell_quote(output_path) + " " + n.to_s() + " " + k.to_s() + " " + want.to_s() + " " + subsets.to_s() + " " + offset.to_s() + " " + ffgwb_shell_quote(metal_path) + " " + ffgwb_shell_quote(ffsrp_metallib_path(binary))

# Exact q=2 low-rank shear absorption.  Metal enumerates the regular
# pair/axis/carrier product; the host materializes and independently verifies
# the deterministic first non-one-flip endpoint.
-> fflrsp_build_command(root, binary) (String String)
  source = "benchmarks/matmul/metaflip/flipfleet_low_rank_shear_pool.w"
  "cd " + ffgwb_shell_quote(root) + " && TUNGSTEN_LL_PATH=" + ffgwb_shell_quote(binary + ".ll") + " TUNGSTEN_METAL_PATH=" + ffgwb_shell_quote(ffmc_generated_source_path(binary)) + " bin/tungsten -o " + ffgwb_shell_quote(binary) + " " + ffgwb_shell_quote(source) + " --release --native --fast --lto"

-> fflrsp_build(root, binary) (String String) i64
  built = system(fflrsp_build_command(root, binary))
  if !built
    return 0
  ffmc_build(root, ffmc_generated_source_path(binary), binary)

-> fflrsp_metallib_path(binary) (String)
  ffmc_library_path(binary)

-> fflrsp_metallib_fresh(root, binary) (String String) i64
  ffmc_fresh(ffmc_generated_source_path(binary), binary)

-> fflrsp_plan_valid(n, pair_limit, nonce) (i64 i64 i64) i64
  if n < 5 || n > 7
    return 0
  if pair_limit < 1 || pair_limit > 2048 || nonce < 0
    return 0
  1

-> fflrsp_epoch_command(root, binary, seed_path, output_path, n, pair_limit, nonce) (String String String String i64 i64 i64)
  if fflrsp_plan_valid(n, pair_limit, nonce) == 0
    return ""
  metal_path = ffmc_generated_source_path(binary)
  "cd " + ffgwb_shell_quote(root) + " && " + ffgwb_shell_quote(binary) + " " + ffgwb_shell_quote(seed_path) + " " + ffgwb_shell_quote(output_path) + " " + n.to_s() + " " + pair_limit.to_s() + " " + nonce.to_s() + " " + ffgwb_shell_quote(metal_path) + " " + ffgwb_shell_quote(fflrsp_metallib_path(binary))
