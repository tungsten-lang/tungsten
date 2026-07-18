# Build and launch glue for the one-process bounded exact-move CPU pool.

use ../metallib_cache

-> ffpeb_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

-> ffpeb_build_command(root, binary) (String String)
  source = "kernels/workers/pooled_exact.w"
  "cd " + ffpeb_shell_quote(root) + " && TUNGSTEN_GPU_DIALECTS=none TUNGSTEN_LL_PATH=" + ffpeb_shell_quote(binary + ".ll") + " " + ffpeb_shell_quote(ffmc_tungsten(root)) + " compile " + ffpeb_shell_quote(source) + " --release --fast --lto --out " + ffpeb_shell_quote(binary)

-> ffpeb_build(root, binary) (String String) i64
  if system(ffpeb_build_command(root, binary))
    return 1
  0

-> ffpeb_plan_valid(n, kind, budget, nonce) (i64 i64 i64 i64) i64
  if n < 2 || n > 7
    return 0
  if kind != 1 && kind != 5 && kind != 10
    return 0
  if budget < 1 || budget > 4096 || nonce < 0
    return 0
  1

-> ffpeb_epoch_command(root, binary, seed_path, output_path, n, kind, budget, nonce) (String String String String i64 i64 i64 i64)
  if root.size() < 1 || binary.size() < 1 || seed_path.size() < 1 || output_path.size() < 1 || seed_path == output_path
    return ""
  if ffpeb_plan_valid(n, kind, budget, nonce) == 0
    return ""
  "cd " + ffpeb_shell_quote(root) + " && " + ffpeb_shell_quote(binary) + " " + ffpeb_shell_quote(seed_path) + " " + ffpeb_shell_quote(output_path) + " " + n.to_s() + " " + kind.to_s() + " " + budget.to_s() + " " + nonce.to_s()
