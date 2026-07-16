# Offline Metal-library cache shared by Metaflip's generated workers.
#
# Compiling MSL inside every GPU child wastes the gap between epochs and lets
# concurrent roles contend in the compiler. Build a source-fresh `.metallib`
# next to each worker executable once. Bounded engines load it at startup;
# generic/rect workers may retain it in a persistent adaptive process.

use core/system
use ../paths

-> ffmc_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

-> ffmc_library_path(binary) (String)
  binary + ".metallib"

-> ffmc_generated_source_path(binary) (String)
  binary + ".metal"

# Resolve the compiler independently of the package/resource root.  A fleet
# installed as a bit must not assume that its compiler lives under `bin/` in
# the same tree.  Keep the monorepo-relative probe as a development fallback,
# after explicit environment overrides and before PATH lookup.
-> ffmc_tungsten(root) (String)
  candidate = env("METAFLIP_TUNGSTEN")
  if candidate != nil && candidate != ""
    return candidate
  candidate = env("TUNGSTEN_BIN")
  if candidate != nil && candidate != ""
    return candidate
  candidate = env("TUNGSTEN")
  if candidate != nil && candidate != ""
    return candidate
  tungsten_root = env("TUNGSTEN_ROOT")
  if tungsten_root != nil && tungsten_root != ""
    candidate = tungsten_root + "/bin/tungsten"
    if system("test -x " + ffmc_shell_quote(candidate))
      return candidate
  canonical_root = ffls_canonical_dir(root)
  if canonical_root != ""
    candidate = canonical_root + "/../../../../bin/tungsten"
    if system("test -x " + ffmc_shell_quote(candidate))
      return candidate
  candidate = capture("command -v tungsten 2>/dev/null").strip()
  if candidate != ""
    return candidate
  candidate = capture("command -v tungsten-compiler 2>/dev/null").strip()
  if candidate != ""
    return candidate
  "tungsten"

-> ffmc_fresh(source_path, binary) (String String) i64
  cached_path = ffmc_library_path(binary)
  source_mtime = file_mtime_ns(source_path)
  library_mtime = file_mtime_ns(cached_path)
  if source_mtime == nil || library_mtime == nil
    return 0
  if library_mtime < source_mtime
    return 0
  1

# Generated MSL is a second, fully supported cache tier.  Standalone Xcode
# installations sometimes expose Metal at runtime while the offline `metal`
# driver is absent (or `xcrun -sdk macosx metal` is only a rejecting stub).
# Every generated worker already knows how to compile its sibling `.metal`
# source through Metal.framework, so do not confuse that host-tooling gap with
# an unavailable GPU engine.
-> ffmc_runtime_source_ready(source_path, binary) (String String) i64
  if file_mtime_ns(binary) == nil || file_mtime_ns(source_path) == nil
    return 0
  source_size = file_size(source_path)
  if source_size == nil || source_size < 1
    return 0
  1

# Dispatch readiness additionally ties both compiler outputs to the checked-in
# worker source.  This prevents a surviving sibling `.metal` from masking a
# source update when the executable was rebuilt incompletely.
-> ffmc_artifact_ready(worker_source_path, source_path, binary) (String String String) i64
  worker_mtime = file_mtime_ns(worker_source_path)
  source_mtime = file_mtime_ns(source_path)
  binary_mtime = file_mtime_ns(binary)
  if worker_mtime == nil || source_mtime == nil || binary_mtime == nil
    return 0
  if source_mtime < worker_mtime || binary_mtime < worker_mtime
    return 0
  ffmc_ready(source_path, binary)

# Deterministic diagnostic/test switch.  It also provides a useful escape
# hatch on hosts whose offline toolchain is installed but broken.  Runtime MSL
# compilation remains subject to the worker's normal process failure and
# exact-candidate telemetry.
-> ffmc_force_runtime_source() i64
  forced = env("METAFLIP_FORCE_RUNTIME_MSL")
  if forced == "1" || forced == "true" || forced == "yes"
    return 1
  0

# 0 = unavailable, 1 = runtime-source fallback, 2 = cached metallib.
-> ffmc_mode(source_path, binary) (String String) i64
  if ffmc_force_runtime_source() == 0 && ffmc_fresh(source_path, binary) == 1
    return 2
  if ffmc_runtime_source_ready(source_path, binary) == 1
    return 1
  0

-> ffmc_ready(source_path, binary) (String String) i64
  if ffmc_mode(source_path, binary) > 0
    return 1
  0

-> ffmc_mode_name(source_path, binary) (String String)
  mode = ffmc_mode(source_path, binary) ## i64
  if mode == 2
    return "metallib"
  if mode == 1
    return "runtime-source"
  "unavailable"

# Passing an absent path to `metal_load_library` is a hard error.  Emit an
# empty positional argument in source mode so each worker takes its existing
# `metal_compile_source` branch instead.
-> ffmc_launch_library(source_path, binary) (String String)
  if ffmc_mode(source_path, binary) == 2
    return ffmc_library_path(binary)
  ""

# Standalone CommandLineTools can expose a downloaded Metal toolchain through
# `xcrun --find` while rejecting `xcrun -sdk macosx metal`. Resolve both tools
# first and invoke the exact returned paths.
-> ffmc_build_command(root, source_path, binary) (String String String)
  cached_path = ffmc_library_path(binary)
  command = "cd " + ffmc_shell_quote(root)
  command = command + " && METAL_TOOL=$(xcrun --find metal)"
  command = command + " && METALLIB_TOOL=$(xcrun --find metallib)"
  # PID-suffixed temporaries let two campaigns prepare the same cache without
  # clobbering each other's AIR file. The final rename remains atomic.
  command = command + " && AIR_TMP=" + ffmc_shell_quote(binary + ".air.tmp.") + "$$"
  command = command + " && LIBRARY_TMP=" + ffmc_shell_quote(cached_path + ".tmp.") + "$$"
  command = command + " && trap 'rm -f \"$AIR_TMP\" \"$LIBRARY_TMP\"' EXIT"
  command = command + " && \"$METAL_TOOL\" -w -O3 -c " + ffmc_shell_quote(source_path) + " -o \"$AIR_TMP\""
  command = command + " && \"$METALLIB_TOOL\" \"$AIR_TMP\" -o \"$LIBRARY_TMP\""
  command = command + " && mv \"$LIBRARY_TMP\" " + ffmc_shell_quote(cached_path)
  command

-> ffmc_build(root, source_path, binary) (String String String) i64
  built = system(ffmc_build_command(root, source_path, binary))
  if built
    if ffmc_fresh(source_path, binary) == 1
      return 1
  0

# Bundle builds need a dispatch-ready worker, not necessarily an offline
# library.  Keep the strict `ffmc_build`/`ffmc_prepare` cache APIs intact so a
# later healthy toolchain can still populate the faster cache tier.
-> ffmc_build_or_source(root, source_path, binary) (String String String) i64
  forced = ffmc_force_runtime_source() ## i64
  if forced == 0
    if ffmc_build(root, source_path, binary) == 1
      return 1
  if ffmc_runtime_source_ready(source_path, binary) == 1
    reason = "offline-build-failed"
    if forced != 0
      reason = "forced"
    << "METAFLIP_METAL_CACHE mode=runtime-source reason=" + reason + " binary=" + binary
    return 1
  << "METAFLIP_METAL_CACHE mode=unavailable reason=missing-runtime-source binary=" + binary
  0

-> ffmc_prepare(root, source_path, binary) (String String String) i64
  if ffmc_fresh(source_path, binary) == 1
    return 1
  ffmc_build(root, source_path, binary)
