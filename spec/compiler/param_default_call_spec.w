# A parameter default that is a call (or any assignable expression) ends at
# the next comma.
#
# parse_param read the default with parse_expression, whose multiple-assign
# detection saw `g(), c = 2` in `-> f(a, b = g(), c = 2)` as `g(), c = 2`:
# parameter c disappeared and `f(1, 2, 3)` was rejected for arity. A literal
# default (`b = 1`) was never affected, since a literal is no assign target.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)
  << "PASS [name]"

-> g
  5

+ Maker
  -> .make
    7

-> f(a, b = g(), c = 2)
  a + b + c

-> h(a, b = Maker.make, c = 2, d = g())
  a + b + c + d

-> k(a, b: Maker.make, c: 3)
  a + b + c

+ Box
  -> new(@w, @q = Maker.make, s = 2)
    @s = s

  ro :w, :q, :s

check("all arguments given", f(1, 2, 3), 6)
check("call default used", f(1), 8)
check("call default, later default used", f(1, 10), 13)
check("class-method default", h(1), 1 + 7 + 2 + 5)
check("class-method default, all given", h(1, 2, 3, 4), 10)
check("keyword default after a call default", k(1), 11)
check("constructor ivar default", Box.new(1).q, 7)
check("constructor param after a call default", Box.new(1, 3, 4).s, 4)

<< "ALL PASS param_default_call_spec"
