# @resources
#   https://www.cs.utexas.edu/users/EWD/transcriptions/EWD08xx/EWD831.html
#
# Integer Range over the immediate WValue encoding (Location mode 11).
#
# Compiled receivers are packed values: $value carries the raw bits.
# Sub-mode bit 42 selects the loop shape (bit 41 start ∈ {0,1}, 40-bit
# unsigned end) or the span shape (20-bit signed start, 21-bit signed
# end); bit 0 is the exclusive flag. Values are minted by the runtime's
# w_range_imm_try funnel — bounds that do not fit the encoding fall back
# to the heap path — so methods here only ever see mode-11 receivers.
# The tree-walking interpreters intercept ranges natively and never
# dispatch into this class.
#
# Sign extension is done by compare-and-subtract, not shift pairs, and
# hot aliases carry direct bodies (no delegation) so each name stays a
# single dispatch. Decoded bounds fit i48 (end < 2^40), so `## i64`
# reads box safely on return; `sum` stays untyped so its product can
# promote past i48.

+ Range
  is Enumerable

  -> exclusive?
    ($value & 1) == 1

  -> start
    if (($value >> 42) & 1) == 0
      return ($value >> 41) & 1
    s = (($value >> 22) & 0xFFFFF) ## i64
    if s >= 524288
      return s - 1048576
    s

  -> first
    if (($value >> 42) & 1) == 0
      return ($value >> 41) & 1
    s = (($value >> 22) & 0xFFFFF) ## i64
    if s >= 524288
      return s - 1048576
    s

  # Raw upper bound as written in the literal (before exclusivity).
  -> finish
    if (($value >> 42) & 1) == 0
      return ($value >> 1) & 0xFFFFFFFFFF
    e = (($value >> 1) & 0x1FFFFF) ## i64
    if e >= 1048576
      return e - 2097152
    e

  # Largest value the range covers (exclusive bound backs off by one).
  -> last
    e = 0 ## i64
    if (($value >> 42) & 1) == 0
      e = ($value >> 1) & 0xFFFFFFFFFF
    else
      e = (($value >> 1) & 0x1FFFFF) ## i64
      if e >= 1048576
        e = e - 2097152
    if ($value & 1) == 1
      return e - 1
    e

  -> size
    a = 0 ## i64
    e = 0 ## i64
    if (($value >> 42) & 1) == 0
      a = ($value >> 41) & 1
      e = ($value >> 1) & 0xFFFFFFFFFF
    else
      a = (($value >> 22) & 0xFFFFF) ## i64
      if a >= 524288
        a = a - 1048576
      e = (($value >> 1) & 0x1FFFFF) ## i64
      if e >= 1048576
        e = e - 2097152
    if ($value & 1) == 1
      e = e - 1
    n = (e - a + 1) ## i64
    if n < 0
      return 0
    n

  -> count
    size

  -> length
    size

  -> empty?
    size == 0

  -> min
    if empty?
      return nil
    start

  -> max
    if empty?
      return nil
    last

  # Interval membership. On integer ranges this coincides with element
  # membership; fractional values inside the interval also answer true.
  -> include?(x)
    x >= start && x <= last

  -> member?(x)
    x >= start && x <= last

  # Gauss closed form. Untyped on purpose: (a + b) * n reaches ~2^80 at
  # the encoding's limits and must promote. One of n and (a + b) is
  # always even, so the halving divides exactly.
  -> sum
    a = start
    b = last
    if b < a
      return 0
    n = b - a + 1
    if n % 2 == 0
      return (n / 2) * (a + b)
    n * ((a + b) / 2)

  # Indexing compat: compiled ranges were eager Arrays before the
  # immediate encoding, so bracket reads appear in the wild. A step-1
  # integer range indexes in O(1); negative indices count from the end;
  # out-of-bounds answers nil, like Array. Direct bodies (no delegation)
  # so each name stays a single dispatch.
  -> [](index)
    n = size
    i = index
    if i < 0
      i = i + n
    if i < 0 || i >= n
      return nil
    start + i

  -> at(index)
    n = size
    i = index
    if i < 0
      i = i + n
    if i < 0 || i >= n
      return nil
    start + i

  -> each/&
    i = start
    e = last
    while i <= e
      yield i
      i += 1
    self

  -> to_a []
    i = start
    e = last
    while i <= e
      out.push(i)
      i += 1

  -> dup
    self
