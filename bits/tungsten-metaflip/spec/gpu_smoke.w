# Optional macOS/Metal integration smoke. It builds one packaged 3x3 worker,
# prepares its cached metallib, and runs a single 16-lane bounded epoch.

use core/system
use ../lib/metaflip/kernels/bundles/generic
use ../lib/metaflip/paths

args = argv()
root = __DIR__ + "/../lib/metaflip"
if args.size() > 0
  root = args[0]
root = ffls_canonical_dir(root)

binary = "/tmp/metaflip_gpu_smoke_worker"
output = "/tmp/metaflip_gpu_smoke_best.txt"
seed = root + "/seeds/gf2/matmul_3x3_rank23_d139_gf2.txt"

if ffb_build(root, 3, binary) != 1
  << "FAIL packaged generic GPU worker build"
  exit(1)
if ffb_metallib_fresh(root, 3, binary) != 1
  << "FAIL packaged generic GPU metallib"
  exit(1)
if write_file(output, "") == false
  << "FAIL GPU smoke output preparation"
  exit(1)

command = ffb_epoch_command(root, binary, 3, seed, output, "", 0, 1, 1, 1, 1, 1, 1, 16, "", 1, 1)
if command == "" || !system(command)
  << "FAIL packaged generic GPU epoch"
  exit(1)

<< "metaflip packaged GPU smoke: ok"
