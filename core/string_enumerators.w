# Lazy views over a String's content, returned by String#bytes,
# String#codepoints, and String#characters (and by their each_* siblings
# when called without a block). Construction is O(1) and copies nothing:
# every read goes to the underlying string on demand.
#
# StringBytes is an indexed Enumerable — `size` and `[]` are O(1) byte reads
# — so subscripting callers keep Array-shaped access without materializing
# an Array. Code points and characters are variable-width, so their views
# stream through the UTF-8 walk instead of exposing subscripts; use to_a
# for a concrete Array.

+ StringBytes
  is Enumerable

  -> new(@source)

  # Indexed iteration (mode 1): Enumerable combinators loop `self[i]`
  # against `size`, so every element is one O(1) byte load off the string.
  -> __enumerable_iteration_mode
    1

  -> size
    @source.size

  -> length
    @source.size

  -> [](index)
    @source.byte_at(index)

  -> each(&block)
    @source.each_byte -> (b)
      block(b)
    self

  # Materialize natively: one pass over the string's storage in String's own
  # byte walker, instead of the trait's per-element `self[i]` dispatch loop.
  -> to_a
    @source.__bytes_array

  # Element-wise equality against any indexable collection (Array included),
  # so established `text.bytes == [104, 105]` call sites keep their meaning.
  -> ==(other)
    if other == nil
      return false
    eq_n = size
    if eq_n != other.size
      return false
    eq_i = 0
    while eq_i < eq_n
      if self[eq_i] != other[eq_i]
        return false
      eq_i += 1
    true

  -> !=(other)
    !(self == other)

+ StringCodepoints
  is Enumerable

  -> new(@source)

  -> each(&block)
    @source.each_codepoint -> (cp)
      block(cp)
    self

  # Code points are variable-width, so counting is one UTF-8 walk.
  -> size
    sz = 0
    @source.each_codepoint -> (cp)
      sz += 1
    sz

+ StringCharacters
  is Enumerable

  -> new(@source)

  -> each(&block)
    @source.each_character -> (c)
      block(c)
    self

  -> size
    sz = 0
    @source.each_character -> (c)
      sz += 1
    sz

+ StringGraphemes
  is Enumerable

  -> new(@source)

  -> each(&block)
    @source.each_grapheme -> (g)
      block(g)
    self

  -> size
    sz = 0
    @source.each_grapheme -> (g)
      sz += 1
    sz

+ StringLines
  is Enumerable

  -> new(@source)

  -> each(&block)
    @source.each_line -> (l)
      block(l)
    self

  -> size
    sz = 0
    @source.each_line -> (l)
      sz += 1
    sz
