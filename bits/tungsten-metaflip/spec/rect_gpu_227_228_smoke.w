# Optional macOS/Metal integration smoke for the specialized 2x2x7 and 2x2x8
# lanes. Each worker is built from packaged Tungsten, dispatched once, and
# admitted only through its complete rectangular exact gate.

use core/system
use ../lib/metaflip/kernels/bundles/rect
use ../lib/metaflip/paths

-> ffr2278_smoke(root, p, rank, density) (String i64 i64 i64) i64
  tag = "22" + p.to_s() ## String
  binary = "/tmp/metaflip_rect_" + tag + "_smoke_worker"
  output = "/tmp/metaflip_rect_" + tag + "_smoke_best.txt"
  seed = root + "/seeds/gf2/matmul_2x2x" + p.to_s() + "_rank" + rank.to_s() + "_catalog_gf2.txt"
  if ffrgb_geometry_valid(2, 2, p) != 1
    << "FAIL " + tag + " GPU geometry"
    return 0
  if ffrgb_build(root, 2, 2, p, binary) != 1
    << "FAIL " + tag + " GPU worker build"
    return 0
  if ffrgb_metallib_fresh(root, 2, 2, p, binary) != 1
    << "FAIL " + tag + " GPU metallib"
    return 0
  if write_file(output, "") == false
    << "FAIL " + tag + " output preparation"
    return 0
  command = ffrgb_epoch_command(root, binary, 2, 2, p, seed, output, "", rank-1, 1, 1, 1, 1, 1, 1, 16, "", 1, 1)
  if command == "" || !system(command)
    << "FAIL " + tag + " GPU epoch"
    return 0
  # A one-step smoke need not improve. The seed's density is pinned by the
  # CPU profile test; keeping it in the signature makes accidental cross-wiring
  # visible at the call site.
  if density < 1
    return 0
  1

args = argv()
root = __DIR__ + "/../lib/metaflip"
if args.size() > 0
  root = args[0]
root = ffls_canonical_dir(root)

ok = ffr2278_smoke(root, 7, 25, 132) ## i64
if ok == 1
  ok = ffr2278_smoke(root, 8, 28, 160)
if ok != 1
  exit(1)
<< "metaflip packaged 2x2x7/2x2x8 GPU smokes: ok"
