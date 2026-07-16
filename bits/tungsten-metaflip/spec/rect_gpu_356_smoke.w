# Optional macOS/Metal integration smoke for the specialized 3x5x6 lane.
# It builds from the packaged pure-Tungsten source, prepares the cached
# metallib, and runs one bounded 16-lane epoch from the exact rank-68 seed.

use core/system
use ../lib/metaflip/kernels/bundles/rect
use ../lib/metaflip/paths

args = argv()
root = __DIR__ + "/../lib/metaflip"
if args.size() > 0
  root = args[0]
root = ffls_canonical_dir(root)

binary = "/tmp/metaflip_rect_356_smoke_worker"
output = "/tmp/metaflip_rect_356_smoke_best.txt"
seed = root + "/seeds/gf2/matmul_3x5x6_rank68_catalog_gf2.txt"

if ffrgb_geometry_valid(3, 5, 6) != 1
  << "FAIL 3x5x6 GPU geometry"
  exit(1)
if ffrgb_build(root, 3, 5, 6, binary) != 1
  << "FAIL packaged 3x5x6 GPU worker build"
  exit(1)
if ffrgb_metallib_fresh(root, 3, 5, 6, binary) != 1
  << "FAIL packaged 3x5x6 GPU metallib"
  exit(1)
if write_file(output, "") == false
  << "FAIL 3x5x6 GPU smoke output preparation"
  exit(1)

command = ffrgb_epoch_command(root, binary, 3, 5, 6, seed, output, "", 0, 1, 1, 1, 1, 1, 1, 16, "", 1, 1)
if command == "" || !system(command)
  << "FAIL packaged 3x5x6 GPU epoch"
  exit(1)

<< "metaflip packaged 3x5x6 GPU smoke: ok"
