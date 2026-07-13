# flipfleet_gpu_bundle.w -- native build/dispatch glue for generic GPU lanes.
#
# The five checked-in cal2zone sources are already specialized for factor
# width, threadgroup scratch, capacity, and WPG.  A pure Tungsten coordinator
# uses this module to select and (if needed) compile the matching source.  No
# Python generator runs during a campaign.
#
# Role policy is deliberately elsewhere: rank, density, split, fixed-cube
# break, orbit, polarization, composition, and novelty roles all call the same
# `ffb_epoch_command` with different exact seed files and schedule values.  C3,
# cooperative SIMD, and MITM retain their dedicated native engines.

-> ffb_supported(n) (i64) i64
  ok = 0 ## i64
  if n >= 3 && n <= 7
    ok = 1
  ok

-> ffb_tag(n) (i64)
  n.to_s() + n.to_s() + n.to_s()

-> ffb_bundle_rel()
  "benchmarks/matmul/metaflip/gpu_bundle"

-> ffb_source_rel(n) (i64)
  ffb_bundle_rel() + "/cal2zone_" + ffb_tag(n) + ".w"

-> ffb_metal_rel(n) (i64)
  ffb_bundle_rel() + "/cal2zone_" + ffb_tag(n) + ".metal"

-> ffb_join(root, relative) (String String)
  out = relative
  if root != ""
    out = root + "/" + relative
  out

-> ffb_source_path(root, n) (String i64)
  ffb_join(root, ffb_source_rel(n))

-> ffb_metal_path(root, n) (String i64)
  ffb_join(root, ffb_metal_rel(n))

# Capacity includes the naive n^3 decomposition plus 32 slots of excursion
# room, so even `--seed naive` is legal for every bundled tensor.
-> ffb_cap(n) (i64) i64
  if n == 3
    return 59
  if n == 4
    return 96
  if n == 5
    return 157
  if n == 6
    return 248
  if n == 7
    return 375
  0

-> ffb_seedcap(n) (i64) i64
  ffb_cap(n)

# WPG falls only when the wider masks/capacity would exceed Metal's 32 KiB
# threadgroup-memory ceiling.  Every WPG divides the scheduler's 32-lane unit.
-> ffb_wpg(n) (i64) i64
  if n >= 3 && n <= 5
    return 16
  if n == 6
    return 4
  if n == 7
    return 2
  0

-> ffb_mask_bits(n) (i64) i64
  n * n

-> ffb_mask_bytes(n) (i64) i64
  bytes = 4 ## i64
  if ffb_mask_bits(n) > 30
    bytes = 8
  bytes

-> ffb_shared_bytes(n) (i64) i64
  ffb_cap(n) * ffb_wpg(n) * ffb_mask_bytes(n) * 3

-> ffb_geometry_valid(n) (i64) i64
  ok = ffb_supported(n) ## i64
  if ffb_shared_bytes(n) > 32768
    ok = 0
  if ffb_wpg(n) < 1 || (32 % ffb_wpg(n)) != 0
    ok = 0
  ok

-> ffb_round_lanes(n, requested) (i64 i64) i64
  lanes = 0 ## i64
  wpg = ffb_wpg(n) ## i64
  if wpg > 0 && requested >= wpg
    lanes = (requested / wpg) * wpg
  lanes

-> ffb_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

# Compiling emits a temporary .ll/.metal beside `binary`; the executable reads
# the checked-in sidecar selected above.  This keeps build products in the run
# directory and leaves the source bundle immutable during campaigns.
-> ffb_build_command(root, n, binary) (String i64 String)
  if ffb_supported(n) == 0
    return ""
  llpath = binary + ".ll"
  "cd " + ffb_shell_quote(root) + " && TUNGSTEN_LL_PATH=" + ffb_shell_quote(llpath) + " bin/tungsten -o " + ffb_shell_quote(binary) + " " + ffb_shell_quote(ffb_source_rel(n)) + " --release --native --fast --lto"

-> ffb_build(root, n, binary) (String i64 String) i64
  command = ffb_build_command(root, n, binary)
  if command == ""
    return 0
  built = system(command)
  result = 0 ## i64
  if built
    result = 1
  result

# Positional cal2zone ABI (the wrapper keeps it out of the coordinator):
#   seed best n n n record target steps reseed margin workq wanderq wthr
#   lanes live escapes rounds
#
# `rounds` bounds one adaptive scheduling epoch.  All candidates written to
# `best_path` have passed the relay's deterministic full-tensor host gate.
-> ffb_epoch_command(root, binary, n, seed_path, best_path, record_path, record_target, steps, reseed, margin, workq, wanderq, wthr, requested_lanes, live_path, escapes, rounds) (String String i64 String String String i64 i64 i64 i64 i64 i64 i64 i64 String i64 i64)
  if ffb_supported(n) == 0
    return ""
  lanes = ffb_round_lanes(n, requested_lanes) ## i64
  if lanes < 1
    return ""
  epoch_steps = steps ## i64
  if epoch_steps < 1
    epoch_steps = 1
  epoch_reseed = reseed ## i64
  if epoch_reseed < 1
    epoch_reseed = 1
  epoch_escapes = escapes ## i64
  if epoch_escapes < 1
    epoch_escapes = 1
  if epoch_escapes > lanes
    epoch_escapes = lanes
  epoch_rounds = rounds ## i64
  if epoch_rounds < 1
    epoch_rounds = 1
  "cd " + ffb_shell_quote(root) + " && " + ffb_shell_quote(binary) + " " + ffb_shell_quote(seed_path) + " " + ffb_shell_quote(best_path) + " " + n.to_s() + " " + n.to_s() + " " + n.to_s() + " " + ffb_shell_quote(record_path) + " " + record_target.to_s() + " " + epoch_steps.to_s() + " " + epoch_reseed.to_s() + " " + margin.to_s() + " " + workq.to_s() + " " + wanderq.to_s() + " " + wthr.to_s() + " " + lanes.to_s() + " " + ffb_shell_quote(live_path) + " " + epoch_escapes.to_s() + " " + epoch_rounds.to_s()
