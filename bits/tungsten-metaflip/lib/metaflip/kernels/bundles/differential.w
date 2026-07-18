# Thin build/launch glue for the single-CPU cross-parent pool worker.  Keep the
# heavy surgery implementation in its own executable rather than importing
# its GPU-support libraries into the coordinator.

use ../metallib_cache

# Scoped to this one-child worker.  Ordinary archive novelty thresholds stay
# unchanged; d6 is the smallest proper component exchange worth launching.
-> ffdb_min_distance() i64
  6

-> ffdb_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

-> ffdb_build_command(root, binary) (String String)
  source = "kernels/workers/differential.w"
  "cd " + ffdb_shell_quote(root) + " && TUNGSTEN_GPU_DIALECTS=none TUNGSTEN_LL_PATH=" + ffdb_shell_quote(binary + ".ll") + " TUNGSTEN_METAL_PATH=" + ffdb_shell_quote(ffmc_generated_source_path(binary)) + " " + ffdb_shell_quote(ffmc_tungsten(root)) + " compile " + ffdb_shell_quote(source) + " --release --fast --lto --out " + ffdb_shell_quote(binary)

-> ffdb_build(root, binary) (String String) i64
  built = system(ffdb_build_command(root, binary))
  if built
    return 1
  0

-> ffdb_epoch_command(root, binary, parent_a, parent_b, output, n, pool, offset, min_distance) (String String String String String i64 i64 i64 i64)
  "cd " + ffdb_shell_quote(root) + " && " + ffdb_shell_quote(binary) + " " + ffdb_shell_quote(parent_a) + " " + ffdb_shell_quote(parent_b) + " " + ffdb_shell_quote(output) + " " + n.to_s() + " " + pool.to_s() + " " + offset.to_s() + " " + min_distance.to_s()
