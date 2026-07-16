# Literal-only autoload probe: no explicit Float import or class reference.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

check("floor", (~3.7).floor, 3)
check("ceil", (~3.7).ceil, 4)
check("round positive tie", (~2.5).round, 3)
check("round negative tie", (~-2.5).round, -3)
check("sqrt", (~9.0).sqrt, ~3.0)
check("sq", (~-2.5).sq, ~6.25)
check("sqrt signed zero", wvalue_bits((~-0.0).sqrt), wvalue_bits(~-0.0))

<< "PASS Float remaining literal autoload"
