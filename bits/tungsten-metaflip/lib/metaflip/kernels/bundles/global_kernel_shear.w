# Build/launch glue for the bounded 5x5 global-kernel-shear CPU child.

use ../metallib_cache
use ../build_cache

-> ffgksb_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

-> ffgksb_build_command(root, binary) (String String)
  source = "kernels/workers/global_kernel_shear.w"
  "cd " + ffgksb_shell_quote(root) + " && TUNGSTEN_GPU_DIALECTS=none TUNGSTEN_LL_PATH=" + ffgksb_shell_quote(binary + ".ll") + " TUNGSTEN_METAL_PATH=" + ffgksb_shell_quote(ffmc_generated_source_path(binary)) + " " + ffgksb_shell_quote(ffmc_tungsten(root)) + " compile " + ffgksb_shell_quote(source) + " --release --fast --lto --out " + ffgksb_shell_quote(binary)

-> ffgksb_build(root, binary) (String String) i64
  ffmk_build(root, binary, [root + "/kernels/workers/global_kernel_shear.w", root + "/kernels/global_kernel_shear.w", root + "/strategies/kernel_shear.w", root + "/strategies/tunnel.w", root + "/strategies/span_refactor.w", root + "/scheme.w"], ffgksb_build_command(root, binary), 0)

-> ffgksb_epoch_command(root, binary, seed_path, output_path, nonce) (String String String String i64)
  if root.size() < 1 || binary.size() < 1 || seed_path.size() < 1 || output_path.size() < 1 || seed_path == output_path || nonce < 0
    return ""
  "cd " + ffgksb_shell_quote(root) + " && " + ffgksb_shell_quote(binary) + " " + ffgksb_shell_quote(seed_path) + " " + ffgksb_shell_quote(output_path) + " " + nonce.to_s()
