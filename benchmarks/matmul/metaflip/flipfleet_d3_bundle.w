# Native build/epoch glue for the bounded 6x6 C3 x Z2 quotient experiment.
# The campaign runtime is entirely Tungsten plus the checked-in Metal sidecar.

use flipfleet_metallib_cache

-> ffd3b_supported(n) (i64) i64
  ok = 0 ## i64
  if n == 6
    ok = 1
  ok

-> ffd3b_bundle_rel()
  "benchmarks/matmul/metaflip/d3_bundle"

-> ffd3b_source_rel(n) (i64)
  if n == 6
    return ffd3b_bundle_rel() + "/d3_666.w"
  ""

-> ffd3b_metal_rel(n) (i64)
  if n == 6
    return ffd3b_bundle_rel() + "/d3_666.metal"
  ""

-> ffd3b_join(root, relative) (String String)
  out = relative
  if root != ""
    out = root + "/" + relative
  out

-> ffd3b_source_path(root, n) (String i64)
  ffd3b_join(root, ffd3b_source_rel(n))

-> ffd3b_metal_path(root, n) (String i64)
  ffd3b_join(root, ffd3b_metal_rel(n))

-> ffd3b_cap(n) (i64) i64
  if n == 6
    return 240
  0

-> ffd3b_max_walkers() i64
  4096

-> ffd3b_max_steps() i64
  1000000

-> ffd3b_max_dispatches() i64
  64

-> ffd3b_clamp(value, low, high) (i64 i64 i64) i64
  out = value ## i64
  if out < low
    out = low
  if out > high
    out = high
  out

-> ffd3b_shell_quote(value) (String)
  "'" + value.replace("'", "'\"'\"'") + "'"

-> ffd3b_build_command(root, n, binary) (String i64 String)
  if ffd3b_supported(n) == 0 || root == "" || binary == ""
    return ""
  llpath = binary + ".ll"
  "cd " + ffd3b_shell_quote(root) + " && TUNGSTEN_LL_PATH=" + ffd3b_shell_quote(llpath) + " TUNGSTEN_METAL_PATH=" + ffd3b_shell_quote(ffmc_generated_source_path(binary)) + " bin/tungsten -o " + ffd3b_shell_quote(binary) + " " + ffd3b_shell_quote(ffd3b_source_rel(n)) + " --release --native --fast --lto"

-> ffd3b_build(root, n, binary) (String i64 String) i64
  command = ffd3b_build_command(root, n, binary)
  if command == ""
    return 0
  built = system(command)
  if !built
    return 0
  ffmc_build(root, ffmc_generated_source_path(binary), binary)

-> ffd3b_metallib_path(binary) (String)
  ffmc_library_path(binary)

-> ffd3b_metallib_fresh(root, n, binary) (String i64 String) i64
  ffmc_fresh(ffmc_generated_source_path(binary), binary)

# Positional bounded worker ABI:
#   seed output walkers steps dispatches band plus_period metallib
-> ffd3b_epoch_command(root, binary, n, seed_path, output_path, walkers, steps, dispatches, band, plus_period) (String String i64 String String i64 i64 i64 i64 i64)
  if ffd3b_supported(n) == 0 || root == "" || binary == "" || seed_path == "" || output_path == ""
    return ""
  epoch_walkers = ffd3b_clamp(walkers, 1, ffd3b_max_walkers()) ## i64
  epoch_steps = ffd3b_clamp(steps, 1, ffd3b_max_steps()) ## i64
  epoch_dispatches = ffd3b_clamp(dispatches, 1, ffd3b_max_dispatches()) ## i64
  epoch_band = ffd3b_clamp(band, 0, ffd3b_cap(n) - 12) ## i64
  epoch_plus = ffd3b_clamp(plus_period, 0, 1000000000) ## i64
  "cd " + ffd3b_shell_quote(root) + " && " + ffd3b_shell_quote(binary) + " " + ffd3b_shell_quote(seed_path) + " " + ffd3b_shell_quote(output_path) + " " + epoch_walkers.to_s() + " " + epoch_steps.to_s() + " " + epoch_dispatches.to_s() + " " + epoch_band.to_s() + " " + epoch_plus.to_s() + " " + ffd3b_shell_quote(ffd3b_metallib_path(binary))

-> ffd3b_epoch(root, binary, n, seed_path, output_path, walkers, steps, dispatches, band, plus_period) (String String i64 String String i64 i64 i64 i64 i64) i64
  command = ffd3b_epoch_command(root, binary, n, seed_path, output_path, walkers, steps, dispatches, band, plus_period)
  if command == ""
    return 0
  ran = system(command)
  result = 0 ## i64
  if ran
    result = 1
  result
