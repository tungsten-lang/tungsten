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
