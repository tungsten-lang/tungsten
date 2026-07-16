# Deliberately no `use`, literal, typed array, ccall, or argv() call: ARGV alone
# must schedule Array for the process-created receiver.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

value = ARGV
check("ARGV.size", value.size, 3)
check("ARGV.cap", value.cap >= 3, true)
check("ARGV.empty", value.empty?, false)
check("ARGV.first", value.first, "alpha")
check("ARGV.last", value.last(1, 2, 3), "gamma")

<< "autoload.argv_constant: ok"
