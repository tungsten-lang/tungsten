# Optional macOS/Metal integration smoke for the specialized 2x2x9 lane.
# The rank-32 seed is Andrew I. Perminov's 2025 integer scheme reduced mod 2.

use core/system
use ../lib/metaflip/kernels/bundles/rect
use ../lib/metaflip/paths

args = argv()
root = __DIR__ + "/../lib/metaflip"
if args.size() > 0
  root = args[0]
root = ffls_canonical_dir(root)

binary = "/tmp/metaflip_rect_229_smoke_worker"
output = "/tmp/metaflip_rect_229_smoke_best.txt"
seed = root + "/seeds/gf2/matmul_2x2x9_rank32_d156_perminov_2025_gf2.txt"

if ffrgb_geometry_valid(2, 2, 9) != 1
  << "FAIL 2x2x9 GPU geometry"
  exit(1)
if ffrgb_build(root, 2, 2, 9, binary) != 1
  << "FAIL packaged 2x2x9 GPU worker build"
  exit(1)
if ffrgb_metallib_fresh(root, 2, 2, 9, binary) != 1
  << "FAIL packaged 2x2x9 GPU metallib"
  exit(1)
if write_file(output, "") == false
  << "FAIL 2x2x9 GPU smoke output preparation"
  exit(1)

command = ffrgb_epoch_command(root, binary, 2, 2, 9, seed, output, "", 31, 1, 1, 1, 1, 1, 1, 16, "", 1, 1)
if command == "" || !system(command)
  << "FAIL packaged 2x2x9 GPU epoch"
  exit(1)

<< "metaflip packaged 2x2x9 GPU smoke: ok"
