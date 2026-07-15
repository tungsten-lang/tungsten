+ HintedCompatTarget
  -> get(index)
    index + 100

+ HintedCompatHolder
  -> new(value)
    @receiver = value ## HintedCompatTarget

  -> get(index)
    @receiver.get(index)

+ HintedCompatCheck
  -> .call(name, got, expected)
    if got != expected
      << "FAIL " + name + ": got=" + got.to_s() + " expected=" + expected.to_s()
      exit(1)
    << "PASS " + name

source = HintedCompatHolder.new(HintedCompatTarget.new())
native = HintedCompatHolder.new([11, 42])
HintedCompatCheck.call("hinted source miss", source.get(1), 101)
HintedCompatCheck.call("hinted source hit", source.get(2), 102)
HintedCompatCheck.call("hinted native miss", native.get(1), 42)
HintedCompatCheck.call("hinted native hit", native.get(0), 11)
<< "PASS hinted argc-one compatibility"
