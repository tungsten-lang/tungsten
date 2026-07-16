# macOS/Metal regression: an offline-toolchain failure must retain a healthy
# rectangular GPU engine when the generated MSL can compile at runtime.
# Run with spec/fixtures/offline-metal-failure prepended to PATH.

use core/system
use ../lib/metaflip/kernels/bundles/rect
use ../lib/metaflip/paths

args = argv()
root = __DIR__ + "/../lib/metaflip"
if args.size() > 0
  root = args[0]
root = ffls_canonical_dir(root)

binary = "/tmp/metaflip_rect_runtime_fallback_446"
output = "/tmp/metaflip_rect_runtime_fallback_446_best.txt"
seed = root + "/seeds/gf2/matmul_4x4x6_rank73_d690_gl_frontier_gf2.txt"
z = system("rm -f " + ffrgb_shell_quote(binary) + " " + ffrgb_shell_quote(binary + ".metal") + " " + ffrgb_shell_quote(binary + ".metallib") + " " + ffrgb_shell_quote(output))

if ffrgb_build(root, 4, 4, 6, binary) != 1
  << "FAIL runtime-source bundle build"
  exit(1)
if ffrgb_gpu_artifact_ready(root, 4, 4, 6, binary) != 1
  << "FAIL runtime-source artifact readiness"
  exit(1)
if ffrgb_metallib_fresh(root, 4, 4, 6, binary) != 0
  << "FAIL offline-failure fixture unexpectedly produced a metallib"
  exit(1)
if write_file(output, "") == false
  << "FAIL output preparation"
  exit(1)

command = ffrgb_epoch_command(root, binary, 4, 4, 6, seed, output, "", 72, 1, 1, 4, 1, 1, 7, 16, "", 1, 1)
if command == "" || !command.ends_with?(" ''")
  << "FAIL source fallback did not preserve empty metallib ABI"
  exit(1)
if !system(command)
  << "FAIL runtime MSL compilation/dispatch"
  exit(1)

# A missing/empty sibling source remains a hard build failure even in forced
# fallback mode.  This protects the distinction between host-toolchain gaps
# and broken compiler/package artifacts.
bad_binary = "/tmp/metaflip_runtime_fallback_missing"
bad_source = bad_binary + ".metal"
z = system("rm -f " + ffrgb_shell_quote(bad_binary) + " " + ffrgb_shell_quote(bad_source) + " " + ffrgb_shell_quote(bad_binary + ".metallib"))
if write_file(bad_binary, "not-an-executable") == false || write_file(bad_source, "") == false
  << "FAIL missing-source control preparation"
  exit(1)
if ffmc_ready(bad_source, bad_binary) != 0
  << "FAIL empty runtime source accepted"
  exit(1)
if ffmc_build_or_source(root, bad_source, bad_binary) != 0
  << "FAIL missing runtime source masked as healthy"
  exit(1)

<< "metaflip offline-failure runtime-MSL fallback smoke: ok"
