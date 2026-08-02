# Tag-sign negation (encoding v4, R3): `-x` and `abs` on a BigInt hand out
# the SAME buffer with the overlay bit (bit 47 of the boxed value) flipped —
# O(1), zero allocation. The effective sign is header XOR overlay.
#
# The semantic this pins: a tag-flipped value is a LINKED VIEW, `-x` as a
# standing relationship. Immutable arithmetic can't tell the difference (a
# view equals the negation, forever). Bang methods CAN: `x.neg!` flips the
# shared header, so every view's effective value negates together — which
# is exactly the linked-view arithmetic (`y = -x; x.neg!` leaves y equal to
# the NEW -x, i.e. the OLD x). This extends the documented `x + 0` sharing
# caveat on bang methods; it is intentional, not an accident.

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

# negation across widths equals the arithmetic (copy-path) reference
(1..48).each -> (k)
  x = (1 << (64 * k - 9)) + k * 7717 + 3
  nx = -x
  check("neg.matches_sub@" + k.to_s(), nx.to_s(), (0 - x).to_s())
  check("neg.involution@" + k.to_s(), (-nx).to_s(), x.to_s())
  check("neg.add_cancels@" + k.to_s(), (nx + x).to_s(), "0")

x = (1 << 300) + 12345
nx = -x

# the flip is an alias: x's buffer is marked shared
check("neg.marks_shared", ccall("w_bigint_shared_value", x), "true")

# predicates compose the overlay
check("pred.nx_negative", nx.negative?.to_s(), "true")
check("pred.nx_not_positive", nx.positive?.to_s(), "false")
check("pred.x_positive", x.positive?.to_s(), "true")
check("pred.parity_unchanged", nx.odd?.to_s(), x.odd?.to_s())

# formatting, comparison, hashing see the effective value
check("tostr.flipped", nx.to_s(), "-" + x.to_s())
check("cmp.flipped", (nx < 0).to_s(), "true")
check("cmp.orders", (nx < x).to_s(), "true")
h = {}
h[nx] = "v"
check("hash.value_keyed", h[0 - x], "v")

# abs: zero-copy on the flipped view
check("abs.of_flipped", nx.abs().to_s(), x.to_s())
check("abs.of_positive_identity", x.abs().to_s(), x.to_s())

# arithmetic with flipped operands on both sides
y = (1 << 200) + 999
check("arith.mul_signs", ((-x) * (-y)).to_s(), (x * y).to_s())
check("arith.mixed_add", ((-x) + y).to_s(), (y - x).to_s())
check("arith.div_sign", ((0 - (x * y)) / y).to_s(), (0 - x).to_s())

# linked-view semantics under bang mutation (the extended caveat)
a = (1 << 128) + 41
v = -a
snapshot = a.to_s()
a.neg!
check("bang.receiver_negated", a.to_s(), "-" + snapshot)
check("bang.view_follows", v.to_s(), snapshot)
a.neg!
check("bang.restored", v.to_s(), "-" + snapshot)

# abs! composes with the receiver's own overlay: it lands the RECEIVER on
# effectively-positive, and linked views stay -receiver
b = (1 << 128) + 77
before = b.to_s()
w = -b
w.abs!
# abs! landed the RECEIVER w on effectively-positive |b|; the source view b
# follows as the linked -w (the header itself went negative).
check("absbang.flipped_receiver", w.to_s(), before)
check("absbang.source_view", b.to_s(), "-" + before)

<< "bigint_tag_sign_spec: all checks passed"
