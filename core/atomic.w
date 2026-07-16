# Atomic — a native signed-i64 atomic cell.
+ Atomic
  -> increment
    ccall("w_atomic_increment", self)

  -> decrement
    ccall("w_atomic_decrement", self)
