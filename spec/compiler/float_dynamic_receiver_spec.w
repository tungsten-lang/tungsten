# Every public Float leaf must survive receiver type erasure at a function
# boundary. This covers the native IC/source split as well as IEEE predicates.

-> check(name, got, want)
  if got == want
    << "PASS [name]"
  else
    << "FAIL [name] got=[got] want=[want]"
    exit 1

-> exercise(value)
  check("float.dynamic.to_f", value.to_f(), ~3.5)
  check("float.dynamic.abs", (0.0 - value).abs(), ~3.5)
  check("float.dynamic.floor", value.floor(), 3)
  check("float.dynamic.ceil", value.ceil(), 4)
  check("float.dynamic.round", value.round(), 4)
  check("float.dynamic.sqrt", value.sqrt() > ~1.87 && value.sqrt() < ~1.88, true)
  check("float.dynamic.sq", value.sq(), ~12.25)
  check("float.dynamic.truncate", value.truncate(), ~3.0)
  check("float.dynamic.nan", value.nan?(), false)
  check("float.dynamic.infinite", value.infinite?(), false)
  check("float.dynamic.finite", value.finite?(), true)

-> check_nonfinite(label, value, want_nan, want_infinite)
  check("float.dynamic." + label + ".nan", value.nan?(), want_nan)
  check("float.dynamic." + label + ".infinite", value.infinite?(), want_infinite)
  check("float.dynamic." + label + ".finite", value.finite?(), false)

exercise(~3.5)
check_nonfinite("infinity", Math.exp(~1000.0), false, true)
check_nonfinite("nan", Math.asin(~2.0), true, false)
