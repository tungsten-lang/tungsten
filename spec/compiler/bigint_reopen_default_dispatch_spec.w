# A core-class reopen must neither perturb runtime superclass initialization
# nor let an ancestor's smaller exact-arity stub hide the core class's
# default-compatible override.

-> check(name, got, expected)
  if got != expected
    << "FAIL " + name + ": got=" + got.to_s() + " expected=" + expected.to_s()
    exit(1)
  << "PASS " + name

+ DefaultDispatchBase
  -> label
    "base"

  -> .kind
    "base"

+ DefaultDispatchChild < DefaultDispatchBase
  -> label(value = "child")
    value

  -> .kind(value = "child")
    value

+ BigInt
  -> reopen_dispatch_probe
    73

child = DefaultDispatchChild.new()
check("subclass trailing default", child.label(), "child")
check("subclass static trailing default", DefaultDispatchChild.kind(), "child")

x = 10 ** 76 + 3
check("bigint type after reopen", type(x), "BigInt")
check("bigint default to_s after reopen", x.to_s(), "10000000000000000000000000000000000000000000000000000000000000000000000000003")
check("bigint explicit-base to_s after reopen", x.to_s(16), "161bcca7119915b50764b4abe86529797775a5f1719510000000000000000003")
check("reopened method", x.reopen_dispatch_probe(), 73)

<< "PASS bigint reopen default dispatch"
