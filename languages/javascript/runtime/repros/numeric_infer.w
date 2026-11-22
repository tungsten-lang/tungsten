# prim returns its untyped argument on one path and a Float on the other; the compiled
# engine infers a Float return type, so prim(Big.new(3)) dies with
# "runtime error: expected numeric type". run --interpret prints 3.
+ Big
  ro :v
  -> new(@v)
-> prim(v)
  return v if v.is_a?(Big)
  ~1.0
p = prim(Big.new(3))
<< p.v
