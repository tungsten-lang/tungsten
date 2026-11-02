# Grapheme — UAX #29 extended grapheme cluster (core/grapheme.w).
#
# Run:
#   bin/tungsten spec/core/grapheme_spec.w
#   bin/tungsten run --interpret spec/core/grapheme_spec.w
#   bin/tungsten --ruby spec/core/grapheme_spec.w

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()

combining = Grapheme.new("e\u0301")
composed = Grapheme.new("é")
ascii_g = Grapheme.new("A")
from_cp = U+0065.to_grapheme()

check("type is Grapheme", type(combining) == "Grapheme")
check("is_a? Grapheme", combining.is_a?(Grapheme))
check("Codepoint#to_grapheme", type(from_cp) == "Grapheme" && from_cp.to_s == "e")
check("combining Grapheme size is 1", combining.size == 1 && combining.length == 1)
check("combining Grapheme byte_size is 3", combining.byte_size == 3 && combining.bytes == [101, 204, 129])
check("combining Grapheme has 2 codepoints", combining.codepoint_count == 2 && combining.codepoints == [101, 769])
check("combining Grapheme composite?", combining.composite? && combining.combining? && !composed.composite?)
check("combining Grapheme base and marks", combining.base == U+0065 && combining.combining_marks == [U+0301])
check("combining Grapheme scalars", combining.scalars == [U+0065, U+0301])
check("combining Grapheme nfc resolves to composed", combining.nfc.to_s == "é" && combining.nfc.codepoints == [233])
check("composed Grapheme nfd decomposes to combining", composed.nfd.codepoints == [101, 769])
check("canonically_equivalent?", combining.canonically_equivalent?(composed))
check("ascii_g to_char and to_codepoint", ascii_g.to_char == Char.new(65) && ascii_g.to_codepoint == U+0041)
check("composed to_codepoint", composed.to_codepoint == U+00E9)

multi_cp_raises = false
begin
  combining.to_codepoint()
rescue e
  multi_cp_raises = true
check("multi-codepoint Grapheme#to_codepoint raises", multi_cp_raises)

non_ascii_char_raises = false
begin
  composed.to_char()
rescue e
  non_ascii_char_raises = true
check("non-ASCII Grapheme#to_char raises", non_ascii_char_raises)

multi_grapheme_raises = false
begin
  Grapheme.new("ab")
rescue e
  multi_grapheme_raises = true
check("multi-grapheme String raises in Grapheme.new", multi_grapheme_raises)

empty_raises = false
begin
  Grapheme.new("")
rescue e
  empty_raises = true
check("empty String raises in Grapheme.new", empty_raises)

<< "ALL PASS grapheme_spec ([passed.load()] checks)"
