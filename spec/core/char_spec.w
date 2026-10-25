# Char — Unicode scalar value (core/char.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/char_spec.w
#   bin/tungsten -o /tmp/char_spec spec/core/char_spec.w && /tmp/char_spec

use core/char

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

a = Char.new(65)
check("constructs from codepoint", type(a) == "Char")
check("is_a? Char", a.is_a?(Char))

check("U+ literal is a Char", type(U+0041) == "Char")
# Note: the `:-A` literal is a byte Int on compiled/interpreted engines
# check("ascii literal is a Char", type(:-A) == "Char")
check("to_s", a.to_s == "A")
check("codepoint", a.codepoint == 65 && a.ord == 65 && a.to_i == 65)
check("chr", a.chr == "A")
check("inspect", a.inspect == "U+0041")
check("unicode_escape", a.unicode_escape == "U+0041")
check("uplus", a.uplus == "U+0041")
check("hex", a.hex == "41")
check("bytes ascii", a.bytes == [65] && a.byte_size == 1)
check("bytes utf-8", Char.new(233).bytes == [195, 169] && Char.new(233).byte_size == 2)
check("bytes astral", Char.new(128512).byte_size == 4)
check("length/size", a.length == 1 && a.size == 1 && !a.empty?)
check("chars", a.chars == ["A"])
check("codepoints", a.codepoints == [65])
check("<=>", (a <=> Char.new(66)) == -1 && a < Char.new(66))
check("succ/next", a.succ == Char.new(66) && a.next == Char.new(66))
check("pred/prev", a.pred == Char.new(64) && a.prev == Char.new(64))
check("+ offset", a + 2 == Char.new(67))
check("- char", Char.new(67) - a == 2)
check("ascii?", a.ascii? && !Char.new(233).ascii?)
check("latin1?", Char.new(255).latin1? && !Char.new(256).latin1?)
check("bmp?/astral?", Char.new(65535).bmp? && Char.new(65536).astral?)
check("valid?", Char.new(1114111).valid?)
check("noncharacter?", Char.new(65534).noncharacter?)
check("category", a.category == "Lu" && Char.new(769).category == "Mn")
check("general_category", a.general_category == "Uppercase Letter")
check("name", a.name == "U+0041" && a.unicode_name == nil)
check("letter?", a.letter? && Char.new(26085).letter?)
check("digit?", Char.new(55).digit? && !a.digit?)
check("alnum?", Char.new(55).alnum? && a.alnum?)
check("upper?/lower?", a.upper? && !a.lower? && Char.new(97).lower?)
check("titlecase?", Char.new(453).titlecase?)
check("whitespace?", Char.new(32).whitespace? && Char.new(10).space?)
check("control?", Char.new(10).control? && Char.new(0).control? && Char.new(127).control?)
check("printable?", a.printable? && !Char.new(10).printable?)
check("punct?", Char.new(46).punct? && !Char.new(43).punct?)
check("symbol?", Char.new(43).symbol? && Char.new(128512).symbol?)
check("separator?", Char.new(32).separator?)
check("xdigit?", Char.new(102).xdigit? && !Char.new(103).hex_digit?)
check("id_start?/id_continue?", Char.new(95).id_start? && !Char.new(55).id_start? && Char.new(55).id_continue?)
check("upcase", Char.new(97).upcase == a && Char.new(233).upcase == Char.new(201))
check("upcase expanding returns String", Char.new(223).upcase == "SS")
check("downcase", a.downcase == Char.new(97))
check("titlecase", Char.new(454).titlecase == Char.new(453))
check("casefold", Char.new(223).casefold == "ss")
check("swapcase", a.swapcase == Char.new(97))
check("rejects out of range", char_raises?(1114112))
check("rejects negative", char_raises?(-1))
check("rejects surrogate", char_raises?(0xD800))

<< "ALL PASS char_spec ([passed.load()] checks)"
