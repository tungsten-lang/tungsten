# Regenerate every bundled cal2zone Metal worker from tools/cal2zone.template.
#
#   tungsten tools/gen_cal2zone.w [OUT_DIR]
#
# OUT_DIR defaults to lib/metaflip/kernels; pass a scratch directory to render
# without touching the tree.  Geometry comes from the runtime profile tables,
# so adding a shape means extending ffrp_gpu_cap / ffrp_gpu_wpg (or ffb_*) and
# re-running this script.

use cal2zone_generator

args = argv()
out_root = __DIR__ + "/../lib/metaflip/kernels"
if args.size() > 0
  out_root = args[0]
count = ffgz_write_all(__DIR__ + "/cal2zone.template", out_root) ## i64
if count < 1
  << "gen_cal2zone: rendering failed"
  exit(1)
<< "gen_cal2zone: wrote " + count.to_s() + " workers under " + out_root
