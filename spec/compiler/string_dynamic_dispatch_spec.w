# Dynamic (untyped-receiver) dispatch of String/Symbol size and length —
# round-5, 2026-07-22. When a receiver's static type is unknown (e.g. a
# function-returned value), `.size()` goes through cached dynamic dispatch.
# Native size dispatch and every source method in core/string_native.w must
# remain reachable across erased receiver boundaries for all String storage
# modes and the shared Symbol representation.
#
# Run: `bin/tungsten -o /tmp/sdd spec/compiler/string_dynamic_dispatch_spec.w && /tmp/sdd`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> f(x)
  x

-> dyn_empty(value)
  value.empty?

-> dyn_swapcase(value)
  value.swapcase

-> dyn_capitalize(value)
  value.capitalize

-> dyn_reverse(value)
  value.reverse

-> dyn_chars(value)
  value.chars

-> dyn_bytes(value)
  value.bytes

-> dyn_ascii(value)
  value.ascii?

-> dyn_blank(value)
  value.blank?

-> dyn_byte_at(value, idx)
  value.byte_at(idx)

-> dyn_codepoints(value)
  value.codepoints

-> dyn_characters(value)
  value.characters

-> dyn_each_byte_sum(value)
  total = 0
  value.each_byte -> (b)
    total += b
  total

-> dyn_nfd(value)
  value.nfd

-> dyn_graphemes(value)
  value.graphemes

-> dyn_camelize(value)
  value.camelize

-> dyn_scan(value, pat)
  value.scan(pat)

-> dyn_upcase(value)
  value.upcase

-> dyn_downcase(value)
  value.downcase

-> dyn_lpad(value)
  value.lpad(8, ".")

-> dyn_rpad(value)
  value.rpad(8, ".")

-> dyn_center(value)
  value.center(7, ".")

-> dyn_delete(value)
  value.delete("lo")

-> dyn_squeeze(value)
  value.squeeze

-> dyn_squeeze_set(value)
  value.squeeze("a")

-> dyn_tr(value)
  value.tr("ae", "xy")

-> dyn_to_s(value)
  value.to_s

check("dyn.sso_size", f("hello").size(), 5)
check("dyn.heap_size", f("hello world longer!").size(), 19)
check("dyn.empty_size", f("").size(), 0)
check("dyn.length_alias", f("hello").length(), 5)
check("dyn.utf8_bytes", f("héllo").size(), 6)
check("dyn.symbol_size", f(:hello).size(), 5)
check("dyn.symbol_length", f(:hello).length(), 5)

n = f(88172645463325252)
check("dyn.chained_to_s_size", n.to_s().size(), 17)
check("dyn.chained_in_interp", "[n.to_s().size()]", "17")
check("dyn.smallint_chain", f(12345).to_s().size(), 5)
check("dyn.cmp_in_interp", "[n.to_s().size() > 20]", "false")

check("dyn.empty.inline", dyn_empty(""), true)
check("dyn.empty.slab", dyn_empty("123456"), false)
check("dyn.empty.symbol", dyn_empty("".to_sym), true)
check("dyn.swapcase.inline", dyn_swapcase("AbC"), "aBc")
check("dyn.swapcase.heap", dyn_swapcase("AbCdEf" * 12), "aBcDeF" * 12)
check("dyn.capitalize", dyn_capitalize("hELLO"), "Hello")
check("dyn.reverse.utf8", dyn_reverse("aé日"), "日éa")
check("dyn.chars", dyn_chars("aé").join("|"), "a|é")
check("dyn.bytes", dyn_bytes("é"), [195, 169])
check("dyn.upcase", dyn_upcase("Abc-é"), "ABC-é")
check("dyn.downcase", dyn_downcase("AbC-É"), "abc-É")
check("dyn.lpad", dyn_lpad("abc"), ".....abc")
check("dyn.rpad", dyn_rpad("abc"), "abc.....")
check("dyn.center", dyn_center("abc"), "..abc..")
check("dyn.delete", dyn_delete("hello"), "he")
check("dyn.squeeze", dyn_squeeze("aaabbbcc"), "abc")
check("dyn.squeeze.set", dyn_squeeze_set("aaabbb"), "abbb")
check("dyn.tr", dyn_tr("peace"), "pyxcy")
check("dyn.to_s.symbol", dyn_to_s(:symbol), "symbol")
check("dyn.bytes.to_a", dyn_bytes("é").to_a, [195, 169])
check("dyn.ascii.true", dyn_ascii("abc"), true)
check("dyn.ascii.false", dyn_ascii("é"), false)
check("dyn.ascii.symbol", dyn_ascii(:abc), true)
check("dyn.ascii.heap", dyn_ascii(f("h" * 80)), true)
check("dyn.blank.true", dyn_blank("  "), true)
check("dyn.blank.false", dyn_blank(" x "), false)
check("dyn.byte_at", dyn_byte_at("abc", 1), 98)
check("dyn.byte_at.negative", dyn_byte_at("abc", -1), 99)
check("dyn.codepoints", dyn_codepoints("aé").to_a, [97, 233])
check("dyn.characters", dyn_characters("aé").to_a.join("|"), "a|é")
check("dyn.each_byte", dyn_each_byte_sum("ab"), 195)
check("dyn.nfd", dyn_nfd(233.chr), 101.chr + 769.chr)
check("dyn.nfd.symbol", dyn_nfd(:abc), "abc")
check("dyn.graphemes", dyn_graphemes("ab").to_a, ["a", "b"])
check("dyn.camelize", dyn_camelize("a_b"), "AB")
check("dyn.scan", dyn_scan("x1y2", "y"), ["y"])
