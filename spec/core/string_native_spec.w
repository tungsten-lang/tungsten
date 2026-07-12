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

<< "string_native_spec: all checks passed"
