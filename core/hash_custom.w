# Custom hash table with selectable hash function.
#
# Open-addressing with linear probing. Power-of-2 capacity. Uses
# nil-as-empty, so keys must never be nil.
#
# Hash function is selected by symbol at init time. Supported:
#
#   :splitmix64  — identity hash on WValue bits (fast for interned strings)
#
# Equality is always WValue `==` (i64 identity fast path for interned
# strings, delegated string/number compare for non-interned types).
#
# Usage:
#   h = HashCustom.new(:splitmix64, 64)
#   h.set("foo", 1)
#   v = h.get("foo")   # returns nil if not present

+ HashCustom
  -> new(hash_kind, initial_capacity) (w64 i64)
    @hash_kind = hash_kind
    @count = 0
    cap = initial_capacity
    if cap < 16
      cap = 16
    # round up to power of 2
    p = 16
    while p < cap
      p = p * 2
    @capacity = p
    @mask = p - 1
    @keys = []
    @values = []
    i = 0
    while i < p
      @keys.push(nil)
      @values.push(nil)
      i += 1

  -> hash(key) (string) i64
    v = key
    v = v ^ (v >> 30)
    v = v * 0xbf58476d1ce4e5b9
    v = v ^ (v >> 27)
    v = v * 0x94d049bb133111eb
    v = v ^ (v >> 31)
    v

  -> get(key)
    idx = hash(key) & @mask
    loop
      k = @keys[idx]
      if k == nil
        return nil
      if k == key
        return @values[idx]
      idx = (idx + 1) & @mask

  -> set(key, value)
    # Grow if load factor > 0.75
    if @count * 4 >= @capacity * 3
      grow()

    idx = hash(key) & @mask
    loop
      k = @keys[idx]
      if k == nil
        @keys[idx] = key
        @values[idx] = value
        @count += 1
        return
      if k == key
        @values[idx] = value
        return
      idx = (idx + 1) & @mask

  -> grow
    old_keys = @keys
    old_values = @values
    old_cap = @capacity
    new_cap = old_cap * 2

    new_keys = []
    new_values = []
    i = 0
    while i < new_cap
      new_keys.push(nil)
      new_values.push(nil)
      i += 1

    @keys = new_keys
    @values = new_values
    @capacity = new_cap
    @mask = new_cap - 1
    @count = 0

    i = 0
    while i < old_cap
      k = old_keys[i]
      if k != nil
        idx = hash(k) & @mask
        loop
          if @keys[idx] == nil
            @keys[idx] = k
            @values[idx] = old_values[i]
            @count += 1
            break
          idx = (idx + 1) & @mask
      i += 1

  -> length
    @count

  -> has(key)
    get(key) != nil
