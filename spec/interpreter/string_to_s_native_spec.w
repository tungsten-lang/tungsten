# Tree-walker mirror for the raw String/Symbol#to_s source body.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

inline = "abc"
slab = "a slab-backed interpreter string"
inline_result = inline.to_s
slab_result = slab.to_s

check("inline content", inline_result, inline)
check("inline identity", wvalue_bits(inline_result), wvalue_bits(inline))
check("slab content", slab_result, slab)
check("slab identity", wvalue_bits(slab_result), wvalue_bits(slab))

inline_symbol = :abc
slab_symbol = :a_slab_symbol
inline_symbol_result = inline_symbol.to_s
slab_symbol_result = slab_symbol.to_s

check("inline symbol content", inline_symbol_result, "abc")
check("inline symbol bit clear", wvalue_bits(inline_symbol_result), wvalue_bits(inline_symbol) & -2)
check("slab symbol content", slab_symbol_result, "a_slab_symbol")
check("slab symbol bit clear", wvalue_bits(slab_symbol_result), wvalue_bits(slab_symbol) & -2)

<< "string_to_s_native_spec: all checks passed"
