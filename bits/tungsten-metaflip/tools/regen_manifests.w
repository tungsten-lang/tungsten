# Regenerate (default) or verify (`verify`) lib/metaflip/SHA256SUMS and
# lib/metaflip/manifests/runtime-sources.tsv from the current tree.  The mode
# is a bare word because `tungsten FILE --check` is consumed by the runner.
use ../lib/metaflip/manifest_check

root = __DIR__ + "/.."
av = argv()
if av.size() > 0 && av[0] == "verify"
  problems = ffmf_check(root)
  i = 0 ## i64
  while i < problems.size()
    << problems[i]
    i += 1
  if problems.size() > 0
    << "metaflip manifests: " + problems.size().to_s() + " problem(s); run tools/regen_manifests.w"
    exit(1)
  << "metaflip manifests: ok"
  exit(0)
z = ffmf_write(root) ## i64
<< "metaflip manifests: regenerated"
