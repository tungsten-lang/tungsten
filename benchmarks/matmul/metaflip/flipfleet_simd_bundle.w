# flipfleet_simd_bundle.w -- pure-Tungsten cooperative SIMD GPU bundle.
#
# Each checked-in worker assigns one decomposition trajectory to one 32-lane
# Metal SIMD-group.  The Python specializer is a development tool only; a
# campaign builds and runs these immutable Tungsten/Metal assets directly.
#
# One epoch is deliberately finite.  `ffsimd_epoch_command` rejects an absent
# lane allocation and any step/dispatch schedule that could overflow the i32
# per-trajectory counters.  The worker writes a candidate only after its host
# exhaustively reconstructs every tensor coefficient over GF(2).

-> ffsimd_supported(n) (i64) i64
  ok = 0 ## i64
  if n >= 3 && n <= 7
    ok = 1
  ok

-> ffsimd_tag(n) (i64)
  n.to_s() + n.to_s() + n.to_s()

-> ffsimd_bundle_rel()
  "benchmarks/matmul/metaflip/simd_bundle"

-> ffsimd_source_rel(n) (i64)
  ffsimd_bundle_rel() + "/simdgroup_" + ffsimd_tag(n) + ".w"

-> ffsimd_metal_rel(n) (i64)
  ffsimd_bundle_rel() + "/simdgroup_" + ffsimd_tag(n) + ".metal"

-> ffsimd_join(root, relative) (String String)
  out = relative
  if root != ""
    out = root + "/" + relative
  out

-> ffsimd_source_path(root, n) (String i64)
  ffsimd_join(root, ffsimd_source_rel(n))

-> ffsimd_metal_path(root, n) (String i64)
  ffsimd_join(root, ffsimd_metal_rel(n))

# These capacities fit the naive n^3 decomposition plus at least twelve escape
# slots and are rounded to eight for efficient buffer layout.
-> ffsimd_cap(n) (i64) i64
  if n == 3
    return 40
  if n == 4
    return 80
  if n == 5
    return 144
  if n == 6
    return 232
  if n == 7
    return 360
  0

-> ffsimd_mask_bytes(n) (i64) i64
  bytes = 4 ## i64
  if n * n > 30
    bytes = 8
  bytes

-> ffsimd_hash_size(n) (i64) i64
  size = 256 ## i64
  if ffsimd_mask_bytes(n) == 8
    size = 512
  size

# Measured mode selection: cooperative scan wins through 5x5; maintained hash
# chains win once rank and factor width reach 6x6.
-> ffsimd_mode(n) (i64) i64
  if n >= 3 && n <= 5
    return 0
  if n >= 6 && n <= 7
    return 1
  -1

# Includes all scheme scratch plus the emitter's two 32-element reduction
# arrays (one float and one i32).
-> ffsimd_shared_bytes(n) (i64) i64
  cap = ffsimd_cap(n) ## i64
  mask_bytes = ffsimd_mask_bytes(n) ## i64
  hash_size = ffsimd_hash_size(n) ## i64
  3 * cap * mask_bytes + 6 * mask_bytes + 4 * (3 * hash_size + 3 * cap) + 256

-> ffsimd_geometry_valid(n) (i64) i64
  ok = ffsimd_supported(n) ## i64
  if ffsimd_cap(n) < n * n * n + 12
    ok = 0
  if ffsimd_shared_bytes(n) > 32768
    ok = 0
  ok

# Adaptive policy accounts in hardware lanes.  A cooperative trajectory is
# indivisible, so allocations round down to whole 32-lane SIMD-groups.
-> ffsimd_round_lanes(requested) (i64) i64
  lanes = 0 ## i64
  if requested >= 32
    lanes = (requested / 32) * 32
  lanes

-> ffsimd_groups_for_lanes(requested) (i64) i64
  ffsimd_round_lanes(requested) / 32

-> ffsimd_shell_quote(value) (String)
  "'" + value.replace("'", "'\"'\"'") + "'"

-> ffsimd_build_command(root, n, binary) (String i64 String)
  if ffsimd_supported(n) == 0
    return ""
  llpath = binary + ".ll"
  "cd " + ffsimd_shell_quote(root) + " && TUNGSTEN_LL_PATH=" + ffsimd_shell_quote(llpath) + " bin/tungsten -o " + ffsimd_shell_quote(binary) + " " + ffsimd_shell_quote(ffsimd_source_rel(n)) + " --release --native --fast --lto"

-> ffsimd_build(root, n, binary) (String i64 String) i64
  command = ffsimd_build_command(root, n, binary)
  if command == ""
    return 0
  built = system(command)
  result = 0 ## i64
  if built
    result = 1
  result

-> ffsimd_epoch_valid(requested_lanes, steps, dispatches, margin) (i64 i64 i64 i64) i64
  ok = 1 ## i64
  if ffsimd_round_lanes(requested_lanes) < 32
    ok = 0
  if steps < 1 || dispatches < 1 || margin < 0
    ok = 0
  if steps > 2000000000 || dispatches > 2000000000
    ok = 0
  if steps > 0 && dispatches > 0
    if steps * dispatches > 2000000000
      ok = 0
  ok

# Positional worker ABI:
#   seed output groups steps dispatches margin fixed_mode
#
# `requested_lanes` is the scheduler allocation, while `groups` is the number
# of independent cooperative trajectories.  `dispatches` is the hard epoch
# boundary; the native coordinator can then reallocate the lane portfolio.
-> ffsimd_epoch_command(root, binary, n, seed_path, best_path, requested_lanes, steps, dispatches, margin) (String String i64 String String i64 i64 i64 i64)
  if ffsimd_supported(n) == 0
    return ""
  if ffsimd_epoch_valid(requested_lanes, steps, dispatches, margin) == 0
    return ""
  groups = ffsimd_groups_for_lanes(requested_lanes) ## i64
  "cd " + ffsimd_shell_quote(root) + " && " + ffsimd_shell_quote(binary) + " " + ffsimd_shell_quote(seed_path) + " " + ffsimd_shell_quote(best_path) + " " + groups.to_s() + " " + steps.to_s() + " " + dispatches.to_s() + " " + margin.to_s() + " " + ffsimd_mode(n).to_s()

-> ffsimd_epoch(root, binary, n, seed_path, best_path, requested_lanes, steps, dispatches, margin) (String String i64 String String i64 i64 i64 i64) i64
  command = ffsimd_epoch_command(root, binary, n, seed_path, best_path, requested_lanes, steps, dispatches, margin)
  if command == ""
    return 0
  ran = system(command)
  result = 0 ## i64
  if ran
    result = 1
  result
