# Deliberately no `use`: a plain literal must schedule Array before its source
# query leaves are reached. Kept separate so another autoload trigger cannot
# accidentally mask this one.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

value = [10, 20, 30]
check("literal.size", value.size, 3)
check("literal.cap", value.cap >= 3, true)
check("literal.empty", value.empty?, false)
check("literal.first", value.first, 10)
check("literal.last", value.last, 30)
check("literal.extra", value.last(1, 2, 3), 30)

<< "autoload.literal: ok"
