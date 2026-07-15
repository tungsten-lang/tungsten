+ ExactArgcOneProbe
  -> get(index)
    index + 100

+ ExactArgcOneHolder
  -> new
    @receiver = ExactArgcOneProbe.new()

  -> get(index)
    @receiver.get(index)

+ InvalidatedArgcOneHolder
  -> new
    @receiver = ExactArgcOneProbe.new()

  -> replace(value)
    @receiver = value

  -> get(index)
    @receiver.get(index)

-> exact_argc_one_check(name, got, expected)
  if got != expected
    << "FAIL " + name + ": got=" + got.to_s() + " expected=" + expected.to_s()
    exit(1)
  << "PASS " + name

exact = ExactArgcOneHolder.new()
exact_argc_one_check("exact source miss", exact.get(1), 101)
exact_argc_one_check("exact source hit", exact.get(2), 102)

invalidated = InvalidatedArgcOneHolder.new()
exact_argc_one_check("invalidated source", invalidated.get(3), 103)
invalidated.replace([11, 42])
exact_argc_one_check("invalidated native", invalidated.get(1), 42)

<< "PASS exact ivar argc-one cached dispatch"
