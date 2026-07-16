# Optional macOS/Metal integration smoke for the three large rectangles in
# the default portfolio.  It deliberately uses Tungsten's runtime Metal
# compiler so the full-width control does not depend on an installed offline
# Metal toolchain.

use core/system
use ../lib/metaflip/kernels/bundles/rect
use ../lib/metaflip/paths

-> rect_new_source_epoch(root, binary, seed, output, n, m, p, target, lanes) (String String String String i64 i64 i64 i64 i64)
  "cd " + ffrgb_shell_quote(root) + " && " + ffrgb_shell_quote(binary) + " " + ffrgb_shell_quote(seed) + " " + ffrgb_shell_quote(output) + " " + n.to_s() + " " + m.to_s() + " " + p.to_s() + " '' " + target.to_s() + " 1 1 4 1 1 7 " + lanes.to_s() + " '' 1 1"

-> rect_new_build_and_run(root, tag, seed, n, m, p, target, lanes) (String String String i64 i64 i64 i64 i64) i64
  binary = "/tmp/metaflip_rect_" + tag + "_source_smoke_worker"
  output = "/tmp/metaflip_rect_" + tag + "_source_smoke_best.txt"
  if !system(ffrgb_build_command(root, n, m, p, binary))
    << "FAIL packaged " + tag + " GPU worker build"
    return 0
  if write_file(output, "") == false
    << "FAIL packaged " + tag + " GPU output preparation"
    return 0
  if !system(rect_new_source_epoch(root, binary, seed, output, n, m, p, target, lanes))
    << "FAIL packaged " + tag + " source-compiled GPU epoch"
    return 0
  1

args = argv()
root = __DIR__ + "/../lib/metaflip"
if args.size() > 0
  root = args[0]
root = ffls_canonical_dir(root)

if ffrgb_geometry_valid(4, 4, 6) != 1 || ffrgb_shared_bytes(4, 4, 6) != 24576
  << "FAIL 4x4x6 GPU geometry"
  exit(1)
if ffrgb_geometry_valid(4, 5, 6) != 1 || ffrgb_shared_bytes(4, 5, 6) != 29184
  << "FAIL 4x5x6 GPU geometry"
  exit(1)
if ffrgb_geometry_valid(4, 5, 7) != 1 || ffrgb_shared_bytes(4, 5, 7) != 32256
  << "FAIL 4x5x7 GPU geometry"
  exit(1)

seed446 = root + "/seeds/gf2/matmul_4x4x6_rank73_d690_gl_frontier_gf2.txt"
seed456 = root + "/seeds/gf2/matmul_4x5x6_rank90_d906_rect_portfolio_gf2.txt"
if rect_new_build_and_run(root, "446", seed446, 4, 4, 6, 72, 16) != 1
  exit(1)
if rect_new_build_and_run(root, "456", seed456, 4, 5, 6, 89, 16) != 1
  exit(1)

# The canonical 457 seed contains V masks above 2^34.  Appending an identical
# high-V pair preserves exactness at r106.  The step-zero defensive audit must
# cancel the pair and publish r104 only after device->host i64 serialization
# and exhaustive rectangular verification both succeed.
canonical457 = read_file(root + "/seeds/gf2/matmul_4x5x7_rank104_d1089_gl_frontier_gf2.txt")
if canonical457 == nil
  << "FAIL packaged 457 seed"
  exit(1)
lines = canonical457.split("\n")
augmented = "106\n"
i = 1 ## i64
while i < lines.size()
  if lines[i].size() > 0
    augmented = augmented + lines[i] + "\n"
  i += 1
high_v_term = "524320 17215801553 180619280\n"
augmented = augmented + high_v_term + high_v_term
seed457 = "/tmp/metaflip_rect_457_high_v_duplicate_seed.txt"
output457 = "/tmp/metaflip_rect_457_source_smoke_best.txt"
binary457 = "/tmp/metaflip_rect_457_source_smoke_worker"
if write_file(seed457, augmented) == false || write_file(output457, "") == false
  << "FAIL 457 full-width control preparation"
  exit(1)
if !system(ffrgb_build_command(root, 4, 5, 7, binary457))
  << "FAIL packaged 457 wide GPU worker build"
  exit(1)
if !system(rect_new_source_epoch(root, binary457, seed457, output457, 4, 5, 7, 104, 8))
  << "FAIL packaged 457 full-width GPU epoch"
  exit(1)
result457 = read_file(output457)
if result457 == nil || !result457.starts_with?("104 1089\n") || !result457.include?("21743272017")
  << "FAIL 457 full-width roundtrip gate"
  exit(1)

<< "metaflip packaged 446/456/457 GPU smoke: ok"
