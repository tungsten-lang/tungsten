# `super(args)` into a parent method whose trailing parameters have defaults. The
# devirtualization registry holds only plain signatures, so such a super used to find no
# target and returned nil without calling the parent (found compiling JS-AOT's runtime,
# where JS:Function#define calls JS:Base#define(key, v, flags = ATTR_DEFAULT)).

-> check(name, got, want)
  if got != want
    << "FAIL " + name + ": got " + got.to_s() + ", want " + want.to_s()
    exit(1)
  << "PASS " + name

+ Base
  rw :log
  -> new
    @log = []
  -> put(key, flags = 7)
    @log.push(key + ":" + flags.to_s())
    flags
  -> two(a, b = 2, c = 3)
    a + b + c

+ Kid < Base
  -> new
    @log = []
  -> put(key, flags)
    super(key, flags)
  -> two(a)
    super(a) * 10

+ Grandkid < Kid
  -> new
    @log = []
  -> put(key, flags)
    super(key, flags) + 1

k = Kid.new
check("all arguments passed", k.put("a", 5), 5)
check("parent ran", k.log.join(","), "a:5")
check("missing trailing arguments take their defaults", k.two(1), 60)
g = Grandkid.new
check("through an intermediate override", g.put("b", 1), 2)
check("grandparent ran", g.log.join(","), "b:1")
