# Native String method dispatch and representation-invariant regressions.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

# Canonical inline empty plus every operation here that can produce a
# zero-length result must converge on that same mode-0 representation.
check("literal empty", "".empty?, true)
check("inline nonempty", "a".empty?, false)
check("inline max", "12345".empty?, false)
check("slab", "123456".empty?, false)
check("slab long", "a slab-backed string".empty?, false)
check("slice empty", "abc".slice(99, 3).empty?, true)
check("repeat empty", ("abc" * 0).empty?, true)
check("strip empty", "   ".strip.empty?, true)
check("upcase empty", "".upcase.empty?, true)
check("downcase empty", "".downcase.empty?, true)
check("capitalize empty", "".capitalize.empty?, true)

# w_str_append deliberately creates heap strings even for short non-empty
# results; repeat creates a long heap string. Both must reject empty?.
heap_short = "".concat("h")
heap_long = "h" * 80
check("short heap", heap_short.empty?, false)
check("long heap", heap_long.empty?, false)

# A concatenation above the short-string threshold is a rope. Runtime dispatch
# flattens it before invoking the native String method.
rope_left = "l" * 40
rope_right = "r" * 40
rope = rope_left + rope_right
check("rope", rope.empty?, false)

# Symbols share String's 0xF9 representation and historically shared its IC.
check("empty symbol", "".to_sym.empty?, true)
check("nonempty symbol", "x".to_sym.empty?, false)

-> check_byte_length(name, value, want)
  check("[name] size", value.size, want)
  check("[name] length", value.length, want)
  # The removed native IC ignored surplus arguments; source dispatch retains
  # that public compatibility behavior.
  check("[name] size extras", value.size(1, 2), want)
  check("[name] length extras", value.length(1, 2), want)

check_byte_length("inline empty", "", 0)
check_byte_length("inline UTF-8 bytes", "é", 2)
check_byte_length("slab UTF-8 bytes", "ééé", 6)
check_byte_length("heap", heap_long, 80)
check_byte_length("rope", rope, 80)
check_byte_length("inline symbol", "sym".to_sym, 3)
check_byte_length("slab symbol", "symbol".to_sym, 6)
check_byte_length("heap symbol", heap_long.to_sym, 80)

# String/Symbol#to_s is the exact low-bit clear shared by the 0xF9 runtime
# representation. Check identity for every String storage tier and exact
# Symbol -> String bits for both supported Symbol tiers.
inline_values = ["", "a", "12345"]
slab_values = ["123456", "a slab-backed string"]
heap_values = ["".concat("h"), "h" * 80]

si = 0
while si < inline_values.size
  value = inline_values[si]
  check("inline to_s content", value.to_s, value)
  check("inline to_s identity", wvalue_bits(value.to_s), wvalue_bits(value))
  si += 1

si = 0
while si < slab_values.size
  value = slab_values[si]
  check("slab to_s content", value.to_s, value)
  check("slab to_s identity", wvalue_bits(value.to_s), wvalue_bits(value))
  si += 1

si = 0
while si < heap_values.size
  value = heap_values[si]
  check("heap to_s content", value.to_s, value)
  check("heap to_s identity", wvalue_bits(value.to_s), wvalue_bits(value))
  si += 1

to_s_rope = ("l" * 40) + ("r" * 41)
rope_first = to_s_rope.to_s
rope_second = to_s_rope.to_s
check("rope to_s content", rope_first, ("l" * 40) + ("r" * 41))
check("rope to_s cached flat identity", wvalue_bits(rope_first), wvalue_bits(rope_second))
check("rope to_s String result", type(rope_first), "String")

inline_symbol = "abc".to_sym
slab_symbol = "symbol-slab".to_sym
check("inline symbol to_s content", inline_symbol.to_s, "abc")
check("inline symbol bit clear", wvalue_bits(inline_symbol.to_s), wvalue_bits(inline_symbol) & -2)
check("slab symbol to_s content", slab_symbol.to_s, "symbol-slab")
check("slab symbol bit clear", wvalue_bits(slab_symbol.to_s), wvalue_bits(slab_symbol) & -2)
check("symbol to_s result type", type(slab_symbol.to_s), "String")

<< "string_native_spec: all checks passed"
