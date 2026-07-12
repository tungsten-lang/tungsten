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

  -> __enumerable_iteration_mode
    2

  -> __enumerable_each(block)
    each -> (key, value)
      block.call(key, value)
