# Grapheme — Unicode extended grapheme cluster (UAX #29).
#
# A Grapheme represents a single user-perceived character, which may be the
# resolution of multiple Unicode code points (e.g. a base letter plus one or
# more combining marks `"e\u0301"`, Hangul jamo sequences, regional indicator
# flag pairs, or emoji ZWJ sequences).
#
# For a single 21-bit Unicode scalar value (`U+0000..U+10FFFF`), see `Codepoint`.
# For a 7-bit ASCII character (`0..127`, literal `:-A`), see `Char`.
+ Grapheme
  is Comparable

  -> new(value)
    t = type(value)
    if t == "Grapheme"
      @text = value.to_s()
    elsif t == "String"
      @text = value
    elsif t == "Char" || t == "Codepoint"
      @text = value.to_s()
    elsif t == "Int"
      @text = Codepoint.new(value).to_s()
    else
      @text = value.to_s()
    if @text.empty?()
      raise "empty grapheme"
    first_end = ccall_nobox("w_string_grapheme_next", @text, 0)
    if first_end != @text.size()
      raise "Grapheme.new expects a single grapheme cluster"
    @codepoints = @text.codepoints().to_a()

  -> to_s
    @text

  -> inspect
    @text

  -> size
    1

  -> length
    1

  -> byte_size
    @text.size()

  -> bytes
    @text.bytes().to_a()

  -> empty?
    false

  -> codepoints
    @codepoints

  -> codepoint_count
    @codepoints.size()

  -> composite?
    @codepoints.size() > 1

  -> combining?
    @codepoints.size() > 1

  -> ascii?
    @codepoints.size() == 1 && @codepoints[0] < 128

  -> base
    Codepoint.new(@codepoints[0])

  -> scalars
    out = []
    i = 0
    while i < @codepoints.size()
      out.push(Codepoint.new(@codepoints[i]))
      i += 1
    out

  -> combining_marks
    out = []
    i = 1
    while i < @codepoints.size()
      out.push(Codepoint.new(@codepoints[i]))
      i += 1
    out

  -> nfc
    Grapheme.new(@text.nfc())

  -> nfd
    Grapheme.new(@text.nfd())

  -> nfkc
    norm = @text.nfkc()
    if ccall_nobox("w_string_grapheme_next", norm, 0) == norm.size()
      return Grapheme.new(norm)
    norm

  -> nfkd
    norm = @text.nfkd()
    if ccall_nobox("w_string_grapheme_next", norm, 0) == norm.size()
      return Grapheme.new(norm)
    norm

  -> canonically_equivalent?(other)
    @text.nfc() == other.to_s().nfc()

  -> display_width(ambiguous = 1)
    Unicode.display_width(@text, ambiguous)

  -> emoji?
    Unicode.emoji?(@codepoints[0])

  -> upcase
    u = @text.upcase()
    if ccall_nobox("w_string_grapheme_next", u, 0) == u.size()
      return Grapheme.new(u)
    u

  -> downcase
    d = @text.downcase()
    if ccall_nobox("w_string_grapheme_next", d, 0) == d.size()
      return Grapheme.new(d)
    d

  -> to_grapheme
    self

  -> to_codepoint
    if @codepoints.size() != 1
      raise "cannot convert multi-codepoint Grapheme to a single Codepoint; use #codepoints or #nfc"
    Codepoint.new(@codepoints[0])

  -> to_char
    if @codepoints.size() != 1 || @codepoints[0] >= 128
      raise "cannot convert non-ASCII or multi-codepoint Grapheme to ASCII Char"
    Char.new(@codepoints[0])

  -> <=>(other)
    t = type(other)
    if t == "Grapheme" || t == "String" || t == "Char" || t == "Codepoint"
      return @text <=> other.to_s()
    nil
