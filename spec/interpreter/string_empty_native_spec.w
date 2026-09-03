# Tree-walker parity for the source-only String/Symbol#empty? method. Ropes
# must be flattened before `$value` reaches the source body, just as compiled
# cached dispatch does.

# Surplus arguments are an error on both engines (E_LOWER_ARITY at compile
# time where the callee is known; the interpreter raises at the call).
-> surplus_rejected?(f)
  begin
    f.call
    false
  rescue surplus_error
    true

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

check("inline empty", "".empty?, true)
check("inline nonempty", "abc".empty?, false)
check("slab nonempty", "a slab-backed string".empty?, false)
check("heap nonempty", ("h" * 80).empty?, false)
check("derived empty", "   ".strip.empty?, true)

left = "l" * 40
right = "r" * 40
check("rope nonempty", (left + right).empty?, false)

check("empty symbol", "".to_sym.empty?, true)
check("nonempty symbol", "symbol".to_sym.empty?, false)
check("String surplus arguments rejected", surplus_rejected?(->() "".empty?(123, "ignored")), true)
check("Symbol surplus arguments rejected", surplus_rejected?(->() "".to_sym.empty?(123)), true)

<< "PASS interpreter String/Symbol#empty? source parity"
