use flipfleet_block_composer

# Independent exact-certificate gate for block-composition outputs.
#
#   flipfleet-block-verify SCHEME NxMxP

# Capacity 32768 covers the current composition campaign while keeping a
# malformed or unexpectedly enormous input bounded.

av = argv()
if av.size() != 2
  << "usage: flipfleet-block-verify SCHEME NxMxP"
  exit(1)
dims_text = av[1].split("x")
if dims_text.size() != 3
  << "shape must be NxMxP"
  exit(1)
n = dims_text[0].to_i() ## i64
m = dims_text[1].to_i() ## i64
p = dims_text[2].to_i() ## i64
if n < 1 || m < 1 || p < 1
  << "shape dimensions must be positive"
  exit(1)
scheme = ffbc_load_exact(av[0], n, m, p, 32768)
if scheme == nil
  << "FAIL exact " + av[1] + " " + av[0]
  exit(1)
<< "PASS exact " + av[1] + " rank " + scheme.rank().to_s() + " " + av[0]
