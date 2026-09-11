# The packaged runtime manifests must match the tree exactly: every file
# under lib/metaflip in SHA256SUMS with its current digest, every Tungsten
# source in manifests/runtime-sources.tsv, nothing stale, missing, or extra.
# Regenerate with `tungsten tools/regen_manifests.w` after changing lib/.
use ../lib/metaflip/manifest_check

root = __DIR__ + "/.."
problems = ffmf_check(root)
i = 0 ## i64
while i < problems.size()
  << "FAIL " + problems[i]
  i += 1
if problems.size() > 0
  << "metaflip runtime manifests: " + problems.size().to_s() + " failure(s)"
  exit(1)
entries = ffmf_lines(read_file(ffmf_sha256sums_path(root))).size() ## i64
<< "metaflip runtime manifests: ok (" + entries.to_s() + " files)"
