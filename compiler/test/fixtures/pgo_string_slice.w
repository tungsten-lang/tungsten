# Source-controlled PGO training shape for String lowering. This deliberately
# mirrors both empty and inline slice paths without being a runtime benchmark.

fn pgo_slice(source, offset)
  piece = source.slice(offset, 5)
  piece.size()

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

source = "abcdefghijklmnop"
<< pgo_slice(source, 2)
<< pgo_slice(source, 99)
