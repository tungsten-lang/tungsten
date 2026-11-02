# Codepoint — 21-bit Unicode scalar value (U+0000..U+10FFFF, excluding surrogates).
#
# Literals:
#   U+0041   # Latin Capital Letter A (65)
#   U+00E9   # Latin Small Letter E with Acute (233)
#   U+221E   # Infinity (8734)
#
# A Codepoint is a single Unicode scalar value and is the unit on which Unicode
# Character Database (UCD, UAX #44) properties are defined. A user-perceived
# character (extended grapheme cluster, UAX #29) may be the resolution of
# multiple codepoints (e.g. a base letter plus combining accent `e\u0301` ->
# see `Grapheme`). For 7-bit ASCII characters (`0..127`, literal `:-A`), see
# `Char < Codepoint`.
+ Codepoint
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
    if t == "Char" || t == "Codepoint"
      return value
    cp = nil
    if t == "Int"
      cp = value
    elsif t == "String"
      if value.empty?()
        raise "empty codepoint"
      cps = value.codepoints()
      if cps.size() > 1
        raise "Codepoint.new expects a single Unicode codepoint; use Grapheme.new for multi-codepoint graphemes"
      cp = cps[0]
    else
      cp = value.to_i()
    if !cp.is_a?(Int) || cp < 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)
      raise "invalid Unicode scalar value U+" + cp.to_i().to_s(16).upcase()
    ccall("w_char_new", cp)

  -> .from_i(value)
    Codepoint.new(value)

  -> .valid?(value)
    t = type(value)
    if t == "Char" || t == "Codepoint"
      return value.valid?()
    return false if t != "Int"
    value >= 0 && value <= 0x10FFFF

  -> .scalar?(value)
    t = type(value)
    if t == "Char" || t == "Codepoint"
      return value.valid?()
    return false if t != "Int"
    value >= 0 && value <= 0x10FFFF && (value < 0xD800 || value > 0xDFFF)

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

  -> to_codepoint
    self

  -> to_char
    Char.new(self)

  -> to_grapheme
    Grapheme.new(self.to_s())

  # Ordering / stepping by Unicode scalar value.
  -> <=>(other)
    self_cp = ($value >> 25) & 0x1FFFFF
    t = type(other)
    other_cp = nil
    if t == "Char" || t == "Codepoint"
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
    Codepoint.new(shifted)

  -> -(other)
    t = type(other)
    if t == "Char" || t == "Codepoint"
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

  # Unicode shape & UCD properties (UAX #44).
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

  -> scalar?
    self.valid?()

  -> noncharacter?
    cp = ($value >> 25) & 0x1FFFFF
    (cp >= 0xFDD0 && cp <= 0xFDEF) || (cp & 0xFFFE) == 0xFFFE

  -> noncharacter_code_point
    self.noncharacter?()

  -> nchar
    self.noncharacter?()

  -> category
    CATEGORY_CODES[($value >> 3) & 0x1F]

  -> general_category
    CATEGORY_NAMES[($value >> 3) & 0x1F]

  -> gc
    self.general_category()

  -> block
    cp = ($value >> 25) & 0x1FFFFF
    if cp < 128
      return "ASCII"
    if cp < 256
      return "Latin-1 Supplement"
    if cp <= 0xFFFF
      return "BMP"
    "Supplementary"

  -> blk
    self.block()

  -> script
    Unicode.script(self.ord())

  -> sc
    self.script()

  -> age
    Unicode.codepoint_age(self.ord())

  -> assigned?(version = nil)
    Unicode.assigned?(self.ord(), version)

  -> unicode_name
    nil

  -> na
    self.unicode_name()

  -> unicode_1_name
    nil

  -> na1
    self.unicode_1_name()

  -> name
    self.uplus()

  -> combining_class(version = nil)
    Unicode.combining_class(self.ord(), version)

  -> ccc
    self.combining_class()

  -> east_asian_width
    Unicode.east_asian_width(self.ord())

  -> ea
    self.east_asian_width()

  -> display_width(ambiguous = 1)
    Unicode.char_width(self.ord(), ambiguous)

  -> bidi_class
    Unicode.bidi_class(self.ord())

  -> bc
    self.bidi_class()

  -> bidi_mirrored?
    Unicode.bidi_mirrored?(self.ord())

  -> bidi_m
    self.bidi_mirrored?()

  -> bidi_mirror
    m = Unicode.bidi_mirror(self.ord())
    m == self.ord() ? self : Codepoint.new(m)

  -> bmg
    self.bidi_mirror()

  -> bidi_control?
    Unicode.bidi_control?(self.ord())

  -> bidi_c
    self.bidi_control?()

  -> emoji?
    Unicode.emoji?(self.ord())

  -> emoji_presentation?
    Unicode.emoji_presentation?(self.ord())

  -> epres
    self.emoji_presentation?()

  -> emoji_modifier?
    Unicode.emoji_modifier?(self.ord())

  -> emod
    self.emoji_modifier?()

  -> emoji_modifier_base?
    Unicode.emoji_modifier_base?(self.ord())

  -> ebase
    self.emoji_modifier_base?()

  -> extended_pictographic?
    Unicode.extended_pictographic?(self.ord())

  -> extpict
    self.extended_pictographic?()

  -> ideographic?
    Unicode.ideographic?(self.ord())

  -> ideo
    self.ideographic?()

  -> pattern_syntax?
    Unicode.pattern_syntax?(self.ord())

  -> pat_syn
    self.pattern_syntax?()

  -> pattern_white_space?
    Unicode.pattern_white_space?(self.ord())

  -> pat_ws
    self.pattern_white_space?()

  -> grapheme_base
    !self.mark?() && !self.control?()

  -> gr_base
    self.grapheme_base()

  -> grapheme_extend
    self.mark?()

  -> gr_ext
    self.grapheme_extend()

  # Classification.
  -> letter?
    (($value >> 3) & 0x1F) <= 4

  -> alphabetic?
    (($value >> 3) & 0x1F) <= 4

  -> alphabetic
    self.alphabetic?()

  -> alpha?
    (($value >> 3) & 0x1F) <= 4

  -> alpha
    self.alphabetic?()

  -> mark?
    cat = ($value >> 3) & 0x1F
    cat >= 11 && cat <= 13

  -> diacritic
    self.mark?()

  -> dia
    self.diacritic()

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

  -> lower
    self.lowercase?()

  -> uppercase?
    (($value >> 3) & 0x1F) == 0

  -> upper?
    (($value >> 3) & 0x1F) == 0

  -> upper
    self.uppercase?()

  -> titlecase?
    (($value >> 3) & 0x1F) == 2

  -> whitespace?
    if ($value & 4) != 0
      return true
    cp = ($value >> 25) & 0x1FFFFF
    (cp >= 9 && cp <= 13) || cp == 0x85

  -> space?
    self.whitespace?()

  -> white_space
    self.whitespace?()

  -> wspace
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

  -> hex_digit
    self.hex_digit?()

  -> ascii_hex_digit
    self.hex_digit?()

  -> ahex
    self.hex_digit?()

  -> xdigit?
    self.hex_digit?()

  -> id_start?
    cat = ($value >> 3) & 0x1F
    if cat <= 4 || cat == 6
      return true
    (($value >> 25) & 0x1FFFFF) == 95

  -> id_start
    self.id_start?()

  -> ids
    self.id_start?()

  -> xid_start
    self.id_start?()

  -> xids
    self.id_start?()

  -> id_continue?
    cat = ($value >> 3) & 0x1F
    cat <= 7 || (cat >= 11 && cat <= 14)

  -> id_continue
    self.id_continue?()

  -> idc
    self.id_continue?()

  -> xid_continue
    self.id_continue?()

  -> xidc
    self.id_continue?()

  # POSIX-style `is_*?` predicate aliases
  -> is_alnum?
    self.alnum?()

  -> is_alpha?
    self.alpha?()

  -> is_ascii?
    self.ascii?()

  -> is_cntrl?
    self.control?()

  -> is_digit?
    self.digit?()

  -> is_graph?
    !self.space?() && !self.control?()

  -> is_lower?
    self.lower?()

  -> is_number?
    self.number?()

  -> is_print?
    self.printable?()

  -> is_punct?
    self.punct?()

  -> is_space?
    self.space?()

  -> is_upper?
    self.upper?()

  -> is_valid?
    self.valid?()

  -> is_xdigit?
    self.xdigit?()

  # Case mapping. A mapping that expands to multiple scalars returns String.
  -> upcase
    cp = ($value >> 25) & 0x1FFFFF
    if cp == 223
      return "SS"
    cat = ($value >> 3) & 0x1F
    if cat == 2
      return Codepoint.new(cp - 1)
    if cat != 1
      return self
    raw = ($value >> 10) & 0x1FF
    delta = raw >= 256 ? raw - 512 : raw
    if delta == 0 || delta == -256
      return self
    Codepoint.new(cp + delta)

  -> uppercase
    self.upcase()

  -> simple_uppercase_mapping
    self.upcase()

  -> suc
    self.upcase()

  -> uppercase_mapping
    self.upcase()

  -> uc
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
    Codepoint.new(cp + delta)

  -> lowercase
    self.downcase()

  -> simple_lowercase_mapping
    self.downcase()

  -> slc
    self.downcase()

  -> lowercase_mapping
    self.downcase()

  -> lc
    self.downcase()

  -> titlecase
    cp = ($value >> 25) & 0x1FFFFF
    if cp == 223
      return "Ss"
    if cp in (454 457 460 499)
      return Codepoint.new(cp - 1)
    if cp in (452 455 458 497)
      return Codepoint.new(cp + 1)
    self.upcase()

  -> simple_titlecase_mapping
    self.titlecase()

  -> stc
    self.titlecase()

  -> titlecase_mapping
    self.titlecase()

  -> tc
    self.titlecase()

  -> casefold
    cp = ($value >> 25) & 0x1FFFFF
    if cp == 223
      return "ss"
    self.downcase()

  -> simple_case_folding
    self.casefold()

  -> scf
    self.casefold()

  -> case_folding
    self.casefold()

  -> cf
    self.casefold()

  -> swapcase
    cat = ($value >> 3) & 0x1F
    if cat == 1
      return self.upcase()
    if cat == 0 || cat == 2
      return self.downcase()
    self

  -> changes_when_lowercased
    self.downcase() != self

  -> cwl
    self.changes_when_lowercased()

  -> changes_when_uppercased
    self.upcase() != self

  -> cwu
    self.changes_when_uppercased()

  -> changes_when_titlecased
    self.titlecase() != self

  -> cwt
    self.changes_when_titlecased()

  -> changes_when_casefolded
    self.casefold() != self

  -> cwcf
    self.changes_when_casefolded()

  -> changes_when_casemapped
    self.changes_when_lowercased() || self.changes_when_uppercased() || self.changes_when_titlecased()

  -> cwcm
    self.changes_when_casemapped()

use core/char
