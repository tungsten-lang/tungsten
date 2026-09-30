# Bit-level helpers for GF(2) matrix masks.
#
# A mask is a non-negative Integer of any size (the language promotes to BigInt
# past 47 bits, and every helper here is exact for such values). A matrix is
# packed row-major: bit `row * cols + col` is entry (row, col). Bit 0 is the
# least significant bit.
#
# The stdlib has no popcount or set-bit iteration for arbitrary-size Integers;
# this file supplies them, plus the conversion between an Integer mask and the
# 64-bit limb arrays (`i64[]`, little-endian, limb j = bits 64j..64j+63) that
# the exactness gates in packed.w run on.
#
#   Python original               Tungsten
#   ----------------------------  ------------------------------------------
#   list(bits(x))                 Bits.positions(x)              ascending
#   popcount(x)                   Bits.popcount(x)
#   (x & -x).bit_length() - 1     Bits.low_bit_index(x)          -1 for 0
#   x.bit_length() - 1            Bits.high_bit_index(x)         -1 for 0
#   remap(x, tab)                 Bits.remap(x, tab)
#   T(x, R, C)                    Bits.transpose(x, R, C)
#   sum(1 << b for b in ...)      Bits.from_positions(list)
#   f"{x:x}", int(s, 16)          Bits.to_hex(x), Bits.parse_hex(s, 0, s.size)
#
# Integer <-> limbs (an Integer never leaves the boxed lane, so these two are
# deliberately UNTYPED: typed integer locals wrap at 64 bits on the compiled
# engine, which is exactly what a wide mask must not do):
#
#   Bits.to_limbs(x, limbs, offset, words)    store x into limbs[offset ...]
#   Bits.from_limbs(limbs, offset, words)     the Integer stored there
#
# Storing a BigInt into an `i64[]` slot keeps its low 64 bits, so extracting a
# limb is just `limbs[k] = x` followed by `x = x >> 64`, on both engines.
#
# Hexadecimal text (the MFW1 spelling of a mask) is lowercase, without leading
# zeros; `Bits.hex_run`/`Bits.hex_limb` are the typed byte scanners the MFW1
# readers are built from.
#
# Memory: compiled Tungsten has no garbage collector, and the compiler only frees
# values it can prove never escape, which excludes every array or string handed to
# another function. A loop that verifies a thousand certificates therefore
# releases its large temporaries itself: `Bits.release(value)` frees an array,
# string or BigInt the caller owns exclusively (and does not touch again).

use core/bit_ops

