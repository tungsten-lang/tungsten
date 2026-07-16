use ../../compiler/lib/interpreter

CASE_COUNT = 20

interp = Interpreter.new()
interp.try_autoload_class("Float")
float_class = interp.primitive_runtime_class(~0.0)
if interp.lookup_method(float_class, "abs", 0) == nil
  << "FAIL interpreter did not autoload Float#abs from [interp.autoload_registry()["Float"]]"
  exit(1)
i = 0
while i < CASE_COUNT
  value = ccall("w_ref_float_leaf_case", i)
  got_abs = interp.dispatch_method(value, "abs", [], nil, nil)
  got_nan = interp.dispatch_method(value, "nan?", [], nil, nil)
  got_infinite = interp.dispatch_method(value, "infinite?", [], nil, nil)
  expected_abs = ccall("w_ref_float_leaf_abs", value)
  expected_nan = ccall("w_ref_float_leaf_nan_p", value)
  expected_infinite = ccall("w_ref_float_leaf_infinite_p", value)
  if wvalue_bits(got_abs) != wvalue_bits(expected_abs) || got_nan != expected_nan || got_infinite != expected_infinite
    << "FAIL interpreter Float leaves case=[i]"
    exit(1)
  i += 1

<< "interpreter correctness: ok ([CASE_COUNT * 3] exact public checks)"
