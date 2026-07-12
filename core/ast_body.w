# Packed AST child-list view.
#
# The runtime freezes AST-owned polymorphic arrays into a flat arena and stores
# a compact value reference in node fields. Body is the read-only Tungsten view
# over that representation: offset occupies bits 21..44 and element count bits
# 0..20. Only the arena slot load remains a storage primitive; iteration and
# every derived collection operation come from Tungsten code.

in Tungsten:AST

+ Body
  is Enumerable

  -> size
    $value & 0x1FFFFF

  -> empty?
    ($value & 0x1FFFFF) == 0

  # Named form of `[]`, useful at dynamic call sites. Ordinary bracket syntax
  # may lower directly to the same bounds-safe runtime array reader.
  -> read(index)
    raw_index = ccall_nobox("w_numeric_to_i64", index) ## i64
    count = ($value & 0x1FFFFF) ## i64
    if raw_index < 0
      raw_index += count
    if raw_index < 0 || raw_index >= count
      return nil
    offset = (($value >> 21) & 0xFFFFFF) ## i64
    ccall_nobox("w_body_arena_get", offset, raw_index)

  -> [](index)
    read(index)

  -> each/&
    offset = (($value >> 21) & 0xFFFFFF) ## i64
    count = ($value & 0x1FFFFF) ## i64
    i = 0 ## i64
    while i < count
      item = ccall_nobox("w_body_arena_get", offset, i)
      yield item
      i += 1
    self

  # Body remains an Enumerable, but its hot combinators iterate the packed
  # arena directly. Going through Enumerable's generic callback adapter adds a
  # dynamic method call per element and defeats early-exit performance.
  -> map/& []
    offset = (($value >> 21) & 0xFFFFFF) ## i64
    count = ($value & 0x1FFFFF) ## i64
    i = 0 ## i64
    while i < count
      item = ccall_nobox("w_body_arena_get", offset, i)
      mapped = yield item
      out.push(mapped)
      i += 1

  -> select/& []
    offset = (($value >> 21) & 0xFFFFFF) ## i64
    count = ($value & 0x1FFFFF) ## i64
    i = 0 ## i64
    while i < count
      item = ccall_nobox("w_body_arena_get", offset, i)
      keep = yield item
      out.push(item) if keep
      i += 1

  -> reject/& []
    offset = (($value >> 21) & 0xFFFFFF) ## i64
    count = ($value & 0x1FFFFF) ## i64
    i = 0 ## i64
    while i < count
      item = ccall_nobox("w_body_arena_get", offset, i)
      reject_item = yield item
      out.push(item) unless reject_item
      i += 1

  -> find/&
    offset = (($value >> 21) & 0xFFFFFF) ## i64
    count = ($value & 0x1FFFFF) ## i64
    i = 0 ## i64
    while i < count
      item = ccall_nobox("w_body_arena_get", offset, i)
      found = yield item
      return item if found
      i += 1
    nil

  -> any?
    offset = (($value >> 21) & 0xFFFFFF) ## i64
    count = ($value & 0x1FFFFF) ## i64
    i = 0 ## i64
    while i < count
      bits = wvalue_bits(ccall_nobox("w_body_arena_get", offset, i)) ## i64
      return true if bits != 0 && bits != 1
      i += 1
    false

  -> any?/&
    offset = (($value >> 21) & 0xFFFFFF) ## i64
    count = ($value & 0x1FFFFF) ## i64
    i = 0 ## i64
    while i < count
      item = ccall_nobox("w_body_arena_get", offset, i)
      matched = yield item
      return true if matched
      i += 1
    false

  -> all?
    offset = (($value >> 21) & 0xFFFFFF) ## i64
    count = ($value & 0x1FFFFF) ## i64
    i = 0 ## i64
    while i < count
      bits = wvalue_bits(ccall_nobox("w_body_arena_get", offset, i)) ## i64
      return false if bits == 0 || bits == 1
      i += 1
    true

  -> all?/&
    offset = (($value >> 21) & 0xFFFFFF) ## i64
    count = ($value & 0x1FFFFF) ## i64
    i = 0 ## i64
    while i < count
      item = ccall_nobox("w_body_arena_get", offset, i)
      matched = yield item
      return false unless matched
      i += 1
    true

  -> none?
    offset = (($value >> 21) & 0xFFFFFF) ## i64
    count = ($value & 0x1FFFFF) ## i64
    i = 0 ## i64
    while i < count
      bits = wvalue_bits(ccall_nobox("w_body_arena_get", offset, i)) ## i64
      return false if bits != 0 && bits != 1
      i += 1
    true

  -> none?/&
    offset = (($value >> 21) & 0xFFFFFF) ## i64
    count = ($value & 0x1FFFFF) ## i64
    i = 0 ## i64
    while i < count
      item = ccall_nobox("w_body_arena_get", offset, i)
      matched = yield item
      return false if matched
      i += 1
    true

  -> reduce(init, &block)
    acc = init
    offset = (($value >> 21) & 0xFFFFFF) ## i64
    count = ($value & 0x1FFFFF) ## i64
    i = 0 ## i64
    while i < count
      item = ccall_nobox("w_body_arena_get", offset, i)
      acc = yield acc, item
      i += 1
    acc

  -> compact() []
    offset = (($value >> 21) & 0xFFFFFF) ## i64
    count = ($value & 0x1FFFFF) ## i64
    i = 0 ## i64
    while i < count
      item = ccall_nobox("w_body_arena_get", offset, i)
      out.push(item) if item != nil
      i += 1

  -> dup() []
    offset = (($value >> 21) & 0xFFFFFF) ## i64
    count = ($value & 0x1FFFFF) ## i64
    i = 0 ## i64
    while i < count
      out.push ccall_nobox("w_body_arena_get", offset, i)
      i += 1

  -> to_a
    dup()
