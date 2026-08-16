# Source-controlled PGO training shape for protected numeric lowering. Keep it
# compact: this file trains compiler branches and is never a runtime benchmark.

fn pgo_numeric(seed)
  wide = (1 << 4096) + seed ## big
  i = 0 ## i64
  while i < 32
    wide += i
    wide = (wide * 3) / 3
    wide ^= 1 << (i & 63)
    i += 1
  wide % 1000000007

Tungsten.PROTECT_THE_CORE!
Tungsten.STOP_THE_PRESS!
Tungsten.LOCK_THE_DOORS!

<< pgo_numeric(41)
