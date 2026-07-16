use core/string_native

# Tree-walker gate for shared String/Symbol methods and primitive identity.

-> fail(name, got, expected)
  << "FAIL interpreter [name] got=[got] expected=[expected]"
  exit(1)

-> check(name, got, expected)
  if got != expected
    fail(name, got, expected)

-> check_both(name, value, expected)
  check("[name].size", value.size, expected)
  check("[name].length", value.length, expected)
  check("[name].size.extra", value.size(1, 2, 3), expected)
  check("[name].length.extra", value.length(1, 2, 3), expected)

check_both("inline.empty", "", 0)
check_both("inline.ascii", "abcde", 5)
check_both("inline.utf8-byte-count", "é", 2)
check_both("slab.utf8-byte-count", "ééé", 6)

heap = "h" * 80
check_both("heap", heap, 80)
rope = ("l" * 40) + ("r" * 41)
check_both("rope", rope, 81)

# Call to_sym first on a distinct fresh WRope. The interpreter's direct native
# bridge must flatten before w_str_to_sym sets the Symbol bit; otherwise that
# bit is applied to the generic rope pointer itself.
rope_for_symbol = ("q" * 40) + ("z" * 41)
rope_symbol = rope_for_symbol.to_sym
check_both("symbol.fresh-rope", rope_symbol, 81)
check("symbol.fresh-rope.content", rope_symbol.to_s, ("q" * 40) + ("z" * 41))

nul_bytes = u8[80]
i = 0
while i < 80
  nul_bytes[i] = 65
  i += 1
nul_bytes[0] = 0
nul_bytes[31] = 0
nul_bytes[79] = 0
nul_heap = ccall("w_string_from_byte_array", nul_bytes)
check_both("heap.embedded-nul", nul_heap, 80)

check_both("symbol.empty", "".to_sym, 0)
check_both("symbol.inline", "sym".to_sym, 3)
check_both("symbol.slab", "symbol".to_sym, 6)
check_both("symbol.heap", heap.to_sym, 80)
check_both("symbol.embedded-nul", nul_heap.to_sym, 80)

# The tree walker passes a trailing block to the callee; no-block source/native
# methods ignore it here (compiled lowering separately rewrites to result.each).
string_hits = 0
string_result = "abc".size -> (ignored)
  string_hits += 1
check("string block hits", string_hits, 0)
check("string block result", string_result, 3)

symbol_hits = 0
symbol_result = "xy".to_sym.length -> (ignored)
  symbol_hits += 1
check("symbol block hits", symbol_hits, 0)
check("symbol block result", symbol_result, 2)

# String is explicitly registered above on shared compiled key 0xF9. The tree
# walker has separate host identities, but pin the same public contract and
# stable class-object behavior as the compiled w_class_of regression.
check("identity.String registration", "".empty?, true)
identity_symbol = :identity
check("identity.Symbol type", type(identity_symbol), "Symbol")
check("identity.Symbol class_name", identity_symbol.class_name, "Symbol")
identity_symbol_class = identity_symbol.class
check("identity.Symbol class.name", identity_symbol_class.name, "Symbol")
check("identity.Symbol class stable", identity_symbol.class == identity_symbol_class, true)
check("identity.Symbol is_a name", identity_symbol.is_a?("Symbol"), true)
check("identity.Symbol is_a class", identity_symbol.is_a?(identity_symbol_class), true)
check("identity.Symbol not String", identity_symbol.is_a?("String"), false)

identity_string = "identity"
check("identity.String type", type(identity_string), "String")
check("identity.String class_name", identity_string.class_name, "String")
identity_string_class = identity_string.class
check("identity.String class.name", identity_string_class.name, "String")
check("identity.String class stable", identity_string.class == identity_string_class, true)
check("identity.String is_a name", identity_string.is_a?("String"), true)
check("identity.String is_a class", identity_string.is_a?(identity_string_class), true)
check("identity.String not Symbol", identity_string.is_a?("Symbol"), false)
check("identity classes distinct", identity_string_class == identity_symbol_class, false)
check("identity.Symbol stable after String", identity_symbol.class == identity_symbol_class, true)

<< "PASS String/Symbol interpreter: size/length representations, rope-to-sym, and stable class/is_a identity"
