# Closures: lambdas as values, .call, captured mutable state, composition.
#
# Cross-engine parity spec (scripts/parity.sh).

-> apply(f, x)
  f.call(x)
dbl = ->(x) x * 2
<< "lambda [apply(dbl, 21)] [dbl.call(4)]"
add = ->(a, b) a + b
<< "lambda2 [add.call(1, 2)]"
-> make_counter
  n = [0]
  bump = ->(d) n.push(n.pop + d).last
  bump
ctr = make_counter()
ctr.call(1)
ctr.call(1)
<< "closure [ctr.call(10)]"
-> compose(f, g)
  ->(x) f.call(g.call(x))
inc = ->(x) x + 1
<< "compose [compose(dbl, inc).call(5)]"
fns = [dbl, inc]
<< "fns.map [fns.map -> item.call(10)]"
k = 3
addk = ->(x) x + k
<< "capture [addk.call(1)]"
