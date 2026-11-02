# Char (7-bit ASCII, core/char.w) & Codepoint (Unicode scalar, core/codepoint.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/char_spec.w
#   bin/tungsten -o /tmp/char_spec spec/core/char_spec.w && /tmp/char_spec

use core/char
use core/codepoint

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

-> char_raises?(cp)
  ok = 1
  begin
    Char.new(cp)
  rescue e
    ok = 0
  ok == 0

-> codepoint_raises?(cp)
  ok = 1
  begin
    Codepoint.new(cp)
  rescue e
    ok = 0
  ok == 0

a = Char.new(65)
check("constructs ASCII Char", type(a) == "Char")
check("ASCII Char is_a? Char", a.is_a?(Char))
check("ASCII Char is_a? Codepoint", a.is_a?(Codepoint))

check("U+0041 is_a? Char and Codepoint", U+0041.is_a?(Char) && U+0041.is_a?(Codepoint))
check("non-ASCII U+221E is_a? Codepoint but not Char", U+221E.is_a?(Codepoint) && !U+221E.is_a?(Char))

check("to_s", a.to_s == "A")
check("codepoint", a.codepoint == 65 && a.ord == 65 && a.to_i == 65)
check("chr", a.chr == "A")
check("inspect", a.inspect == "U+0041")
check("unicode_escape", a.unicode_escape == "U+0041")
check("uplus", a.uplus == "U+0041")
check("hex", a.hex == "41")
check("bytes ascii", a.bytes == [65] && a.byte_size == 1)
check("bytes utf-8", Codepoint.new(233).bytes == [195, 169] && Codepoint.new(233).byte_size == 2)
check("bytes astral", Codepoint.new(128512).byte_size == 4)
check("length/size", a.length == 1 && a.size == 1 && !a.empty?)
check("chars", a.chars == ["A"])
check("codepoints", a.codepoints == [65])
check("<=>", (a <=> Char.new(66)) == -1 && a < Char.new(66))
check("succ/next", a.succ == Char.new(66) && a.next == Char.new(66))
check("pred/prev", a.pred == Char.new(64) && a.prev == Char.new(64))
check("+ offset", a + 2 == Char.new(67))
check("- char", Char.new(67) - a == 2)
check("ascii?", a.ascii? && !Codepoint.new(233).ascii?)
check("latin1?", Codepoint.new(255).latin1? && !Codepoint.new(256).latin1?)
check("bmp?/astral?", Codepoint.new(65535).bmp? && Codepoint.new(65536).astral?)
check("valid?", Codepoint.new(1114111).valid?)
check("noncharacter?", Codepoint.new(65534).noncharacter?)
check("category", a.category == "Lu" && Codepoint.new(769).category == "Mn")
check("general_category", a.general_category == "Uppercase Letter")
check("name", a.name == "U+0041" && a.unicode_name == nil)
check("letter?", a.letter? && Codepoint.new(26085).letter?)
check("digit?", Char.new(55).digit? && !a.digit?)
check("alnum?", Char.new(55).alnum? && a.alnum?)
check("upper?/lower?", a.upper? && !a.lower? && Char.new(97).lower?)
check("titlecase?", Codepoint.new(453).titlecase?)
check("whitespace?", Char.new(32).whitespace? && Char.new(10).space?)
check("control?", Char.new(10).control? && Char.new(0).control? && Char.new(127).control?)
check("printable?", a.printable? && !Char.new(10).printable?)
check("punct?", Char.new(46).punct? && !Char.new(43).punct?)
check("symbol?", Char.new(43).symbol? && Codepoint.new(128512).symbol?)
check("separator?", Char.new(32).separator?)
check("xdigit?", Char.new(102).xdigit? && !Char.new(103).hex_digit?)
check("id_start?/id_continue?", Char.new(95).id_start? && !Char.new(55).id_start? && Char.new(55).id_continue?)
check("upcase", Char.new(97).upcase == a && Codepoint.new(233).upcase == Codepoint.new(201))
check("upcase expanding returns String", Codepoint.new(223).upcase == "SS")
check("downcase", a.downcase == Char.new(97))
check("titlecase", Codepoint.new(454).titlecase == Codepoint.new(453))
check("casefold", Codepoint.new(223).casefold == "ss")
check("swapcase", a.swapcase == Char.new(97))
check("Char rejects non-ASCII (>= 128)", char_raises?(128) && char_raises?(233) && char_raises?(128512))
check("Char rejects negative", char_raises?(-1))
check("Char.valid? is strictly 0..127", Char.valid?(0) && Char.valid?(127) && !Char.valid?(128) && !Char.valid?(-1))
check("Codepoint rejects out of range", codepoint_raises?(1114112))
check("Codepoint rejects negative", codepoint_raises?(-1))
check("Codepoint rejects surrogate", codepoint_raises?(0xD800))
check("Codepoint.new / from_i / to_char", Codepoint.new(65) == a && Codepoint.from_i(65).to_char == a)
non_ascii_to_char_raises = 0
begin
  Codepoint.new(233).to_char()
rescue e
  non_ascii_to_char_raises = 1
check("non-ASCII Codepoint#to_char raises", non_ascii_to_char_raises == 1)
check("Codepoint.valid? vs scalar?", Codepoint.valid?(0xD800) && !Codepoint.scalar?(0xD800) && Codepoint.scalar?(0x10FFFF) && !Codepoint.valid?(0x110000))
check("UCD short aliases", a.gc == a.general_category && a.blk == "ASCII" && a.sc == "Latin" && Char.new(33).sc == "Common" && a.na == nil && a.ccc == 0 && Codepoint.new(769).ccc == 230)
check("UCD grapheme properties", a.gr_base && !a.gr_ext && Codepoint.new(769).gr_ext && !Codepoint.new(769).gr_base)
check("UCD boolean property aliases", a.alpha && !a.lower && a.upper && !a.wspace && a.ahex && a.xids && a.xidc && !a.nchar)
check("UCD case mapping aliases", a.slc == Char.new(97) && Char.new(97).suc == a && a.scf == Char.new(97) && a.cwl && !a.cwu && a.cwcm)
check("POSIX is_*? predicates", a.is_ascii? && a.is_alpha? && a.is_upper? && !a.is_lower? && !a.is_cntrl? && !a.is_digit? && !a.is_space? && a.is_valid?)

<< "ALL PASS char_spec ([passed.load()] checks)"
