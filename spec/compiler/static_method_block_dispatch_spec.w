# Static class calls must place an attached block in the method's final block
# slot, after any omitted optional positional parameters.

-> check(name, actual, expected)
  if actual != expected
    << "FAIL " + name + ": got=" + actual.to_s + " expected=" + expected.to_s
    exit 1

+ StaticBlockProbe
  -> .explicit(prefix = "default", &)
    if block?
      return yield prefix
    "plain:" + prefix

  -> .implicit(prefix = "default")
    if block?
      return yield prefix
    "plain:" + prefix

  -> .bare
    explicit() -> (value)
      "bare:" + value

+ StaticBlockChild < StaticBlockProbe

check("explicit no block default", StaticBlockProbe.explicit(), "plain:default")
check("explicit no block argument", StaticBlockProbe.explicit("given"), "plain:given")
check("explicit block default", StaticBlockProbe.explicit() -> (value)
  "block:" + value
, "block:default")
check("explicit block argument", StaticBlockProbe.explicit("given") -> (value)
  "block:" + value
, "block:given")
check("implicit block default", StaticBlockProbe.implicit() -> (value)
  "implicit:" + value
, "implicit:default")
check("bare static block", StaticBlockProbe.bare(), "bare:default")
check("inherited static block", StaticBlockChild.explicit() -> (value)
  "child:" + value
, "child:default")

<< "static_method_block_dispatch_spec: all checks passed"
