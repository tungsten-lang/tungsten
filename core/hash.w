+ Hash
  is Enumerable

  - data
    u32    count
    u32    capacity
    u8     flags
    u8[7]  _pad
    * w64[] keys
    * w64[] values

  -> __enumerable_yields_pair?
    true

  # Direct WHash view-field load; the u32 count is boxed inline as an Integer.
  -> size
    $count

  -> __enumerable_iteration_mode
    2

  -> __enumerable_each(block)
    each -> (key, value)
      block.call(key, value)

  # Non-destructive union: a new hash with self's entries plus other's, where
  # other wins on a key collision (Ruby Hash#merge, no-block form). The
  # receiver is untouched.
  -> merge(other)
    result = {}
    self.each -> (k, v)
      result[k] = v
    other.each -> (k, v)
      result[k] = v
    result

  # Destructive union: copy other's entries into self (other wins on
  # collision) and return self (Ruby Hash#merge! / #update).
  -> merge!(other)
    other.each -> (k, v)
      self[k] = v
    self

  -> update(other)
    merge!(other)

  # New hash with the same keys and each value mapped through the block.
  # Uses the anonymous `&` block form (callable as `&(...)`), which the
  # self-hosted interpreter resolves too — a named `&block` param is not
  # callable on the interp path.
  -> transform_values(&)
    result = {}
    self.each -> (k, v)
      result[k] = &(v)
    result

  # New hash with each key mapped through the block; values unchanged. On a
  # key collision the last-written value wins (Ruby semantics).
  -> transform_keys(&)
    result = {}
    self.each -> (k, v)
      result[&(k)] = v
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
    self.each -> (k, v)
      result[v] = k
    result

  # Iterate (key, value) pairs, returning self (Ruby Hash#each_pair).
  -> each_pair(&)
    self.each -> (k, v)
      &(k, v)
    self
