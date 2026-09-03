# BitOrdered trait (core/traits/bit_ordered.w): a class whose i64
# `wvalue_bits` order IS its value order gets <=>, <, <=, >, >= from the
# trait (nil <=> across classes), and — because the trait composes
# `with BitEqual` — should also get ==, !=, eql? and hash. The trait is not
# in the autoload manifest, so user code loads both files explicitly.
#
# COMPILED-ONLY lane: the native interpreter cannot even parse `with` inside
# a trait body (it reports "Undefined variable or method 'with'"), so
# `use core/traits/bit_ordered` fails there. See the BUG notes at the foot
# of this file.
#
#   bin/tungsten -o /tmp/traits-bit-ordered-spec spec/core/traits_bit_ordered_spec.w && /tmp/traits-bit-ordered-spec

use core/traits/bit_equal
use core/traits/bit_ordered

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

# Seconds since midnight: bit order == chronological order.
+ Clock
  is BitOrdered

  -> new(seconds)
    @seconds = seconds

  -> wvalue_bits
    @seconds

+ Stamp
  is BitOrdered

  -> new(bits)
    @bits = bits

  -> wvalue_bits
    @bits

dawn = Clock.new(6 * 3600)
noon = Clock.new(12 * 3600)
noon_again = Clock.new(12 * 3600)
dusk = Clock.new(18 * 3600)
before_epoch = Clock.new(-5)
epoch = Clock.new(0)

# <=> is the sign of the bit difference
check("cmp.less", (dawn <=> noon) == -1)
check("cmp.greater", (dusk <=> noon) == 1)
check("cmp.equal", (noon <=> noon_again) == 0)
check("cmp.negative_bits", (before_epoch <=> epoch) == -1)
check("cmp.cross_class_nil", (noon <=> Stamp.new(12 * 3600)) == nil)

# the derived comparisons
check("lt.true", dawn < noon)
check("lt.false_equal", !(noon < noon_again))
check("lt.false_greater", !(dusk < noon))
check("le.true_less", dawn <= noon)
check("le.true_equal", noon <= noon_again)
check("le.false", !(dusk <= noon))
check("gt.true", dusk > noon)
check("gt.false_equal", !(noon > noon_again))
check("ge.true_greater", dusk >= noon)
check("ge.true_equal", noon >= noon_again)
check("ge.false", !(dawn >= noon))
check("order.negative_before_zero", before_epoch < epoch)

# total order: sort by the bits
sorted = [dusk, dawn, noon].sort
check("sort.ascending",
      sorted[0].wvalue_bits == 6 * 3600 &&
      sorted[1].wvalue_bits == 12 * 3600 &&
      sorted[2].wvalue_bits == 18 * 3600)
check("sort.min_max", [dusk, dawn, noon].min.wvalue_bits == 6 * 3600 &&
                      [dusk, dawn, noon].max.wvalue_bits == 18 * 3600)

# antisymmetry and transitivity
check("cmp.antisymmetric", (dawn <=> dusk) == 0 - (dusk <=> dawn))
check("lt.transitive", dawn < noon && noon < dusk && dawn < dusk)

# BitOrdered composes `with BitEqual` ("Subsumes BitEqual"), so equality
# and hashing must be bit-level too.
# BUG: `with <Trait>` composition is unimplemented in BOTH engines.
#   compiled — the composed methods are never mixed in: `noon == noon_again`
#     is false (identity) and `noon.hash` is an identity hash, while a class
#     that says `is BitEqual` directly works.
#   interpreted — `with` inside a trait body does not even parse.
# Repro (compiled prints a "no method greet" error, interpreted prints
# "Undefined variable or method 'with'"):
#   trait Greet
#     -> greet
#       "hi"
#   trait Polite
#     with Greet
#     -> polite
#       self.greet + "!"
#   + P
#     is Polite
#   << P.new.polite
# check("eq.same_bits", noon == noon_again)
# check("ne.different_bits", noon != dusk)
# check("eql.same_bits", noon.eql?(noon_again))
# check("hash.is_bits", noon.hash == 12 * 3600)
# check("hash.equal_values", noon.hash == noon_again.hash)
# check("cross.eq_false", !(noon == Stamp.new(12 * 3600)))

<< "traits_bit_ordered_spec: all checks passed"
