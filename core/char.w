# Char — 7-bit ASCII character (0..127).
#
# Literals:
#   :-A      # ASCII letter (65)
#   :-*      # ASCII punctuation (42)
#   :-\n     # ASCII control / escape (10)
#
# Char represents strictly 7-bit ASCII (`0..127`). For arbitrary 21-bit Unicode
# scalar values (`U+0000..U+10FFFF`), use `Codepoint` (`U+XXXX`). For
# user-perceived characters / extended grapheme clusters that may span multiple
# codepoints (such as a base character plus combining marks), use `Grapheme`.
+ Char < Codepoint

  -> .new(value)
    t = type(value)
    cp = nil
    if t == "Char" || t == "Codepoint"
      cp = value.codepoint()
    elsif t == "Int"
      cp = value
    elsif t == "String"
      if value.empty?()
        raise "empty character"
      if value.size() != 1
        raise "Char.new expects a single ASCII byte (0..127); use Codepoint.new or Grapheme.new for Unicode"
      cp = value.codepoints()[0]
    else
      cp = value.to_i()
    if !cp.is_a?(Int) || cp < 0 || cp > 127
      raise "invalid ASCII character (expected 0..127, got " + cp.to_s() + "); use Codepoint.new for non-ASCII Unicode scalars"
    ccall("w_char_new", cp)

  -> .from_i(value)
    Char.new(value)

  -> .valid?(value)
    t = type(value)
    if t == "Char" || t == "Codepoint"
      cp = value.codepoint()
      return cp >= 0 && cp <= 127
    return false if t != "Int"
    value >= 0 && value <= 127

  -> .ascii?(value)
    Char.valid?(value)
