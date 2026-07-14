# Offline Metal-library cache shared by FlipFleet's generated workers.
#
# Compiling MSL inside every GPU child wastes the gap between epochs and lets
# concurrent roles contend in the compiler. Build a source-fresh `.metallib`
# next to each worker executable once. Bounded engines load it at startup;
# generic/rect workers may retain it in a persistent adaptive process.

-> ffmc_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

-> ffmc_library_path(binary) (String)
  binary + ".metallib"

-> ffmc_generated_source_path(binary) (String)
  binary + ".metal"

-> ffmc_fresh(source_path, binary) (String String) i64
  cached_path = ffmc_library_path(binary)
  source_mtime = file_mtime_ns(source_path)
  library_mtime = file_mtime_ns(cached_path)
  if source_mtime == nil || library_mtime == nil
    return 0
  if library_mtime < source_mtime
    return 0
  1

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

-> ffmc_prepare(root, source_path, binary) (String String String) i64
  if ffmc_fresh(source_path, binary) == 1
    return 1
  ffmc_build(root, source_path, binary)