+ Metaflip:Gf2:Bits
  # ---- memory ----------------------------------------------------------------

  # Frees a heap value (i64[] / Array / String / BigInt) that the caller owns
  # exclusively and will not use again; a no-op for inline integers and short
  # strings. Never call it on a value another object may still reference. The
  # tree-walking interpreter has no such runtime call (it raises, and the
  # rescue turns that into a no-op); the guard costs a few nanoseconds compiled.
  -> .release(value)
    begin
      ccall("w_value_free_w", value)
    rescue e
      nil
    nil

  # ---- geometry --------------------------------------------------------------

  # ceil(bits / 64), never below 1: the limbs of a mask `bits` wide.
  -> .limbs_for(bits) (i64) i64
    words = (bits + 63) / 64 ## i64
    if words < 1
      words = 1
    words

  # ---- queries ---------------------------------------------------------------
  #
  # Every loop below walks a mask 64 bits at a time with `rest = rest >> 64`.
  # Each shift allocates a BigInt that nothing frees, so the loops release their
  # own intermediates (never the caller's x): the walk costs no memory and, with
  # the runtime's BigInt recycler, is several times faster than leaking.

  # Number of set bits.
  -> .popcount(x)
    raise "mask must be non-negative" if x < 0
    total = 0
    rest = x
    owned = false
    while rest != 0
      total += BitOps.count_ones_u64(rest)
      nxt = rest >> 64
      Metaflip:Gf2:Bits.release(rest) if owned
      owned = true
      rest = nxt
    total

  # Index of the lowest set bit, or -1 for 0.
  -> .low_bit_index(x)
    raise "mask must be non-negative" if x < 0
    return -1 if x == 0
    base = 0
    rest = x
    owned = false
    while true
      zeros = BitOps.trailing_zeros_u64(rest)
      if zeros < 64
        Metaflip:Gf2:Bits.release(rest) if owned
        return base + zeros
      nxt = rest >> 64
      Metaflip:Gf2:Bits.release(rest) if owned
      owned = true
      rest = nxt
      base += 64

  # Index of the highest set bit (bit_length - 1), or -1 for 0.
  -> .high_bit_index(x)
    raise "mask must be non-negative" if x < 0
    return -1 if x == 0
    base = 0
    rest = x
    owned = false
    while true
      nxt = rest >> 64
      if nxt == 0
        top = base + 63 - BitOps.leading_zeros_u64(rest)
        Metaflip:Gf2:Bits.release(rest) if owned
        return top
      Metaflip:Gf2:Bits.release(rest) if owned
      owned = true
      rest = nxt
      base += 64

  # Appends the indices of the set bits among the low 64 bits of `limb`,
  # ascending, offset by base. It works on the two 32-bit halves so that the
  # answer is the same whether the engine wraps a wide argument to i64 on the
  # way in (compiled) or hands it over unchanged (tree-walking interpreter).
  -> .limb_positions(limb, base, out) (i64 i64 Array) i64
    count = 0 ## i64
    half = limb & 4294967295 ## i64
    while half != 0
      out.push(base + BitOps.trailing_zeros_u64(half))
      half = half & (half - 1)
      count += 1
    half = (limb >> 32) & 4294967295
    while half != 0
      out.push(base + 32 + BitOps.trailing_zeros_u64(half))
      half = half & (half - 1)
      count += 1
    count

  # The indices of the set bits, ascending: Python's `list(bits(x))`.
  -> .positions(x)
    raise "mask must be non-negative" if x < 0
    out = []
    base = 0
    rest = x
    owned = false
    while rest != 0
      Metaflip:Gf2:Bits.limb_positions(rest, base, out)
      nxt = rest >> 64
      Metaflip:Gf2:Bits.release(rest) if owned
      owned = true
      rest = nxt
      base += 64
    out

  # ---- building masks --------------------------------------------------------

  # The limb with only bit (index mod 64) set. (Typed base: a literal `1 << n`
  # takes the promoting BigInt lane even inside a typed function, allocating and
  # leaking for every shift of 47 or more.)
  -> .bit_mask(index) (i64) i64
    one = 1 ## i64
    one << (index & 63)

  # Sets bit b in a limb array.
  -> .set_bit(limbs, b) (i64[] i64) i64
    limbs[b >> 6] = limbs[b >> 6] | Metaflip:Gf2:Bits.bit_mask(b)
    b

  # The mask with exactly the given bit indices set (duplicates collapse).
  -> .from_positions(list)
    top = -1
    list.each -> (b)
      raise "bit index must be non-negative" if b < 0
      top = b if b > top
    return 0 if top < 0
    limbs = i64[top / 64 + 1]
    list.each -> (b)
      Metaflip:Gf2:Bits.set_bit(limbs, b)
    x = Metaflip:Gf2:Bits.from_limbs(limbs, 0, limbs.size)
    Metaflip:Gf2:Bits.release(limbs)
    x

  # Moves every set bit b to table[b] (an Array or i64[] indexed by bit).
  -> .remap(x, table)
    positions = Metaflip:Gf2:Bits.positions(x)
    moved = positions.map -> (b) table[b]
    result = Metaflip:Gf2:Bits.from_positions(moved)
    Metaflip:Gf2:Bits.release(positions)
    Metaflip:Gf2:Bits.release(moved)
    result

  # Transposes x viewed as a rows x cols bit matrix: bit r*cols+c -> c*rows+r.
  -> .transpose(x, rows, cols)
    positions = Metaflip:Gf2:Bits.positions(x)
    moved = positions.map -> (b) (b % cols) * rows + b / cols
    result = Metaflip:Gf2:Bits.from_positions(moved)
    Metaflip:Gf2:Bits.release(positions)
    Metaflip:Gf2:Bits.release(moved)
    result

  # ---- Integer <-> limbs -----------------------------------------------------

  # Stores x into limbs[offset, offset + words) and returns the limbs used
  # (0 for x == 0). The slots beyond the used ones are NOT touched, so pass a
  # zeroed array (`i64[n]` is). Raises when x needs more than `words` limbs.
  -> .to_limbs(x, limbs, offset, words)
    raise "mask must be non-negative" if x < 0
    used = 0
    rest = x
    owned = false
    while rest != 0
      if used >= words
        Metaflip:Gf2:Bits.release(rest) if owned
        raise "mask wider than [64 * words] bits"
      limbs[offset + used] = rest
      nxt = rest >> 64
      Metaflip:Gf2:Bits.release(rest) if owned
      owned = true
      rest = nxt
      used += 1
    used

  # 1 when limb k of the array is nonzero. (Typed: reading `limbs[k]` from
  # untyped code boxes a limb of 2^47 or more into a fresh BigInt.)
  -> .limb_nonzero(limbs, k) (i64[] i64) i64
    if limbs[k] != 0
      return 1
    0

  # The high (which = 1) or low (which = 0) 32 bits of limb k, as a small
  # non-negative integer.
  -> .limb_half(limbs, k, which) (i64[] i64 i64) i64
    limb = limbs[k] ## i64
    if which == 1
      limb = limb >> 32
    limb & 4294967295

  # The Integer stored in limbs[offset, offset + words), built 32 bits at a time
  # from the most significant end.
  -> .from_limbs(limbs, offset, words)
    top = words - 1
    while top >= 0 && Metaflip:Gf2:Bits.limb_nonzero(limbs, offset + top) == 0
      top -= 1
    return 0 if top < 0
    x = 0
    j = top
    while j >= 0
      half = 1
      while half >= 0
        piece = Metaflip:Gf2:Bits.limb_half(limbs, offset + j, half)
        shifted = x << 32
        if piece == 0
          next_x = shifted
        else
          next_x = shifted | piece
          Metaflip:Gf2:Bits.release(shifted)
        Metaflip:Gf2:Bits.release(x)
        x = next_x
        half -= 1
      j -= 1
    x

  # ---- text ------------------------------------------------------------------

  # Address of a string's bytes for `Bits.byte`, or 0 for a string too short
  # (5 bytes or fewer) to have stable storage; `byte_at` per byte costs two C
  # calls, a raw load costs none, and the scanners below read hundreds of
  # megabytes.
  -> .text_ptr(text) (String) i64
    if text.size <= 5
      return 0
    ccall_nobox("w_string_data_ptr", text)

  # Byte i of text (ptr from text_ptr(text)); the caller keeps 0 <= i < size.
  -> .byte(text, ptr, i) (String i64 i64) i64
    if ptr == 0
      return text.byte_at(i)
    raw_load_u8(ptr, i)

  # ---- hexadecimal text ------------------------------------------------------

  # Lowercase hexadecimal, no leading zeros ("0" for 0).
  -> .to_hex(x)
    raise "mask must be non-negative" if x < 0
    x.to_s(16)

  # First index in [pos, limit) whose byte is not a lowercase hex digit
  # (limit when the whole range is).
  -> .hex_run(text, ptr, pos, limit) (String i64 i64 i64) i64
    i = pos ## i64
    while i < limit
      b = Metaflip:Gf2:Bits.byte(text, ptr, i) ## i64
      if (b < 48 || b > 57) && (b < 97 || b > 102)
        return i
      i += 1
    i

  # The hex digits text[first, last) (at most 16, all valid) as one limb.
  -> .hex_limb(text, ptr, first, last) (String i64 i64 i64) i64
    value = 0 ## i64
    i = first ## i64
    while i < last
      b = Metaflip:Gf2:Bits.byte(text, ptr, i) ## i64
      digit = b - 48 ## i64
      if b >= 97
        digit = b - 87
      value = (value << 4) | digit
      i += 1
    value

  # The value of the hex digits text[first, last), which the caller has already
  # checked (non-empty, lowercase hex digits only; leading zeros are fine).
  -> .hex_value(text, ptr, first, last)
    digits = last - first
    return Metaflip:Gf2:Bits.hex_limb(text, ptr, first, last) if digits <= 15
    words = (digits + 15) / 16
    limbs = i64[words]
    j = 0
    stop = last
    while stop > first
      start = stop - 16
      start = first if start < first
      limbs[j] = Metaflip:Gf2:Bits.hex_limb(text, ptr, start, stop)
      j += 1
      stop = start
    x = Metaflip:Gf2:Bits.from_limbs(limbs, 0, words)
    Metaflip:Gf2:Bits.release(limbs)
    x

  # The value of the lowercase hex digits text[first, last), or -1 when that
  # range is empty or holds any other byte. Leading zeros are accepted here;
  # callers that need canonical text check the first byte themselves.
  -> .parse_hex(text, first, last)
    return -1 if last <= first
    ptr = Metaflip:Gf2:Bits.text_ptr(text)
    return -1 if Metaflip:Gf2:Bits.hex_run(text, ptr, first, last) != last
    Metaflip:Gf2:Bits.hex_value(text, ptr, first, last)

  # Parses a whole lowercase hex string; raises on anything else.
  -> .from_hex(text)
    x = Metaflip:Gf2:Bits.parse_hex(text, 0, text.size)
    raise "not a lowercase hexadecimal mask: [text]" if x < 0
    x
