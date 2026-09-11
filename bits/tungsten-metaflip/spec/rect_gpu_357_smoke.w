# Optional macOS/Metal integration smoke for the generated 3x5x7 lane
# (35-bit V factors, eight walkers per group).
#
# The seed is the public rank-79 frontier with its last term duplicated:
# the scheme stays exact at rank 81, the worker's step-zero duplicate audit
# cancels the pair, and the host relay may publish rank 79 only after its
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

binary = "/tmp/metaflip_rect_357_smoke_worker"
output = "/tmp/metaflip_rect_357_smoke_best.txt"
seed = "/tmp/metaflip_rect_357_smoke_seed.txt"

if ffrgb_geometry_valid(3, 5, 7) != 1 || ffrgb_wpg(3, 5, 7) != 8 || ffrgb_shared_bytes(3, 5, 7) != 24576
  << "FAIL 3x5x7 GPU geometry"
  exit(1)
if rect_smoke_duplicate_seed(root + "/" + ffrp_seed_rel(3, 5, 7), seed) != 79
  << "FAIL 3x5x7 smoke seed preparation"
  exit(1)
if ffrgb_build(root, 3, 5, 7, binary) != 1
  << "FAIL packaged 3x5x7 GPU worker build"
  exit(1)
if ffrgb_metallib_fresh(root, 3, 5, 7, binary) != 1
  << "FAIL packaged 3x5x7 GPU metallib"
  exit(1)
if write_file(output, "") == false
  << "FAIL 3x5x7 GPU smoke output preparation"
  exit(1)

command = ffrgb_epoch_command(root, binary, 3, 5, 7, seed, output, "", 78, 1, 1, 4, 1, 1, 7, 8, "", 1, 1)
if command == "" || !system(command)
  << "FAIL packaged 3x5x7 GPU epoch"
  exit(1)
result = read_file(output)
if result == nil || !result.starts_with?("79 ")
  << "FAIL 3x5x7 duplicate cancellation did not publish rank 79"
  exit(1)
if metaflip_verify_rect(output, 3, 5, 7) != 1
  << "FAIL 3x5x7 published scheme is not exact"
  exit(1)

<< "metaflip packaged 3x5x7 GPU smoke: ok"
