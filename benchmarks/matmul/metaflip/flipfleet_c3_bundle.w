# flipfleet_c3_bundle.w -- native build/epoch glue for C3 GPU lanes.
#
# The checked-in workers are dimension-specialized quotient walkers.  Every
# accepted GPU mutation XOR-toggles a complete C3 orbit.  A campaign therefore
# compiles one of these Tungsten sources (when its cached binary is absent) and
# invokes that binary directly; c3_gpu_worker_gen.py is never on the campaign
# runtime path.
#
# Each worker independently gates both its runtime seed and copied-back winner:
# factors must be nonzero, in range, and duplicate-free; the full matrix-
# multiplication tensor is reconstructed over GF(2); and C3 closure is checked.
# The output file is cleared before dispatch and rewritten only after all three
# candidate gates pass.

use flipfleet_metallib_cache

-> ffc3_supported(n) (i64) i64
  ok = 0 ## i64
  if n >= 3 && n <= 7
    ok = 1
  ok

-> ffc3_tag(n) (i64)
  n.to_s() + n.to_s() + n.to_s()

-> ffc3_bundle_rel()
  "benchmarks/matmul/metaflip/c3_bundle"

-> ffc3_source_rel(n) (i64)
  ffc3_bundle_rel() + "/c3_" + ffc3_tag(n) + ".w"

-> ffc3_metal_rel(n) (i64)
  ffc3_bundle_rel() + "/c3_" + ffc3_tag(n) + ".metal"

-> ffc3_join(root, relative) (String String)
  out = relative
  if root != ""
    out = root + "/" + relative
  out

-> ffc3_source_path(root, n) (String i64)
  ffc3_join(root, ffc3_source_rel(n))

-> ffc3_metal_path(root, n) (String i64)
  ffc3_join(root, ffc3_metal_rel(n))

# Naive rank plus the default 15-rank band, six orbit-toggle temporaries, and
# at least one spare slot, rounded to eight.  Record seeds fit with more room.
-> ffc3_cap(n) (i64) i64
  if n == 3
    return 56
  if n == 4
    return 88
  if n == 5
    return 152
  if n == 6
    return 240
  if n == 7
    return 368
  0

-> ffc3_mask_bytes(n) (i64) i64
  bytes = 4 ## i64
  if n >= 6
    bytes = 8
  bytes

-> ffc3_max_walkers() i64
  4096

-> ffc3_max_steps() i64
  1000000

-> ffc3_max_dispatches() i64
  64

-> ffc3_clamp(value, low, high) (i64 i64 i64) i64
  out = value ## i64
  if out < low
    out = low
  if out > high
    out = high
  out

-> ffc3_shell_quote(value) (String)
  "'" + value.replace("'", "'\"'\"'") + "'"

# The compiler writes the executable and an offline `.metallib` cache beside
# `binary`; the checked-in sidecar remains the source of truth.
-> ffc3_build_command(root, n, binary) (String i64 String)
  if ffc3_supported(n) == 0 || root == "" || binary == ""
    return ""
  llpath = binary + ".ll"
  "cd " + ffc3_shell_quote(root) + " && TUNGSTEN_LL_PATH=" + ffc3_shell_quote(llpath) + " TUNGSTEN_METAL_PATH=" + ffc3_shell_quote(ffmc_generated_source_path(binary)) + " bin/tungsten -o " + ffc3_shell_quote(binary) + " " + ffc3_shell_quote(ffc3_source_rel(n)) + " --release --native --fast --lto"

-> ffc3_build(root, n, binary) (String i64 String) i64
  command = ffc3_build_command(root, n, binary)
  if command == ""
    return 0
  built = system(command)
  if !built
    return 0
  ffmc_build(root, ffmc_generated_source_path(binary), binary)

-> ffc3_metallib_path(binary) (String)
  ffmc_library_path(binary)

-> ffc3_metallib_fresh(root, n, binary) (String i64 String) i64
  ffmc_fresh(ffmc_generated_source_path(binary), binary)

# Positional C3 worker ABI:
#   seed output walkers steps dispatches band plus_period metallib
#
# `dispatches` bounds an adaptive scheduling epoch.  The API clamps every work
# parameter to the same hard limits enforced again by the worker executable.
# The seed/output paths may be absolute; the worker refuses identical paths.
-> ffc3_epoch_command(root, binary, n, seed_path, output_path, walkers, steps, dispatches, band, plus_period) (String String i64 String String i64 i64 i64 i64 i64)
  if ffc3_supported(n) == 0 || root == "" || binary == "" || seed_path == "" || output_path == ""
    return ""
  epoch_walkers = ffc3_clamp(walkers, 1, ffc3_max_walkers()) ## i64
  epoch_steps = ffc3_clamp(steps, 1, ffc3_max_steps()) ## i64
  epoch_dispatches = ffc3_clamp(dispatches, 1, ffc3_max_dispatches()) ## i64
  epoch_band = ffc3_clamp(band, 0, ffc3_cap(n) - 6) ## i64
  epoch_plus = ffc3_clamp(plus_period, 0, 1000000000) ## i64
  "cd " + ffc3_shell_quote(root) + " && " + ffc3_shell_quote(binary) + " " + ffc3_shell_quote(seed_path) + " " + ffc3_shell_quote(output_path) + " " + epoch_walkers.to_s() + " " + epoch_steps.to_s() + " " + epoch_dispatches.to_s() + " " + epoch_band.to_s() + " " + epoch_plus.to_s() + " " + ffc3_shell_quote(ffc3_metallib_path(binary))

-> ffc3_epoch(root, binary, n, seed_path, output_path, walkers, steps, dispatches, band, plus_period) (String String i64 String String i64 i64 i64 i64 i64) i64
  command = ffc3_epoch_command(root, binary, n, seed_path, output_path, walkers, steps, dispatches, band, plus_period)
  if command == ""
    return 0
  ran = system(command)
  result = 0 ## i64
  if ran
    result = 1
  result
