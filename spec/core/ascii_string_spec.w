# ASCII literals and representation-invariant ASCII metadata.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

name = "interpolated"
check("single literal", 'plain ASCII', "plain ASCII")
check("single no interpolation", 'value=[name]', "value=\[name]")
check("single no escapes", 'line\nnext', "line\\nnext")

# All immutable storage tiers expose the same content-derived predicate.
check("inline single ASCII", 'abc'.ascii?, true)
check("slab single ASCII", '123456'.ascii?, true)
check("heap single ASCII", 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789--heap'.ascii?, true)
check("inline double ASCII", "abc".ascii?, true)
check("slab double ASCII", "123456".ascii?, true)
check("Unicode is not ASCII", "é".ascii?, false)
check("slab Unicode is not ASCII", "ééé".ascii?, false)
check("heap Unicode is not ASCII", ("é" * 40).ascii?, false)

ascii_rope = ("a" * 40) + ("b" * 40)
unicode_rope = ("a" * 40) + ("é" * 40)
check("ASCII rope", ascii_rope.ascii?, true)
check("Unicode rope", unicode_rope.ascii?, false)

builder = StringBuffer()
check("empty StringBuffer result", builder.to_s.ascii?, true)
builder << 'ASCII'
builder << " only"
check("ASCII StringBuffer result", builder.to_s.ascii?, true)
builder << " é"
check("Unicode StringBuffer result", builder.to_s.ascii?, false)

# [] is code-point indexing. The ASCII representation takes its direct byte
# path; non-ASCII UTF-8 walks code-point boundaries. Raw slice stays byte-based.
check("ASCII index", 'abcdef'[2], "c")
check("ASCII negative index", 'abcdef'[-1], "f")
check("Unicode first index", "éx"[0], "é")
check("Unicode second index", "éx"[1], "x")
check("Unicode negative index", "éx"[-1], "x")
check("UTF-8 byte size", "éx".size, 3)
check("raw byte slice code point", "éx".slice(0, 2), "é")
check("raw byte slice ASCII tail", "éx".slice(2, 1), "x")

<< "ascii_string_spec: all checks passed"
