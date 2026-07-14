# Native build/dispatch glue for rectangular Metal lanes.
#
# The checked-in cal2zone sources are specialized for their asymmetric
# factor widths.  In particular, plus moves mask U/V/W independently; using a
# square max-width mask here would leak nonexistent coordinates on a shorter
# rectangular axis.  The generated host relay performs deterministic full
# tensor reconstruction before it writes any candidate.

use flipfleet_metallib_cache
use flipfleet_persistent_gpu
use flipfleet_rect_profiles

-> ffrgb_supported(n, m, p) (i64 i64 i64) i64
  ok = ffrp_supported(n, m, p) ## i64
  if ffrp_gpu_cap(n, m, p) < 1
    ok = 0
  ok

-> ffrgb_tag(n, m, p) (i64 i64 i64)
  n.to_s() + m.to_s() + p.to_s()

-> ffrgb_bundle_rel()
  "benchmarks/matmul/metaflip/rect_gpu"

-> ffrgb_source_rel(n, m, p) (i64 i64 i64)
  ffrgb_bundle_rel() + "/cal2zone_" + ffrgb_tag(n, m, p) + ".w"

-> ffrgb_metal_rel(n, m, p) (i64 i64 i64)
  ffrgb_bundle_rel() + "/cal2zone_" + ffrgb_tag(n, m, p) + ".metal"

-> ffrgb_join(root, relative) (String String)
  out = relative
  if root != ""
    out = root + "/" + relative
  out

-> ffrgb_source_path(root, n, m, p) (String i64 i64 i64)
  ffrgb_join(root, ffrgb_source_rel(n, m, p))

-> ffrgb_metal_path(root, n, m, p) (String i64 i64 i64)
  ffrgb_join(root, ffrgb_metal_rel(n, m, p))

-> ffrgb_cap(n, m, p) (i64 i64 i64) i64
  ffrp_gpu_cap(n, m, p)

-> ffrgb_seedcap(n, m, p) (i64 i64 i64) i64
  ffrgb_cap(n, m, p)

-> ffrgb_wpg(n, m, p) (i64 i64 i64) i64
  ffrp_gpu_wpg(n, m, p)

-> ffrgb_shared_bytes(n, m, p) (i64 i64 i64) i64
  ffrgb_cap(n, m, p) * ffrgb_wpg(n, m, p) * 4 * 3

-> ffrgb_geometry_valid(n, m, p) (i64 i64 i64) i64
  ok = ffrgb_supported(n, m, p) ## i64
  if ffrgb_shared_bytes(n, m, p) > 32768
    ok = 0
  if ffrgb_wpg(n, m, p) < 1 || (32 % ffrgb_wpg(n, m, p)) != 0
    ok = 0
  ok

-> ffrgb_round_lanes(n, m, p, requested) (i64 i64 i64 i64) i64
  lanes = 0 ## i64
  wpg = ffrgb_wpg(n, m, p) ## i64
  if wpg > 0 && requested >= wpg
    lanes = (requested / wpg) * wpg
  lanes

-> ffrgb_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

-> ffrgb_build_command(root, n, m, p, binary) (String i64 i64 i64 String)
  if ffrgb_supported(n, m, p) == 0
    return ""
  llpath = binary + ".ll"
  "cd " + ffrgb_shell_quote(root) + " && TUNGSTEN_LL_PATH=" + ffrgb_shell_quote(llpath) + " TUNGSTEN_METAL_PATH=" + ffrgb_shell_quote(ffmc_generated_source_path(binary)) + " bin/tungsten -o " + ffrgb_shell_quote(binary) + " " + ffrgb_shell_quote(ffrgb_source_rel(n, m, p)) + " --release --native --fast --lto"

-> ffrgb_build(root, n, m, p, binary) (String i64 i64 i64 String) i64
  command = ffrgb_build_command(root, n, m, p, binary)
  if command == ""
    return 0
  built = system(command)
  if !built
    return 0
  ffmc_build(root, ffmc_generated_source_path(binary), binary)

-> ffrgb_metallib_path(binary) (String)
  ffmc_library_path(binary)

-> ffrgb_metallib_fresh(root, n, m, p, binary) (String i64 i64 i64 String) i64
  ffmc_fresh(ffmc_generated_source_path(binary), binary)

-> ffrgb_prepare_metallib(root, n, m, p, binary) (String i64 i64 i64 String) i64
  ffmc_prepare(root, ffmc_generated_source_path(binary), binary)

# Positional cal2zone ABI:
#   seed best n m p record target steps reseed margin workq wanderq wthr
#   lanes live escapes rounds metallib
#
# `rounds` bounds one scheduler epoch.  The host relay only writes `best_path`
# after a full rectangular reconstruction gate.
-> ffrgb_epoch_command(root, binary, n, m, p, seed_path, best_path, record_path, record_target, steps, reseed, margin, workq, wanderq, wthr, requested_lanes, live_path, escapes, rounds) (String String i64 i64 i64 String String String i64 i64 i64 i64 i64 i64 i64 i64 String i64 i64)
  if ffrgb_supported(n, m, p) == 0
    return ""
  lanes = ffrgb_round_lanes(n, m, p, requested_lanes) ## i64
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
  "cd " + ffrgb_shell_quote(root) + " && " + ffrgb_shell_quote(binary) + " " + ffrgb_shell_quote(seed_path) + " " + ffrgb_shell_quote(best_path) + " " + n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + ffrgb_shell_quote(record_path) + " " + record_target.to_s() + " " + epoch_steps.to_s() + " " + epoch_reseed.to_s() + " " + margin.to_s() + " " + workq.to_s() + " " + wanderq.to_s() + " " + wthr.to_s() + " " + lanes.to_s() + " " + ffrgb_shell_quote(live_path) + " " + epoch_escapes.to_s() + " " + epoch_rounds.to_s() + " " + ffrgb_shell_quote(ffrgb_metallib_path(binary))
