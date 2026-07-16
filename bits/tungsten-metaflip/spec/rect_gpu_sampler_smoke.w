# Optional macOS/Metal smoke for the optimized rectangular factor sampler.
# Build the newly added 2x2x9 worker from its packaged Tungsten source, inspect
# the generated MSL, and run one bounded exact-gated dispatch.

use core/system
use ../lib/metaflip/kernels/bundles/rect
use ../lib/metaflip/paths

args = argv()
root = __DIR__ + "/../lib/metaflip"
if args.size() > 0
  root = args[0]
root = ffls_canonical_dir(root)

binary = "/tmp/metaflip_rect_gpu_sampler_smoke_229"
output = "/tmp/metaflip_rect_gpu_sampler_smoke_229_best.txt"
seed = root + "/seeds/gf2/matmul_2x2x9_rank32_d156_perminov_2025_gf2.txt"

if ffrgb_geometry_valid(2, 2, 9) != 1
  << "FAIL 2x2x9 GPU geometry"
  exit(1)
if ffrgb_build(root, 2, 2, 9, binary) != 1
  << "FAIL optimized 2x2x9 GPU worker build"
  exit(1)
metal = read_file(binary + ".metal")
if metal == nil || !metal.include?("uint sample = state") || !metal.include?("277803737") || !metal.include?("while ((u1 == 0))")
  << "FAIL generated Metal does not contain unsigned PCG factor sampling"
  exit(1)
if metal.include?("u1 = (((state % 262143)")
  << "FAIL generated Metal retains divided factor sampling"
  exit(1)
if write_file(output, "") == false
  << "FAIL optimized sampler smoke output preparation"
  exit(1)

command = ffrgb_epoch_command(root, binary, 2, 2, 9, seed, output, "", 0, 1, 1, 4, 1000, 250, 7, 16, "", 16, 1)
if command == "" || !system(command)
  << "FAIL optimized sampler GPU dispatch"
  exit(1)

<< "PASS optimized rectangular PCG sampler builds and dispatches through the exact gate"
