# Deliberately no `use`, literal, typed array, ccall, or ARGV constant: argv()
# alone must schedule Array for the process-created receiver.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

value = argv()
check("argv.size", value.size, 3)
check("argv.cap", value.cap >= 3, true)
check("argv.empty", value.empty?, false)
check("argv.first", value.first, "alpha")
check("argv.last", value.last(1, 2, 3), "gamma")

<< "autoload.argv_call: ok"
