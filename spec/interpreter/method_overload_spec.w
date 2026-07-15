# Interpreter parity for exact-arity lookup, bare self calls, registration-
# order fallback, and same-arity replacement on a reopened class.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

+ InterpreterOverloadProbe
  # Arity one is intentionally registered first: unmatched extra arguments
  # must fall back here, just like compiled runtime method lookup.
  -> pick(value)
    "old:" + value

  -> pick
    "zero"

  -> pick_inside(value)
    pick(value)

+ InterpreterOverloadProbe
  # Replacing arity one must update its overload slot without disturbing the
  # distinct zero-argument definition.
  -> pick(value)
    "new:" + value

probe = InterpreterOverloadProbe.new()
check("exact zero", probe.pick, "zero")
check("exact one", probe.pick("x"), "new:x")
check("bare exact one", probe.pick_inside("y"), "new:y")
check("extra fallback", probe.pick("z", "ignored", 99), "new:z")

+ InterpreterOverloadBase
  -> inherited
    "base-zero"

+ InterpreterOverloadChild < InterpreterOverloadBase
  -> inherited(value)
    "child:" + value

child = InterpreterOverloadChild.new()
check("superclass exact before fallback", child.inherited, "base-zero")
check("subclass exact", child.inherited("x"), "child:x")
check("subclass fallback", child.inherited("y", "ignored"), "child:y")

<< "method_overload_spec: all checks passed"
