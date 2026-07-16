# Native-factory autoload probe: receiver shape is unknowable from the AST.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

value = ccall("w_float_remaining_case", 14) # +2.5
check("factory floor", value.floor, ccall("w_float_remaining_ref_floor", value))
check("factory ceil", value.ceil, ccall("w_float_remaining_ref_ceil", value))
check("factory round", value.round, ccall("w_float_remaining_ref_round", value))
check("factory sqrt bits", wvalue_bits(value.sqrt),
      wvalue_bits(ccall("w_float_remaining_ref_sqrt", value)))
check("factory sq bits", wvalue_bits(value.sq),
      wvalue_bits(ccall("w_float_remaining_ref_sq", value)))

<< "PASS Float remaining native-factory autoload"
