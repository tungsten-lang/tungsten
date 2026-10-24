+ Hash
  is Enumerable

  # Mirrors runtime/runtime.h WHash — a compact dict: dense insertion-ordered
  # keys/values plus a sparse index table that takes the probing. Iteration
  # order is insertion order, guaranteed, on every engine.
  - data
    u32    count
    u32    capacity
    u8     flags
    u8     iter_depth
    u8[2]  _pad
    u32    used
    * w64[] keys
    * w64[] values
    * i32[] index

  -> __enumerable_yields_pair?
    true

  # Freezes this table and recursively freezes supported keys and values.
  # Every alias sees the same frozen header; reads and iteration remain valid.
  -> freeze
    ccall("w_freeze", self)

  -> frozen?
    ccall("w_frozen_p", self)

  # Direct WHash view-field load; the u32 count is boxed inline as an Integer.
  -> size
    $count

  -> __enumerable_iteration_mode
    2

  -> __enumerable_each(block)
    each -> (key, value)
      block.call(key, value)

  # Enumerable treats a pair-yielding collection's element as [key, value].
  # Define this directly so the interpreter's generic host include? builtin
  # cannot substitute Ruby Hash's key-membership semantics on one engine.
  -> include?(entry)
    return false if (
      type(entry) != "Array" || entry.size != 2)
    k = entry[0]
    return false if !has_key?(k)
    self[k] == entry[1]

  -> dup
    result = {}
    result.merge!(self)
    result

  # Non-destructive union: a new hash with self's entries plus other's, where
  # other wins on a key collision (Ruby Hash#merge, no-block form). The
  # receiver is untouched.
  -> merge(other)
    result = {}
    result.merge!(self)
    result.merge!(other)
    result

  # Destructive union: copy other's entries into self (other wins on
  # collision) and return self (Ruby Hash#merge! / #update).
  -> merge!(other)
    if frozen?
      raise FrozenError.new("cannot modify frozen Hash")
    ks = other.keys
    vs = other.values
    n = ks.size
    i = 0
    while i < n
      self[ks[i]] = vs[i]
      i += 1
    self

  -> update(other)
    merge!(other)

  # New hash with the same keys and each value mapped through the block.
  # Uses the anonymous `&` block form (callable as `&(...)`), which the
  # self-hosted interpreter resolves too — a named `&block` param is not
  # callable on the interp path.
  -> transform_values(&)
    result = {}
    ks = self.keys
    vs = self.values
    n = ks.size
    i = 0
    while i < n
      result[ks[i]] = &(vs[i])
      i += 1
    result

  # New hash with each key mapped through the block; values unchanged. On a
  # key collision the last-written value wins (Ruby semantics).
  -> transform_keys(&)
    result = {}
    ks = self.keys
    vs = self.values
    n = ks.size
    i = 0
    while i < n
      result[&(ks[i])] = vs[i]
      i += 1
    result

  # Predicate alias for has_key? (Ruby Hash#key?).
  -> key?(k)
    has_key?(k)

  # Value for key, or raise if absent (Ruby Hash#fetch/1).
  -> fetch(k)
    if has_key?(k)
      return self[k]
    raise "key not found: " + k.to_s

  # Value for key, or the supplied default if absent (Ruby Hash#fetch/2).
  -> fetch(k, default)
    if has_key?(k)
      return self[k]
    default

  # New hash mapping each value back to its key (Ruby Hash#invert). On
  # duplicate values the last key iterated wins.
  -> invert
    result = {}
    ks = self.keys
    vs = self.values
    n = ks.size
    i = 0
    while i < n
      result[vs[i]] = ks[i]
      i += 1
    result

  # Iterate (key, value) pairs, returning self (Ruby Hash#each_pair).
  -> each_pair(&)
    self.each -> (k, v)
      &(k, v)
    self
