# String#lchs returns complete tagged LexChar WValues. Its array therefore
# uses w64 storage; i64 storage would numerically box a negative LexChar on a
# generic read. The lexer keeps that w64[] contract on its ivar and explicitly
# reinterprets the same slots only where its native scanner needs raw masks.

-> check(name, got, want)
  if got != want
    << "FAIL lexchar storage " + name + " got=" + got.to_s() + " want=" + want.to_s()
    exit(1)
  << "PASS lexchar storage " + name

+ LexCharStorageProbe
  -> new(source)
    set_lexchars(source.lchs("tungsten"))

  -> set_lexchars(@lc) (w64[])
    self

  -> tagged_at(index)
    @lc[index]

  -> raw_matches_tagged?(index)
    raw = @lc ## i64[]
    raw[index] == wvalue_bits(@lc[index])

chars = "F0z".lchs("tungsten") ## w64[]
probe = LexCharStorageProbe.new("F0z")

check("tag preserved", (wvalue_bits(probe.tagged_at(0)) >> 48) & 0xFFFF, 0xFFFC)
check("hex flag", wvalue_bits(probe.tagged_at(0)) & 8, 8)
check("digit codepoint", (wvalue_bits(probe.tagged_at(1)) >> 18) & 0x1FFFFF, 48)
check("raw reinterpret", probe.raw_matches_tagged?(2), true)

<< "PASS lexer lexchar storage"
