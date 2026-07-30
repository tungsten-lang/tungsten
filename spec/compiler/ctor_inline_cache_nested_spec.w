# Constructor inline cache vs nested construction: Outer's init constructs
# an Inner. The ctor IC must publish OUTER's init under Outer's call-site
# key — publishing whatever init a NESTED `.new` selected (the TLS slot is
# shared) ran Inner's init on the second Outer instance, leaving
# @inner = Integer and @val unset. Iterations 2+ are the regression.

+ Inner
  -> new(@a)
  -> a
    @a

+ Outer
  -> new(v)
    @inner = Inner.new(v + 1)
    @val = v
  -> val
    @val
  -> inner_a
    @inner.a

i = 0
while i < 4
  o = Outer.new(10 + i)
  if o.val != 10 + i
    << "FAIL ctor IC nested: iteration [i] val=" + o.val.to_s()
    exit(1)
  if o.inner_a != 11 + i
    << "FAIL ctor IC nested: iteration [i] inner_a=" + o.inner_a.to_s()
    exit(1)
  i += 1

# Class-method body that constructs an object: the publish guard must not
# cache Inner's init under (Factory, "make")'s key — a poisoned entry made
# every later Factory.make return a raw Factory instance instead.
+ Factory
  -> .make(n)
    Inner.new(n * 2)

j = 0
while j < 3
  built = Factory.make(5 + j)
  if built.a != (5 + j) * 2
    << "FAIL static-method ctor publish: iteration [j] a=" + built.a.to_s()
    exit(1)
  j += 1

<< "ctor inline cache nested: ok"
