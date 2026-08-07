# Engine-parity spec for the exact-tag overload gate (B3/Phase 1) and its
# HAND-COPIED interpreter mirror.
#
# Lowering emits an inline NaN-box tag compare for `(BigInt)`-typed overload
# gates (overload_exact_tag_test, lowering/types.w); the interpreter mirrors
# the same rule by hand in overload_matches_args? (interpreter.w) because no
# shared module exists between the two. This spec is the guard on that copy:
# every check must produce identical output interpreted and compiled.
#   bin/tungsten spec/compiler/overload_exact_tag_parity_spec.w
#   bin/tungsten -o /tmp/ovl_parity spec/compiler/overload_exact_tag_parity_spec.w && /tmp/ovl_parity
#
# Covered per the plan's verification item 8: a subclass receiver, an
# abstract-param `(Number)` catch-all arm, and every operand shape whose
# routing the exact-tag rule could plausibly change (int, BigInt positive/
# negative/tag-flipped/multi-limb, float, decimal, instance).

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

+ TagBox
  -> combine/1(BigInt)
    "bigint-arm"
  -> combine/1(Number)
    "number-arm"

# Subclass receiver: the dispatcher is inherited; selection must behave
# identically through the subclass.
+ TagBoxKid < TagBox
  -> kid?
    true

b = TagBox.new
k = TagBoxKid.new

big = 10 ** 30
neg = 0 - big

check("int.number_arm", b.combine(5), "number-arm")
check("float.number_arm", b.combine(2.5), "number-arm")
check("decimal.number_arm", b.combine(2.5.to_d), "number-arm")
check("big_pos.bigint_arm", b.combine(big), "bigint-arm")
check("big_neg.bigint_arm", b.combine(neg), "bigint-arm")
check("big_flip.bigint_arm", b.combine(neg.abs), "bigint-arm")
check("big_multi.bigint_arm", b.combine(big * big), "bigint-arm")
check("i48_max.number_arm", b.combine(140737488355327), "number-arm")
check("subclass_recv.int", k.combine(7), "number-arm")
check("subclass_recv.big", k.combine(big), "bigint-arm")

# An instance argument matches neither arm's tag/tower — it must fall through
# to `super` (bodyless here), never crash into the BigInt arm.
+ NoNum
  -> label
    "nonum"

# Number-only group beside the BigInt group: the ancestry path all other
# names keep. `(Vector)`-style user classes gate through w_value_is_a.
+ VecLike
  -> v?
    true

+ TagSort
  -> pick/1(VecLike)
    "vec-arm"
  -> pick/1(Number)
    "num-arm"

s = TagSort.new
check("ancestry.vec_arm", s.pick(VecLike.new), "vec-arm")
check("ancestry.num_int", s.pick(3), "num-arm")
check("ancestry.num_big", s.pick(big), "num-arm")
