# Tree-walker parity for source-only Float rounding/root/square leaves.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

check("floor positive", (~3.7).floor, 3)
check("floor negative", (~-3.7).floor, -4)
check("ceil positive", (~3.7).ceil, 4)
check("ceil negative", (~-3.7).ceil, -3)
check("round positive tie", (~2.5).round, 3)
check("round negative tie", (~-2.5).round, -3)
check("round surplus", (~2.5).round(1, 2, 3), 3)

check("sqrt finite", (~9.0).sqrt, ~3.0)
check("sqrt negative zero bits", wvalue_bits((~-0.0).sqrt),
      wvalue_bits(~-0.0))
check("sqrt surplus", (~9.0).sqrt(1, 2), ~3.0)

check("sq finite", (~-2.5).sq, ~6.25)
check("sq negative zero bits", wvalue_bits((~-0.0).sq),
      wvalue_bits(~0.0))
check("sq surplus", (~-2.5).sq(1, 2), ~6.25)

positive_infinity = Math.exp(~10000.0)
not_a_number = Math.sqrt(~-1.0)
check("sqrt infinity", positive_infinity.sqrt.infinite?, true)
check("sqrt negative is NaN", (~-1.0).sqrt.nan?, true)
check("sqrt NaN", not_a_number.sqrt.nan?, true)
check("sq infinity", positive_infinity.sq.infinite?, true)
check("sq NaN", not_a_number.sq.nan?, true)

<< "PASS Float remaining source interpreter parity"
