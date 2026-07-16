# Build/launch glue for the bounded CPU frozen-fringe SAT child.

use ../metallib_cache

-> fffsb_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

-> fffsb_build_command(root, binary) (String String)
  source = "kernels/workers/frozen_fringe_sat.w"
  "cd " + fffsb_shell_quote(root) + " && TUNGSTEN_GPU_DIALECTS=none TUNGSTEN_LL_PATH=" + fffsb_shell_quote(binary + ".ll") + " TUNGSTEN_METAL_PATH=" + fffsb_shell_quote(ffmc_generated_source_path(binary)) + " " + fffsb_shell_quote(ffmc_tungsten(root)) + " compile " + fffsb_shell_quote(source) + " --release --fast --lto --out " + fffsb_shell_quote(binary)

-> fffsb_build(root, binary) (String String) i64
  if system(fffsb_build_command(root, binary))
    return 1
  0

-> fffsb_plan_valid(timeout_s, nonce) (i64 i64) i64
  if timeout_s < 1 || timeout_s > 86400 || nonce < 0
    return 0
  1

-> fffsb_epoch_command(root, binary, seed_path, output_path, timeout_s, nonce) (String String String String i64 i64)
  if root.size() < 1 || binary.size() < 1 || seed_path.size() < 1 || output_path.size() < 1 || seed_path == output_path
    return ""
  if fffsb_plan_valid(timeout_s, nonce) == 0
    return ""
  "cd " + fffsb_shell_quote(root) + " && " + fffsb_shell_quote(binary) + " " + fffsb_shell_quote(seed_path) + " " + fffsb_shell_quote(output_path) + " " + timeout_s.to_s() + " " + nonce.to_s()
