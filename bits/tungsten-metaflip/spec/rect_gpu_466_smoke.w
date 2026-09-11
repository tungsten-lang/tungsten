# Optional macOS/Metal integration smoke for the generated 4x6x6 lane
# (36-bit V factors, eight walkers per group).
#
# The seed is the public rank-105 frontier with its last term duplicated:
# the scheme stays exact at rank 107, the worker's step-zero duplicate audit
# cancels the pair, and the host relay may publish rank 105 only after its
# exhaustive tensor reconstruction gate.  The CPU engine then verifies the
# published file independently.

use core/system
use ../lib/metaflip/kernels/bundles/rect
use ../lib/metaflip/paths
use ../lib/metaflip/verify

# Rewrite a bundled seed (either "rank" header or "R u v w" rows) as a
# rank+2 scheme with one duplicated term; returns the original rank.
-> rect_smoke_duplicate_seed(source, target) (String String) i64
  content = read_file(source)
  if content == nil
    return 0
  lines = content.split("\n")
  body = ""
  last = ""
  rank = 0 ## i64
  i = 0
  while i < lines.size()
    parts = lines[i].split(" ")
    row = ""
    if parts.size() >= 4 && parts[0] == "R"
      row = parts[1] + " " + parts[2] + " " + parts[3]
    if parts.size() == 3
      row = parts[0] + " " + parts[1] + " " + parts[2]
    if row != ""
      body = body + row + "\n"
      last = row
      rank += 1
    i += 1
  if rank < 1
    return 0
  if write_file(target, (rank + 2).to_s() + "\n" + body + last + "\n" + last + "\n") == false
    return 0
  rank

args = argv()
root = __DIR__ + "/../lib/metaflip"
if args.size() > 0
  root = args[0]
root = ffls_canonical_dir(root)

binary = "/tmp/metaflip_rect_466_smoke_worker"
output = "/tmp/metaflip_rect_466_smoke_best.txt"
seed = "/tmp/metaflip_rect_466_smoke_seed.txt"

if ffrgb_geometry_valid(4, 6, 6) != 1 || ffrgb_wpg(4, 6, 6) != 8 || ffrgb_shared_bytes(4, 6, 6) != 30720
  << "FAIL 4x6x6 GPU geometry"
  exit(1)
if rect_smoke_duplicate_seed(root + "/" + ffrp_seed_rel(4, 6, 6), seed) != 105
  << "FAIL 4x6x6 smoke seed preparation"
  exit(1)
if ffrgb_build(root, 4, 6, 6, binary) != 1
  << "FAIL packaged 4x6x6 GPU worker build"
  exit(1)
if ffrgb_metallib_fresh(root, 4, 6, 6, binary) != 1
  << "FAIL packaged 4x6x6 GPU metallib"
  exit(1)
if write_file(output, "") == false
  << "FAIL 4x6x6 GPU smoke output preparation"
  exit(1)

command = ffrgb_epoch_command(root, binary, 4, 6, 6, seed, output, "", 104, 1, 1, 4, 1, 1, 7, 8, "", 1, 1)
if command == "" || !system(command)
  << "FAIL packaged 4x6x6 GPU epoch"
  exit(1)
result = read_file(output)
if result == nil || !result.starts_with?("105 ")
  << "FAIL 4x6x6 duplicate cancellation did not publish rank 105"
  exit(1)
if metaflip_verify_rect(output, 4, 6, 6) != 1
  << "FAIL 4x6x6 published scheme is not exact"
  exit(1)

<< "metaflip packaged 4x6x6 GPU smoke: ok"
