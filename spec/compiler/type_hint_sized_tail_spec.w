# A sized trailing hint `## T[m * n]` is one type: the operator inside the
# brackets is part of the size, not an operation after the hint.
# Regression: E_PARSE_TYPE_HINT_OPERATOR split the hint at its first space,
# read `T[m` as the type and `* n]` as a stray operator, and rejected
# core/vector.w and core/matrix.w, so Vector and Matrix failed to load.
#
# Run:
#   bin/tungsten spec/compiler/type_hint_sized_tail_spec.w
#   bin/tungsten run --interpret spec/compiler/type_hint_sized_tail_spec.w

-> check(name, got, want)
  if got != want
    << "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
    exit 1
  << "PASS " + name

m = 2
n = 3
xs = [1, 2, 3, 4, 5, 6] ## i64[m * n]
check("sized hint with a product parses and lowers", xs.size, 6)
