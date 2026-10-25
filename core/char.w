# Char — Unicode scalar value.
#
# Literals:
#   :-A      # ASCII character literal
#   :-/      # ASCII punctuation
#   U+221E   # Unicode scalar literal
+ Char
  is Comparable

  CATEGORY_CODES = %w[Lu Ll Lt Lm Lo Nd Nl No Zs Zl Zp Mn Mc Me Pc Pd Ps Pe Pi Pf Po Sm Sc Sk So Cc Cf Cs Co Cn]

  CATEGORY_NAMES = [
    "Uppercase Letter", "Lowercase Letter", "Titlecase Letter", "Modifier Letter", "Other Letter",
    "Decimal Number", "Letter Number", "Other Number",
    "Space Separator", "Line Separator", "Paragraph Separator",
    "Nonspacing Mark", "Spacing Mark", "Enclosing Mark",
    "Connector Punctuation", "Dash Punctuation", "Open Punctuation", "Close Punctuation",
    "Initial Quote Punctuation", "Final Quote Punctuation", "Other Punctuation",
    "Math Symbol", "Currency Symbol", "Modifier Symbol", "Other Symbol",
    "Control", "Format", "Surrogate", "Private Use", "Unassigned"
  ]

  -> .new(value)
    t = type(value)
    if t == "Char"
      return value
    cp = nil
    if t == "Int"
      cp = value
    elsif t == "String"
      if value.empty?()
        raise "empty character"
      cp = value.codepoints()[0]
    else
      cp = value.to_i()
    if !cp.is_a?(Int) || cp < 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)
      raise "invalid Unicode scalar value U+" + cp.to_i().to_s(16).upcase()
    ccall("w_char_new", cp)

  -> wvalue_bits
    $value

  # Identity / conversion
  -> codepoint
    ($value >> 25) & 0x1FFFFF

  -> ord
    ($value >> 25) & 0x1FFFFF

  -> to_i
    ($value >> 25) & 0x1FFFFF

  -> to_s
    ch_c = (($value >> 25) & 0x1FFFFF) ## i64
    ch_tag = -1_970_324_836_974_592 ## i64
    if ch_c < 128
      return wvalue_from_bits((ch_tag | 2 | (ch_c << 4)) ## i64)
    if ch_c < 2048
      ch_b0 = 192 | (ch_c >> 6)
      ch_b1 = 128 | (ch_c & 63)
      return wvalue_from_bits((ch_tag | 4 | (ch_b0 << 4) | (ch_b1 << 12)) ## i64)
    if ch_c < 65536
      ch_b0 = 224 | (ch_c >> 12)
      ch_b1 = 128 | ((ch_c >> 6) & 63)
      ch_b2 = 128 | (ch_c & 63)
      return wvalue_from_bits((ch_tag | 6 | (ch_b0 << 4) | (ch_b1 << 12) | (ch_b2 << 20)) ## i64)
    ch_b0 = (240 | (ch_c >> 18)) & 0xFF
    ch_b1 = 128 | ((ch_c >> 12) & 63)
    ch_b2 = 128 | ((ch_c >> 6) & 63)
    ch_b3 = 128 | (ch_c & 63)
    wvalue_from_bits((ch_tag | 8 | (ch_b0 << 4) | (ch_b1 << 12) | (ch_b2 << 20) | (ch_b3 << 28)) ## i64)

  -> chr
    self.to_s()

  -> hex
    (($value >> 25) & 0x1FFFFF).to_s(16).upcase()

  -> uplus
    cp = ($value >> 25) & 0x1FFFFF
    h = cp.to_s(16).upcase()
    width = cp <= 0xFFFF ? 4 : 6
    while h.size() < width
      h = "0" + h
    "U+" + h

  -> unicode_escape
    self.uplus()

  -> inspect
    self.uplus()

  -> bytes
    cp = ($value >> 25) & 0x1FFFFF
    if cp < 128
      return [cp]
    if cp < 2048
      return [192 | (cp >> 6), 128 | (cp & 63)]
    if cp < 65536
      return [224 | (cp >> 12), 128 | ((cp >> 6) & 63), 128 | (cp & 63)]
    [(240 | (cp >> 18)) & 0xFF, 128 | ((cp >> 12) & 63), 128 | ((cp >> 6) & 63), 128 | (cp & 63)]

  -> byte_size
    cp = ($value >> 25) & 0x1FFFFF
    if cp < 128
      return 1
    if cp < 2048
      return 2
    if cp < 65536
      return 3
    4

  -> length
    1

  -> size
    1

  -> empty?
    false

  -> chars
    [self.to_s()]

  -> codepoints
    [($value >> 25) & 0x1FFFFF]

  # Ordering / stepping by Unicode scalar value.
  -> <=>(other)
    self_cp = ($value >> 25) & 0x1FFFFF
    t = type(other)
    other_cp = nil
    if t == "Char"
      other_cp = other.codepoint()
    elsif t == "Int"
      other_cp = other
    elsif t == "String"
      if other.empty?()
        return nil
      other_cp = other.codepoints()[0]
    else
      return nil
    if self_cp < other_cp
      return -1
    if self_cp > other_cp
      return 1
    0

  -> +(offset)
    delta = offset.to_i()
    shifted = (($value >> 25) & 0x1FFFFF) + delta
    while shifted >= 0xD800 && shifted <= 0xDFFF
      shifted += delta
    Char.new(shifted)

  -> -(other)
    if type(other) == "Char"
      return (($value >> 25) & 0x1FFFFF) - other.codepoint()
    self + (-other.to_i())

  -> succ
    self + 1

  -> next
    self + 1

  -> pred
    self - 1

  -> prev
    self - 1

  # Unicode shape.
  -> ascii?
    (($value >> 25) & 0x1FFFFF) < 128

  -> latin1?
    (($value >> 25) & 0x1FFFFF) < 256

  -> bmp?
    (($value >> 25) & 0x1FFFFF) <= 65535

  -> astral?
    (($value >> 25) & 0x1FFFFF) > 65535

  -> valid?
    cp = ($value >> 25) & 0x1FFFFF
    cp >= 0 && cp <= 0x10FFFF && (cp < 0xD800 || cp > 0xDFFF)

  -> noncharacter?
    cp = ($value >> 25) & 0x1FFFFF
    (cp >= 0xFDD0 && cp <= 0xFDEF) || (cp & 0xFFFE) == 0xFFFE

  -> category
    CATEGORY_CODES[($value >> 3) & 0x1F]

  -> general_category
    CATEGORY_NAMES[($value >> 3) & 0x1F]

  -> unicode_name
    nil

  -> name
    self.uplus()

  # Classification.
  -> letter?
    (($value >> 3) & 0x1F) <= 4

  -> alphabetic?
    (($value >> 3) & 0x1F) <= 4

  -> alpha?
    (($value >> 3) & 0x1F) <= 4

  -> mark?
    cat = ($value >> 3) & 0x1F
    cat >= 11 && cat <= 13

  -> number?
    cat = ($value >> 3) & 0x1F
    cat >= 5 && cat <= 7

  -> digit?
    ($value & 1) != 0

  -> alnum?
    (($value >> 3) & 0x1F) <= 5

  -> lowercase?
    (($value >> 3) & 0x1F) == 1

  -> lower?
    (($value >> 3) & 0x1F) == 1

  -> uppercase?
    (($value >> 3) & 0x1F) == 0

  -> upper?
    (($value >> 3) & 0x1F) == 0

  -> titlecase?
    (($value >> 3) & 0x1F) == 2

  -> whitespace?
    if ($value & 4) != 0
      return true
    cp = ($value >> 25) & 0x1FFFFF
    (cp >= 9 && cp <= 13) || cp == 0x85

  -> space?
    self.whitespace?()

  -> control?
    (($value >> 3) & 0x1F) == 25

  -> printable?
    (($value >> 23) & 1) != 0

  -> punctuation?
    cat = ($value >> 3) & 0x1F
    cat >= 14 && cat <= 20

  -> punct?
    cat = ($value >> 3) & 0x1F
    cat >= 14 && cat <= 20

  -> symbol?
    cat = ($value >> 3) & 0x1F
    cat >= 21 && cat <= 24

  -> separator?
    ($value & 4) != 0

  -> hex_digit?
    cp = ($value >> 25) & 0x1FFFFF
    (cp >= 48 && cp <= 57) || (cp >= 65 && cp <= 70) || (cp >= 97 && cp <= 102)

  -> xdigit?
    self.hex_digit?()

  -> id_start?
    cat = ($value >> 3) & 0x1F
    if cat <= 4 || cat == 6
      return true
    (($value >> 25) & 0x1FFFFF) == 95

  -> id_continue?
    cat = ($value >> 3) & 0x1F
    cat <= 7 || (cat >= 11 && cat <= 14)

  # Case mapping. A mapping that expands to multiple scalars returns String.
  -> upcase
    cp = ($value >> 25) & 0x1FFFFF
    if cp == 223
      return "SS"
    cat = ($value >> 3) & 0x1F
    if cat == 2
      return Char.new(cp - 1)
    if cat != 1
      return self
    raw = ($value >> 10) & 0x1FF
    delta = raw >= 256 ? raw - 512 : raw
    if delta == 0 || delta == -256
      return self
    Char.new(cp + delta)

  -> uppercase
    self.upcase()

  -> downcase
    cat = ($value >> 3) & 0x1F
    if cat != 0 && cat != 2
      return self
    raw = ($value >> 10) & 0x1FF
    delta = raw >= 256 ? raw - 512 : raw
    if delta == 0 || delta == -256
      return self
    cp = ($value >> 25) & 0x1FFFFF
    Char.new(cp + delta)

  -> lowercase
    self.downcase()

  -> titlecase
    cp = ($value >> 25) & 0x1FFFFF
    if cp == 223
      return "Ss"
    if cp in (454 457 460 499)
      return Char.new(cp - 1)
    if cp in (452 455 458 497)
      return Char.new(cp + 1)
    self.upcase()

  -> casefold
    cp = ($value >> 25) & 0x1FFFFF
    if cp == 223
      return "ss"
    self.downcase()

  -> swapcase
    cat = ($value >> 3) & 0x1F
    if cat == 1
      return self.upcase()
    if cat == 0 || cat == 2
      return self.downcase()
    self
