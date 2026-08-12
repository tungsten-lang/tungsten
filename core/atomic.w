# Atomic — a native signed-i64 atomic cell.
#
# Every operation is sequentially consistent. Fetch operations return the
# value from before the update; increment/decrement return the value after the
# update. Values outside the signed-i64 range and non-Integer values raise.
+ Atomic
  -> load
    ccall("w_atomic_get", self)

  -> store(value)
    ccall("w_atomic_set", self, value)

  -> exchange(value)
    ccall("w_atomic_exchange", self, value)

  -> compare_exchange(expected, desired)
    ccall("w_atomic_cas", self, expected, desired)

  -> fetch_add(delta)
    ccall("w_atomic_add", self, delta)

  -> fetch_sub(delta)
    ccall("w_atomic_fetch_sub", self, delta)

  -> increment
    ccall("w_atomic_increment", self)

  -> decrement
    ccall("w_atomic_decrement", self)

  # Compatibility spellings retained for existing callers.
  -> get
    load()

  -> set(value)
    store(value)

  -> cas(expected, desired)
    compare_exchange(expected, desired)

  -> add(delta)
    fetch_add(delta)
