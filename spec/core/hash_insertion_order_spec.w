# Hash iteration order is insertion order — a guaranteed language semantic,
# identical across the native runtime, the C VM stage-0 host, and the Ruby
# tree-walker. Overwrites keep a key's position; a deleted-then-reinserted
# key moves to the end; order survives growth and delete churn.
#
# Comparisons use comma-joined .to_s signatures rather than array renderings:
# the engines agree on element text but not on array/symbol formatting.
#
# Run: `bin/tungsten -o /tmp/hio spec/core/hash_insertion_order_spec.w && /tmp/hio`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> key_sig(h)
  sig = ""
  h.each -> (k, v)
    if sig != ""
      sig = sig + ","
    sig = sig + k.to_s
  sig

-> keys_sig(h)
  sig = ""
  h.keys.each -> (k)
    if sig != ""
      sig = sig + ","
    sig = sig + k.to_s
  sig

-> vals_sig(h)
  sig = ""
  h.values.each -> (v)
    if sig != ""
      sig = sig + ","
    sig = sig + v.to_s
  sig

# -- Literal order is source order --
lit = {one: 1, two: 2, three: 3, four: 4}
check("hio.literal", keys_sig(lit), "one,two,three,four")
check("hio.literal.values", vals_sig(lit), "1,2,3,4")

# -- Mixed key kinds keep arrival order --
h = {}
h["banana"] = 1
h[:zeta] = 2
h[7] = 3
h["apple"] = 4
h[2] = 5
check("hio.mixed", keys_sig(h), "banana,zeta,7,apple,2")

# -- Overwrite keeps the key's position --
h[:zeta] = 20
check("hio.overwrite.pos", keys_sig(h), "banana,zeta,7,apple,2")
check("hio.overwrite.val", h[:zeta], 20)

# -- Delete removes without disturbing the rest --
h.delete(7)
check("hio.delete", keys_sig(h), "banana,zeta,apple,2")

# -- A deleted-then-reinserted key moves to the END --
h.delete(:zeta)
h[:zeta] = 99
check("hio.reinsert.end", keys_sig(h), "banana,apple,2,zeta")
check("hio.reinsert.val", h[:zeta], 99)

# -- New inserts after a delete land at the end, in order --
h["date"] = 6
check("hio.post_delete.append", keys_sig(h), "banana,apple,2,zeta,date")

# -- Order survives growth well past the initial table --
big = {}
expected = ""
i = 0
while i < 100
  key = "k" + i.to_s
  big[key] = i
  if expected != ""
    expected = expected + ","
  expected = expected + key
  i += 1
check("hio.growth.keys", keys_sig(big), expected)
check("hio.growth.size", big.size, 100)

# -- each yields in the same order as keys, values in the same order too --
check("hio.each.keys", key_sig(big), keys_sig(big))
each_vals = ""
big.each -> (k, v)
  if each_vals != ""
    each_vals = each_vals + ","
  each_vals = each_vals + v.to_s
check("hio.each.values", each_vals, vals_sig(big))

# -- merge: self's entries first, then other's new keys; collisions keep
#    self's position with other's value --
a = {x: 1, y: 2, z: 3}
b = {w: 10, y: 20}
m = a.merge(b)
check("hio.merge.order", keys_sig(m), "x,y,z,w")
check("hio.merge.collision", m[:y], 20)

# -- Delete churn: repeated delete+reinsert converges (rebuilds purge holes)
#    and always lands the reinserted key at the end --
churn = {a: 1, b: 2, c: 3}
i = 0
while i < 200
  churn.delete(:b)
  churn[:b] = i
  i += 1
check("hio.churn.order", keys_sig(churn), "a,c,b")
check("hio.churn.size", churn.size, 3)
check("hio.churn.val", churn[:b], 199)

# -- Emptying a hash completely and refilling starts fresh --
churn.delete(:a)
churn.delete(:c)
churn.delete(:b)
check("hio.emptied", churn.size, 0)
churn[:fresh] = 1
churn[:start] = 2
check("hio.refill", keys_sig(churn), "fresh,start")

<< "hash insertion order: all green"
