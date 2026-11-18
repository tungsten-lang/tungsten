# One private assumption-query lifetime. Only fresh allocations registered by
# these factories belong to the owner. Formula mirrors, stop/budget cells and
# detached result/proof arrays are borrowed and must never be registered.
# Retained local solvers retain their owner until their final retry retires.

+ WassatQueryStorage
  ro :state

  -> new
    @arrays = []
    # closed / registered payload bytes / released allocation count
    @state = i64[3]

  -> keep(value, bytes)
    state = @state ## i64[]
    raise "query storage is closed" if state[0] != 0
    @arrays.push(value)
    state[1] += bytes
    value

  # A conservative reservation charge, not a process-RSS measurement. Double
  # registered payloads for capacity slack and detached result arrays; charge
  # each registered object for headers, boxed slots and the ownership registry.
  # The fixed per-owner allowance covers the solver/configuration instances.
  -> retention_bytes
    state = @state ## i64[]
    return 0 if state[0] != 0
    4096 + 2 * state[1] + 256 * @arrays.size

  -> release
    state = @state ## i64[]
    return 0 if state[0] != 0
    state[0] = 1
    arrays = @arrays
    count = arrays.size
    @arrays = nil
    arrays.each -> (value)
      z = ccall("w_value_free_w", value)
    state[2] = count
    z = ccall("w_value_free_w", arrays)
    0

-> wassat_query_storage
  WassatQueryStorage.new

-> wassat_query_keep(owner, value, bytes)
  owner.keep(value, bytes)

-> wassat_query_i64(owner, size) (WassatQueryStorage i64) i64[]
  value = i64[size]
  wassat_query_keep(owner, value, 8 * size) if owner != nil
  value

-> wassat_query_i32(owner, size) (WassatQueryStorage i64) i32[]
  value = i32[size]
  wassat_query_keep(owner, value, 4 * size) if owner != nil
  value

-> wassat_query_i8(owner, size) (WassatQueryStorage i64) i8[]
  value = i8[size]
  wassat_query_keep(owner, value, size) if owner != nil
  value

-> wassat_query_u8(owner, size) (WassatQueryStorage i64) u8[]
  value = u8[size]
  wassat_query_keep(owner, value, size) if owner != nil
  value

-> wassat_query_box(owner)
  value = []
  wassat_query_keep(owner, value, 0) if owner != nil
  value

-> wassat_query_release(owner)
  owner.release if owner != nil

-> wassat_query_destroy(owner)
  return 0 if owner == nil
  state = owner.state
  owner.release
  # The method dispatcher inspects its receiver after a method returns.
  # Release the owner only here, after all owner methods have returned.
  z = ccall("w_value_free_w", state)
  z = ccall("w_value_free_w", owner)
  0
