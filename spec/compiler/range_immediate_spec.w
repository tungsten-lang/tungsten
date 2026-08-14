# Immediate Range (Location mode 11) — compiled-engine end-to-end.
#
# Producers are wired: lower_range routes escaped range literals through
# w_range_make, so `lo..hi` itself mints the packed value (eager Array
# only for non-encodable bounds). Values must behave as first-class
# Ranges — type identity, method dispatch through the core Range class
# over the packed bits, equality by canonical encoding, and Hash-key
# round-trips. The raw funnel (ccall w_range_imm_try_w) is asserted too,
# including its miss signal (nil → caller takes the heap path).

use ../../core/range

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

-> rng(lo, hi, excl)
  ccall("w_range_imm_try_w", lo, hi, excl)

# -- Producer: escaped range literals mint the immediate form --
-> hold(v)
  v

lit = hold(3..7)
check("lit type", type(lit), "Range")
check("lit first", lit.first, 3)
check("lit last", lit.last, 7)
check("lit sum", lit.sum, 25)
check("lit interp", "[lit]", "3..7")
xlit = hold(1...10)
check("xlit type", type(xlit), "Range")
check("xlit size", xlit.size, 9)
check("lit eq funnel", lit == rng(3, 7, false), true)
check("lit to_a", lit.to_a, [3, 4, 5, 6, 7])
check("lit index", lit[1], 4)
check("lit index neg", lit[-1], 7)
check("lit index oob", lit[9], nil)
neg = hold(-5..5)
check("neg lit type", type(neg), "Range")
check("neg lit start", neg.start, -5)
# Non-encodable bounds fall back to the eager Array (historical form).
wide = hold(5000000..5000004)
check("fallback type", type(wide), "Array")
check("fallback size", wide.size, 5)
check("fallback first", wide.first, 5000000)

# -- Loop shape (start 0/1, wide end) --
r = rng(3, 7, false)
check("type", type(r), "Range")
check("interp", "[r]", "3..7")

check("start", r.start, 3)
check("first", r.first, 3)
check("finish", r.finish, 7)
check("last", r.last, 7)
check("size", r.size, 5)
check("count", r.count, 5)
check("exclusive?", r.exclusive?, false)
check("empty?", r.empty?, false)
check("min", r.min, 3)
check("max", r.max, 7)
check("sum", r.sum, 25)
check("include lo", r.include?(3), true)
check("include hi", r.include?(7), true)
check("include out", r.include?(8), false)
check("member?", r.member?(5), true)

big = rng(0, 1099511627775, false)   # 2^40 - 1: loop-shape ceiling
check("big last", big.last, 1099511627775)
check("big size", big.size, 1099511627776)
check("big sum promotes", big.sum, 604462909806764831539200)   # 2^79 - 2^39

x = rng(1, 10, true)
check("excl last", x.last, 9)
check("excl size", x.size, 9)
check("excl sum", x.sum, 45)
check("excl interp", "[x]", "1...10")

# -- Span shape (signed bounds) --
s = rng(-5, 5, false)
check("span start", s.start, -5)
check("span last", s.last, 5)
check("span size", s.size, 11)
check("span sum", s.sum, 0)
check("span include", s.include?(-5), true)

e = rng(0, -1, false)   # negative-index slice shape: empty via cascade
check("empty size", e.size, 0)
check("empty? empty", e.empty?, true)
check("empty min", e.min, nil)
check("empty max", e.max, nil)
check("empty sum", e.sum, 0)

# -- Enumerable over the packed bits --
acc = 0
r.each -> (k)
  acc = acc + k
check("each", acc, 25)
check("to_a", r.to_a, [3, 4, 5, 6, 7])
check("map", r.map -> (k) k * 2, [6, 8, 10, 12, 14])
check("select", s.select -> (k) k > 3, [4, 5])

# -- Equality: canonical bits --
check("eq", rng(3, 7, false) == rng(3, 7, false), true)
check("ne excl", rng(3, 7, false) == rng(3, 7, true), false)
check("ne bounds", rng(3, 7, false) == rng(3, 8, false), false)
check("ne array", rng(3, 7, false) == [3, 4, 5, 6, 7], false)

# -- Hash keys: equal-iff-equal-bits --
h = {}
h[rng(3, 7, false)] = "inc"
h[rng(3, 7, true)] = "exc"
check("hash key inc", h[rng(3, 7, false)], "inc")
check("hash key exc", h[rng(3, 7, true)], "exc")
check("hash key miss", h[rng(3, 8, false)], nil)
check("hash size", h.size, 2)

# -- Funnel misses report nil (caller takes the heap path) --
check("miss start", rng(2, 3000000, false), nil)
check("miss end", rng(0, 1099511627776, false), nil)

<< "PASS range_immediate_spec"
